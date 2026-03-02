#!/usr/bin/env python3
"""
ea-sqlite-mcp.py — Cross-platform MCP server for Sparx EA .qea model files

Reads .qea (SQLite) model files directly — no EA installation required.
Runs natively on macOS, Linux, or Windows.

Capabilities:
  - Query elements by type, stereotype, name, package
  - Trace dependencies and impact chains
  - Validate ArchiMate relationships against metamodel
  - Extract diagram metadata and element placement
  - Generate model statistics and coverage reports
  - Export element inventories as structured data

Usage:
  pip install "mcp[cli]"
  python ea-sqlite-mcp.py

  Or with uv:
  uv run --with "mcp[cli]" python ea-sqlite-mcp.py

Claude Desktop config:
  {
    "mcpServers": {
      "EA Model Analyzer": {
        "command": "uv",
        "args": ["run", "--with", "mcp[cli]", "python", "/path/to/ea-sqlite-mcp.py"]
      }
    }
  }

Claude Code:
  claude mcp add --transport stdio "EA Model Analyzer" \
    -- uv run --with "mcp[cli]" python /path/to/ea-sqlite-mcp.py
"""

import sqlite3
import json
import os
from pathlib import Path
from typing import Optional
from collections import defaultdict

try:
    from mcp.server.fastmcp import FastMCP
except ImportError:
    print(
        "ERROR: mcp package not installed. Run: pip install 'mcp[cli]'",
        flush=True,
    )
    raise

# ---------------------------------------------------------------------------
# Server initialisation
# ---------------------------------------------------------------------------

mcp = FastMCP(
    name="EA-Model-Analyzer",
    instructions="""You are connected to an Enterprise Architect model analyzer.
    This server reads Sparx EA .qea files (SQLite databases) directly.
    All tools require a qea_path parameter pointing to the .qea model file.
    This is a READ-ONLY server — it cannot modify models (use the Sparx MCP
    server via the SSH bridge for write operations).""",
)

# Default model path (can be overridden per-call)
DEFAULT_QEA = os.environ.get("EA_MODEL_PATH", "")

# ---------------------------------------------------------------------------
# ArchiMate metamodel for validation
# ---------------------------------------------------------------------------

ARCHIMATE_LAYERS = {
    "Business": [
        "BusinessActor", "BusinessRole", "BusinessCollaboration",
        "BusinessInterface", "BusinessProcess", "BusinessFunction",
        "BusinessInteraction", "BusinessEvent", "BusinessService",
        "BusinessObject", "Contract", "Representation", "Product",
    ],
    "Application": [
        "ApplicationComponent", "ApplicationCollaboration",
        "ApplicationInterface", "ApplicationFunction",
        "ApplicationInteraction", "ApplicationEvent",
        "ApplicationService", "DataObject",
    ],
    "Technology": [
        "Node", "Device", "SystemSoftware", "TechnologyCollaboration",
        "TechnologyInterface", "Path", "CommunicationNetwork",
        "TechnologyFunction", "TechnologyProcess",
        "TechnologyInteraction", "TechnologyEvent",
        "TechnologyService", "Artifact",
    ],
    "Motivation": [
        "Stakeholder", "Driver", "Assessment", "Goal", "Outcome",
        "Principle", "Requirement", "Constraint", "Meaning", "Value",
    ],
    "Strategy": [
        "Resource", "Capability", "CourseOfAction", "ValueStream",
    ],
    "Implementation": [
        "WorkPackage", "Deliverable", "ImplementationEvent", "Plateau", "Gap",
    ],
}

ARCHIMATE_VALID_RELATIONS = {
    "Composition", "Aggregation", "Assignment", "Realization",
    "Serving", "Access", "Influence", "Association",
    "Triggering", "Flow", "Specialization",
}


def _get_conn(qea_path: str) -> sqlite3.Connection:
    """Open a read-only connection to a .qea file."""
    path = qea_path or DEFAULT_QEA
    if not path:
        raise ValueError(
            "No model path provided. Pass qea_path or set EA_MODEL_PATH env var."
        )
    if not Path(path).exists():
        raise FileNotFoundError(f"Model file not found: {path}")
    # Open read-only to prevent accidental writes
    uri = f"file:{path}?mode=ro"
    return sqlite3.connect(uri, uri=True)


def _get_layer(stereotype: str) -> str:
    """Determine ArchiMate layer from stereotype."""
    clean = stereotype.replace("ArchiMate_", "").replace("ArchiMate3::", "")
    for layer, elements in ARCHIMATE_LAYERS.items():
        if clean in elements:
            return layer
    return "Unknown"


# =========================================================================
# TOOLS — Element queries
# =========================================================================

@mcp.tool()
def list_elements(
    qea_path: str,
    object_type: str = "",
    stereotype: str = "",
    name_contains: str = "",
    package_name: str = "",
    limit: int = 200,
) -> str:
    """Search elements in an EA model with optional filters.

    Args:
        qea_path: Path to the .qea model file
        object_type: Filter by EA Object_Type (Class, Component, Activity, etc.)
        stereotype: Filter by stereotype (ArchiMate_BusinessProcess, etc.)
        name_contains: Filter by name substring (case-insensitive)
        package_name: Filter by parent package name
        limit: Maximum results (default 200)

    Returns:
        Formatted list of matching elements with type, stereotype, and package.
    """
    conn = _get_conn(qea_path)
    sql = """
        SELECT o.Object_ID, o.Name, o.Object_Type, o.Stereotype,
               o.Note, p.Name as PackageName
        FROM t_object o
        LEFT JOIN t_package p ON o.Package_ID = p.Package_ID
        WHERE 1=1
    """
    params: list = []

    if object_type:
        sql += " AND o.Object_Type = ?"
        params.append(object_type)
    if stereotype:
        sql += " AND o.Stereotype LIKE ?"
        params.append(f"%{stereotype}%")
    if name_contains:
        sql += " AND o.Name LIKE ?"
        params.append(f"%{name_contains}%")
    if package_name:
        sql += " AND p.Name LIKE ?"
        params.append(f"%{package_name}%")

    sql += f" ORDER BY o.Name LIMIT {limit}"
    rows = conn.execute(sql, params).fetchall()
    conn.close()

    if not rows:
        return "No elements found matching the criteria."

    lines = [f"Found {len(rows)} element(s):\n"]
    for r in rows:
        oid, name, otype, stereo, note, pkg = r
        layer = _get_layer(stereo or "") if stereo and "ArchiMate" in (stereo or "") else ""
        layer_tag = f" [{layer}]" if layer and layer != "Unknown" else ""
        stereo_tag = f" «{stereo}»" if stereo else ""
        pkg_tag = f" in [{pkg}]" if pkg else ""
        desc = ""
        if note:
            desc = f"\n    {note[:120]}..." if len(note) > 120 else f"\n    {note}"
        lines.append(f"  • {name} [{otype}]{stereo_tag}{layer_tag}{pkg_tag}{desc}")

    return "\n".join(lines)


@mcp.tool()
def get_element_detail(qea_path: str, element_name: str) -> str:
    """Get full details of a named element including attributes, operations, tagged values, and connections.

    Args:
        qea_path: Path to the .qea model file
        element_name: Exact name of the element

    Returns:
        Comprehensive element detail including properties, tags, and relationships.
    """
    conn = _get_conn(qea_path)

    # Element basics
    el = conn.execute(
        """SELECT Object_ID, Name, Object_Type, Stereotype, Note, Alias,
                  Status, Phase, Version, Author, Complexity
           FROM t_object WHERE Name = ?""",
        (element_name,),
    ).fetchone()

    if not el:
        conn.close()
        return f"Element '{element_name}' not found."

    oid = el[0]
    lines = [
        f"# {el[1]}",
        f"Type: {el[2]}  Stereotype: {el[3] or '(none)'}",
        f"Status: {el[7] or '-'}  Phase: {el[8] or '-'}  Version: {el[9] or '-'}",
        f"Author: {el[10] or '-'}  Complexity: {el[11] or '-'}",
    ]
    if el[6]:  # Alias
        lines.append(f"Alias: {el[6]}")
    if el[5]:  # Note
        lines.append(f"\nDescription:\n{el[5]}")

    # Tagged values
    tags = conn.execute(
        "SELECT Property, Value FROM t_objectproperties WHERE Object_ID = ?",
        (oid,),
    ).fetchall()
    if tags:
        lines.append("\nTagged Values:")
        for prop, val in tags:
            lines.append(f"  {prop} = {val}")

    # Attributes (for classes)
    attrs = conn.execute(
        "SELECT Name, Type, Default, Notes FROM t_attribute WHERE Object_ID = ? ORDER BY Pos",
        (oid,),
    ).fetchall()
    if attrs:
        lines.append("\nAttributes:")
        for a in attrs:
            default = f" = {a[2]}" if a[2] else ""
            lines.append(f"  {a[0]}: {a[1]}{default}")

    # Operations (for classes)
    ops = conn.execute(
        "SELECT Name, Type, Notes FROM t_operation WHERE Object_ID = ? ORDER BY Pos",
        (oid,),
    ).fetchall()
    if ops:
        lines.append("\nOperations:")
        for o in ops:
            lines.append(f"  {o[0]}() → {o[1] or 'void'}")

    # Outbound connections
    out_conns = conn.execute(
        """SELECT c.Connector_Type, c.Stereotype, tgt.Name, tgt.Object_Type, c.Name
           FROM t_connector c
           JOIN t_object tgt ON c.End_Object_ID = tgt.Object_ID
           WHERE c.Start_Object_ID = ?""",
        (oid,),
    ).fetchall()

    # Inbound connections
    in_conns = conn.execute(
        """SELECT c.Connector_Type, c.Stereotype, src.Name, src.Object_Type, c.Name
           FROM t_connector c
           JOIN t_object src ON c.Start_Object_ID = src.Object_ID
           WHERE c.End_Object_ID = ?""",
        (oid,),
    ).fetchall()

    if out_conns:
        lines.append("\nOutbound Relationships:")
        for c in out_conns:
            label = f" '{c[4]}'" if c[4] else ""
            stereo = f"/{c[1]}" if c[1] else ""
            lines.append(f"  ──[{c[0]}{stereo}{label}]──▶ {c[2]} [{c[3]}]")

    if in_conns:
        lines.append("\nInbound Relationships:")
        for c in in_conns:
            label = f" '{c[4]}'" if c[4] else ""
            stereo = f"/{c[1]}" if c[1] else ""
            lines.append(f"  {c[2]} [{c[3]}] ──[{c[0]}{stereo}{label}]──▶ (this)")

    # Diagrams containing this element
    diagrams = conn.execute(
        """SELECT d.Name, d.Diagram_Type
           FROM t_diagramobjects do
           JOIN t_diagram d ON do.Diagram_ID = d.Diagram_ID
           WHERE do.Object_ID = ?""",
        (oid,),
    ).fetchall()
    if diagrams:
        lines.append("\nAppears in Diagrams:")
        for d in diagrams:
            lines.append(f"  • {d[0]} [{d[1]}]")

    conn.close()
    return "\n".join(lines)


# =========================================================================
# TOOLS — Dependency and impact tracing
# =========================================================================

@mcp.tool()
def trace_dependencies(
    qea_path: str, element_name: str, depth: int = 2, direction: str = "both"
) -> str:
    """Trace dependency chains from a named element to find impact/blast radius.

    Args:
        qea_path: Path to the .qea model file
        element_name: Starting element name
        depth: How many hops to follow (1-5, default 2)
        direction: 'outbound', 'inbound', or 'both' (default)

    Returns:
        Dependency tree showing all connected elements up to specified depth.
    """
    conn = _get_conn(qea_path)
    depth = min(max(depth, 1), 5)

    # Find starting element
    start = conn.execute(
        "SELECT Object_ID, Name, Object_Type, Stereotype FROM t_object WHERE Name = ?",
        (element_name,),
    ).fetchone()
    if not start:
        conn.close()
        return f"Element '{element_name}' not found."

    visited = set()
    tree_lines = [f"Dependency trace from: {start[1]} [{start[2]}] «{start[3] or ''}»\n"]

    def trace(oid: int, current_depth: int, prefix: str):
        if current_depth > depth or oid in visited:
            return
        visited.add(oid)

        connections = []
        if direction in ("outbound", "both"):
            connections.extend(
                conn.execute(
                    """SELECT c.Connector_Type, c.Stereotype, tgt.Object_ID,
                              tgt.Name, tgt.Object_Type, tgt.Stereotype, 'out'
                       FROM t_connector c
                       JOIN t_object tgt ON c.End_Object_ID = tgt.Object_ID
                       WHERE c.Start_Object_ID = ?""",
                    (oid,),
                ).fetchall()
            )
        if direction in ("inbound", "both"):
            connections.extend(
                conn.execute(
                    """SELECT c.Connector_Type, c.Stereotype, src.Object_ID,
                              src.Name, src.Object_Type, src.Stereotype, 'in'
                       FROM t_connector c
                       JOIN t_object src ON c.Start_Object_ID = src.Object_ID
                       WHERE c.End_Object_ID = ?""",
                    (oid,),
                ).fetchall()
            )

        for c in connections:
            ctype, cstereo, next_oid, next_name, next_type, next_stereo, direction_tag = c
            if next_oid in visited:
                continue
            arrow = "──▶" if direction_tag == "out" else "◀──"
            rel = f"{ctype}" + (f"/{cstereo}" if cstereo else "")
            stereo = f" «{next_stereo}»" if next_stereo else ""
            tree_lines.append(
                f"{prefix}{arrow} [{rel}] {next_name} [{next_type}]{stereo}"
            )
            trace(next_oid, current_depth + 1, prefix + "    ")

    trace(start[0], 1, "  ")
    conn.close()

    if len(tree_lines) == 1:
        tree_lines.append("  (no connections found)")

    tree_lines.append(f"\nTotal elements in trace: {len(visited)}")
    return "\n".join(tree_lines)


# =========================================================================
# TOOLS — Model statistics and validation
# =========================================================================

@mcp.tool()
def model_statistics(qea_path: str) -> str:
    """Generate comprehensive model statistics: element counts by type/layer, relationship counts, diagram counts, and coverage metrics.

    Args:
        qea_path: Path to the .qea model file

    Returns:
        Structured statistics report.
    """
    conn = _get_conn(qea_path)

    lines = ["# Model Statistics\n"]

    # Element counts by type
    type_counts = conn.execute(
        """SELECT Object_Type, Stereotype, COUNT(*)
           FROM t_object GROUP BY Object_Type, Stereotype
           ORDER BY COUNT(*) DESC"""
    ).fetchall()

    lines.append("## Elements by Type")
    total_elements = 0
    layer_counts = defaultdict(int)
    for otype, stereo, count in type_counts:
        total_elements += count
        layer = _get_layer(stereo or "") if stereo and "ArchiMate" in (stereo or "") else ""
        if layer and layer != "Unknown":
            layer_counts[layer] += count
        stereo_tag = f" «{stereo}»" if stereo else ""
        lines.append(f"  {otype}{stereo_tag}: {count}")

    lines.append(f"\n  Total elements: {total_elements}")

    if layer_counts:
        lines.append("\n## ArchiMate Layer Distribution")
        for layer, count in sorted(layer_counts.items(), key=lambda x: -x[1]):
            pct = (count / total_elements * 100) if total_elements else 0
            bar = "█" * int(pct / 2)
            lines.append(f"  {layer:20s}: {count:5d} ({pct:5.1f}%) {bar}")

    # Connector counts
    conn_counts = conn.execute(
        """SELECT Connector_Type, Stereotype, COUNT(*)
           FROM t_connector GROUP BY Connector_Type, Stereotype
           ORDER BY COUNT(*) DESC"""
    ).fetchall()
    total_connectors = sum(c[2] for c in conn_counts)
    lines.append(f"\n## Relationships ({total_connectors} total)")
    for ctype, stereo, count in conn_counts:
        stereo_tag = f"/{stereo}" if stereo else ""
        lines.append(f"  {ctype}{stereo_tag}: {count}")

    # Diagram counts
    diag_counts = conn.execute(
        """SELECT Diagram_Type, COUNT(*)
           FROM t_diagram GROUP BY Diagram_Type
           ORDER BY COUNT(*) DESC"""
    ).fetchall()
    total_diagrams = sum(d[1] for d in diag_counts)
    lines.append(f"\n## Diagrams ({total_diagrams} total)")
    for dtype, count in diag_counts:
        lines.append(f"  {dtype}: {count}")

    # Package structure depth
    pkg_count = conn.execute("SELECT COUNT(*) FROM t_package").fetchone()[0]
    lines.append(f"\n## Packages: {pkg_count}")

    # Orphan elements (not on any diagram)
    orphans = conn.execute(
        """SELECT COUNT(*) FROM t_object o
           WHERE NOT EXISTS (
               SELECT 1 FROM t_diagramobjects do WHERE do.Object_ID = o.Object_ID
           )"""
    ).fetchone()[0]
    if total_elements > 0:
        orphan_pct = orphans / total_elements * 100
        lines.append(f"\n## Coverage")
        lines.append(f"  Elements on diagrams: {total_elements - orphans} ({100 - orphan_pct:.1f}%)")
        lines.append(f"  Orphan elements: {orphans} ({orphan_pct:.1f}%)")

    conn.close()
    return "\n".join(lines)


@mcp.tool()
def validate_archimate(qea_path: str) -> str:
    """Validate ArchiMate relationships against the metamodel rules.

    Checks that all ArchiMate-stereotyped connectors use valid
    relationship types between the source and target element types.

    Args:
        qea_path: Path to the .qea model file

    Returns:
        Validation report with violations and warnings.
    """
    conn = _get_conn(qea_path)

    rows = conn.execute(
        """SELECT c.Connector_ID, c.Connector_Type, c.Stereotype,
                  src.Name, src.Object_Type, src.Stereotype,
                  tgt.Name, tgt.Object_Type, tgt.Stereotype
           FROM t_connector c
           JOIN t_object src ON c.Start_Object_ID = src.Object_ID
           JOIN t_object tgt ON c.End_Object_ID = tgt.Object_ID
           WHERE src.Stereotype LIKE '%ArchiMate%'
              OR tgt.Stereotype LIKE '%ArchiMate%'"""
    ).fetchall()
    conn.close()

    if not rows:
        return "No ArchiMate relationships found in the model."

    violations = []
    warnings = []
    valid_count = 0

    for r in rows:
        cid, ctype, cstereo, src_name, src_otype, src_stereo, tgt_name, tgt_otype, tgt_stereo = r

        # Extract ArchiMate relationship type
        rel_type = (cstereo or ctype or "").replace("ArchiMate_", "").replace("ArchiMate3::", "")

        src_layer = _get_layer(src_stereo or "")
        tgt_layer = _get_layer(tgt_stereo or "")

        # Check if relationship type is valid
        if rel_type not in ARCHIMATE_VALID_RELATIONS and rel_type not in (
            "Association", "Dependency", "Realization", "Aggregation",
        ):
            violations.append(
                f"  ❌ [{rel_type}] {src_name} → {tgt_name} — unknown relationship type"
            )
        # Check cross-layer validity (simplified)
        elif src_layer == "Technology" and tgt_layer == "Motivation" and rel_type not in (
            "Realization", "Influence", "Association"
        ):
            warnings.append(
                f"  ⚠️  [{rel_type}] {src_name} ({src_layer}) → {tgt_name} ({tgt_layer}) — unusual cross-layer"
            )
        else:
            valid_count += 1

    lines = [
        f"# ArchiMate Validation Report\n",
        f"Total relationships checked: {len(rows)}",
        f"Valid: {valid_count}",
        f"Violations: {len(violations)}",
        f"Warnings: {len(warnings)}",
    ]

    if violations:
        lines.append(f"\n## Violations ({len(violations)})")
        lines.extend(violations[:50])
        if len(violations) > 50:
            lines.append(f"  ... and {len(violations) - 50} more")

    if warnings:
        lines.append(f"\n## Warnings ({len(warnings)})")
        lines.extend(warnings[:30])

    if not violations and not warnings:
        lines.append("\n✅ All ArchiMate relationships pass validation.")

    return "\n".join(lines)


# =========================================================================
# TOOLS — Package and diagram queries
# =========================================================================

@mcp.tool()
def list_packages(qea_path: str, parent_name: str = "") -> str:
    """List packages in the model, optionally filtered to children of a named package.

    Args:
        qea_path: Path to the .qea model file
        parent_name: If set, only show children of this package

    Returns:
        Package hierarchy with element counts.
    """
    conn = _get_conn(qea_path)

    if parent_name:
        parent = conn.execute(
            "SELECT Package_ID FROM t_package WHERE Name = ?", (parent_name,)
        ).fetchone()
        if not parent:
            conn.close()
            return f"Package '{parent_name}' not found."
        parent_id = parent[0]
        pkgs = conn.execute(
            """SELECT p.Package_ID, p.Name, p.Parent_ID,
                      (SELECT COUNT(*) FROM t_object o WHERE o.Package_ID = p.Package_ID)
               FROM t_package p WHERE p.Parent_ID = ?
               ORDER BY p.Name""",
            (parent_id,),
        ).fetchall()
    else:
        pkgs = conn.execute(
            """SELECT p.Package_ID, p.Name, p.Parent_ID,
                      (SELECT COUNT(*) FROM t_object o WHERE o.Package_ID = p.Package_ID)
               FROM t_package p WHERE p.Parent_ID = 0 OR p.Parent_ID IS NULL
               ORDER BY p.Name"""
        ).fetchall()

    conn.close()

    if not pkgs:
        return "No packages found."

    lines = [f"Packages{' under ' + parent_name if parent_name else ' (root level)'}:\n"]
    for pid, name, parent_id, el_count in pkgs:
        lines.append(f"  📁 {name} ({el_count} elements)")

    return "\n".join(lines)


@mcp.tool()
def list_diagrams(qea_path: str, diagram_type: str = "", name_contains: str = "") -> str:
    """List diagrams in the model with optional filters.

    Args:
        qea_path: Path to the .qea model file
        diagram_type: Filter by diagram type (e.g., 'Logical', 'Activity', 'Custom')
        name_contains: Filter by name substring

    Returns:
        List of diagrams with type, package, and element count.
    """
    conn = _get_conn(qea_path)

    sql = """
        SELECT d.Diagram_ID, d.Name, d.Diagram_Type, p.Name,
               (SELECT COUNT(*) FROM t_diagramobjects do WHERE do.Diagram_ID = d.Diagram_ID)
        FROM t_diagram d
        LEFT JOIN t_package p ON d.Package_ID = p.Package_ID
        WHERE 1=1
    """
    params: list = []
    if diagram_type:
        sql += " AND d.Diagram_Type LIKE ?"
        params.append(f"%{diagram_type}%")
    if name_contains:
        sql += " AND d.Name LIKE ?"
        params.append(f"%{name_contains}%")
    sql += " ORDER BY d.Name"

    rows = conn.execute(sql, params).fetchall()
    conn.close()

    if not rows:
        return "No diagrams found."

    lines = [f"Found {len(rows)} diagram(s):\n"]
    for did, name, dtype, pkg, el_count in rows:
        lines.append(f"  📊 {name} [{dtype}] in [{pkg or 'root'}] — {el_count} elements")

    return "\n".join(lines)


@mcp.tool()
def query_sql(qea_path: str, sql: str) -> str:
    """Execute a read-only SQL query against the EA model database.

    Use this for advanced queries not covered by other tools.
    Common tables: t_object, t_connector, t_package, t_diagram,
    t_diagramobjects, t_objectproperties, t_attribute, t_operation.

    Args:
        qea_path: Path to the .qea model file
        sql: SQL SELECT query (only SELECT is allowed)

    Returns:
        Query results as formatted text.
    """
    # Safety check: only allow SELECT
    sql_stripped = sql.strip().upper()
    if not sql_stripped.startswith("SELECT"):
        return "ERROR: Only SELECT queries are allowed. This is a read-only server."
    for forbidden in ("INSERT", "UPDATE", "DELETE", "DROP", "ALTER", "CREATE", "ATTACH"):
        if forbidden in sql_stripped:
            return f"ERROR: {forbidden} is not allowed. This is a read-only server."

    conn = _get_conn(qea_path)
    try:
        cursor = conn.execute(sql)
        columns = [desc[0] for desc in cursor.description] if cursor.description else []
        rows = cursor.fetchall()
        conn.close()

        if not rows:
            return "Query returned no results."

        # Format as table
        lines = [" | ".join(columns)]
        lines.append("-" * len(lines[0]))
        for row in rows[:500]:
            lines.append(" | ".join(str(v) if v is not None else "" for v in row))

        if len(rows) > 500:
            lines.append(f"\n... truncated ({len(rows)} total rows)")

        return "\n".join(lines)
    except Exception as e:
        conn.close()
        return f"SQL error: {e}"


# =========================================================================
# TOOLS — Mermaid diagram generation (rendered as artifacts in Claude)
# =========================================================================

# ArchiMate stereotype → Mermaid shape mapping
_MERMAID_SHAPES = {
    "Business":       ("([", "])"),   # Stadium/rounded
    "Application":    ("[", "]"),     # Rectangle
    "Technology":     ("[[", "]]"),   # Subroutine
    "Motivation":     ("{{", "}}"),   # Hexagon
    "Strategy":       (">", "]"),     # Asymmetric
    "Implementation": ("(", ")"),     # Rounded
    "Unknown":        ("[", "]"),
}

# ArchiMate relationship → Mermaid arrow
_MERMAID_ARROWS = {
    "Composition":    "--*",
    "Aggregation":    "--o",
    "Assignment":     "-->",
    "Realization":    "-.->",
    "Serving":        "-->",
    "Access":         "-.->",
    "Influence":      "..>",
    "Association":    "---",
    "Triggering":     "-->",
    "Flow":           "==>",
    "Specialization": "--|>",
    "Dependency":     "..>",
}


@mcp.tool()
def generate_dependency_diagram(
    qea_path: str,
    element_name: str,
    depth: int = 2,
    direction: str = "both",
) -> str:
    """Generate a Mermaid diagram showing dependencies from a named element.

    Claude should render the returned Mermaid code as a .mermaid artifact
    so the user sees it as a visual diagram in Claude Desktop.

    Args:
        qea_path: Path to the .qea model file
        element_name: Starting element name
        depth: Hops to follow (1-4, default 2)
        direction: 'outbound', 'inbound', or 'both'

    Returns:
        Mermaid flowchart code. Claude should display this as a Mermaid artifact.
    """
    conn = _get_conn(qea_path)
    depth = min(max(depth, 1), 4)

    start = conn.execute(
        "SELECT Object_ID, Name, Object_Type, Stereotype FROM t_object WHERE Name = ?",
        (element_name,),
    ).fetchone()
    if not start:
        conn.close()
        return f"Element '{element_name}' not found."

    nodes: dict[int, tuple] = {start[0]: (start[1], start[2], start[3] or "")}
    edges: list[tuple] = []
    visited = set()

    def _safe_id(name: str, oid: int) -> str:
        return f"n{oid}"

    def collect(oid: int, d: int):
        if d > depth or oid in visited:
            return
        visited.add(oid)

        conns = []
        if direction in ("outbound", "both"):
            conns.extend(
                conn.execute(
                    """SELECT c.Connector_Type, c.Stereotype, tgt.Object_ID,
                              tgt.Name, tgt.Object_Type, tgt.Stereotype, 'out'
                       FROM t_connector c
                       JOIN t_object tgt ON c.End_Object_ID = tgt.Object_ID
                       WHERE c.Start_Object_ID = ?""",
                    (oid,),
                ).fetchall()
            )
        if direction in ("inbound", "both"):
            conns.extend(
                conn.execute(
                    """SELECT c.Connector_Type, c.Stereotype, src.Object_ID,
                              src.Name, src.Object_Type, src.Stereotype, 'in'
                       FROM t_connector c
                       JOIN t_object src ON c.Start_Object_ID = src.Object_ID
                       WHERE c.End_Object_ID = ?""",
                    (oid,),
                ).fetchall()
            )

        for c in conns:
            ctype, cstereo, next_oid, next_name, next_type, next_stereo, dir_tag = c
            nodes[next_oid] = (next_name, next_type, next_stereo or "")
            rel = cstereo or ctype or "Association"
            if dir_tag == "out":
                edges.append((oid, next_oid, rel))
            else:
                edges.append((next_oid, oid, rel))
            collect(next_oid, d + 1)

    collect(start[0], 1)
    conn.close()

    # Build Mermaid
    lines = [f"flowchart TD"]
    lines.append(f"    %% Dependency diagram from: {element_name}")
    lines.append(f"    %% Depth: {depth} | Direction: {direction}")
    lines.append("")

    # Group by layer
    layer_groups: dict[str, list[int]] = defaultdict(list)
    for oid, (name, otype, stereo) in nodes.items():
        layer = _get_layer(stereo) if "ArchiMate" in stereo else "Other"
        layer_groups[layer].append(oid)

    for layer, oids in layer_groups.items():
        if layer != "Other" and layer != "Unknown":
            lines.append(f"    subgraph {layer}")
        for oid in oids:
            name, otype, stereo = nodes[oid]
            safe = _safe_id(name, oid)
            lshape = _get_layer(stereo) if "ArchiMate" in stereo else "Unknown"
            open_b, close_b = _MERMAID_SHAPES.get(lshape, ("[", "]"))
            clean_stereo = stereo.replace("ArchiMate_", "").replace("ArchiMate3::", "")
            label = f"{name}\\n«{clean_stereo}»" if clean_stereo else name
            lines.append(f"    {safe}{open_b}\"{label}\"{close_b}")
        if layer != "Other" and layer != "Unknown":
            lines.append(f"    end")
        lines.append("")

    # Edges
    for src_oid, tgt_oid, rel in edges:
        src_id = _safe_id("", src_oid)
        tgt_id = _safe_id("", tgt_oid)
        arrow = _MERMAID_ARROWS.get(rel, "-->")
        clean_rel = rel.replace("ArchiMate_", "")
        lines.append(f"    {src_id} {arrow}|{clean_rel}| {tgt_id}")

    # Highlight start node
    lines.append("")
    lines.append(f"    style {_safe_id('', start[0])} fill:#ff6b6b,stroke:#c92a2a,color:#fff")

    mermaid_code = "\n".join(lines)
    return f"""MERMAID_DIAGRAM
Render the following as a Mermaid artifact (.mermaid file) in Claude Desktop:

```mermaid
{mermaid_code}
```

This shows the dependency graph from "{element_name}" with {len(nodes)} elements and {len(edges)} relationships."""


@mcp.tool()
def generate_layer_diagram(qea_path: str, layers: str = "all") -> str:
    """Generate a Mermaid diagram showing ArchiMate layers and cross-layer relationships.

    Claude should render the returned Mermaid code as a .mermaid artifact.

    Args:
        qea_path: Path to the .qea model file
        layers: Comma-separated layer names or 'all' (default).
                Options: Business, Application, Technology, Motivation, Strategy, Implementation

    Returns:
        Mermaid flowchart code. Claude should display this as a Mermaid artifact.
    """
    conn = _get_conn(qea_path)

    if layers == "all":
        target_layers = set(ARCHIMATE_LAYERS.keys())
    else:
        target_layers = {l.strip() for l in layers.split(",")}

    # Collect ArchiMate elements grouped by layer
    elements = conn.execute(
        """SELECT o.Object_ID, o.Name, o.Object_Type, o.Stereotype
           FROM t_object o
           WHERE o.Stereotype LIKE '%ArchiMate%'
           ORDER BY o.Name"""
    ).fetchall()

    layer_elements: dict[str, list[tuple]] = defaultdict(list)
    element_ids = set()
    for oid, name, otype, stereo in elements:
        layer = _get_layer(stereo or "")
        if layer in target_layers:
            layer_elements[layer].append((oid, name, otype, stereo or ""))
            element_ids.add(oid)

    # Collect cross-layer connectors
    connectors = conn.execute(
        """SELECT c.Start_Object_ID, c.End_Object_ID, c.Connector_Type, c.Stereotype
           FROM t_connector c
           WHERE c.Start_Object_ID IN ({ids}) AND c.End_Object_ID IN ({ids})""".format(
            ids=",".join(str(i) for i in element_ids) if element_ids else "0"
        )
    ).fetchall()
    conn.close()

    if not element_ids:
        return "No ArchiMate elements found for the specified layers."

    # Build Mermaid
    lines = ["flowchart TD"]
    lines.append(f"    %% ArchiMate Layer View")
    lines.append("")

    # Layer ordering (top to bottom)
    layer_order = ["Motivation", "Strategy", "Business", "Application", "Technology", "Implementation"]

    for layer in layer_order:
        if layer not in layer_elements:
            continue
        elems = layer_elements[layer]
        lines.append(f"    subgraph {layer}[\"{layer} Layer\"]")
        lines.append(f"    direction LR")
        for oid, name, otype, stereo in elems[:30]:  # Limit per layer for readability
            safe = f"n{oid}"
            open_b, close_b = _MERMAID_SHAPES.get(layer, ("[", "]"))
            clean = stereo.replace("ArchiMate_", "").replace("ArchiMate3::", "")
            label = f"{name}\\n«{clean}»"
            lines.append(f"        {safe}{open_b}\"{label}\"{close_b}")
        if len(elems) > 30:
            lines.append(f"        more_{layer}[\"+{len(elems) - 30} more...\"]")
        lines.append(f"    end")
        lines.append("")

    # Edges
    for src, tgt, ctype, cstereo in connectors:
        if src in element_ids and tgt in element_ids:
            rel = cstereo or ctype or "Association"
            clean_rel = rel.replace("ArchiMate_", "")
            arrow = _MERMAID_ARROWS.get(clean_rel, "-->")
            lines.append(f"    n{src} {arrow}|{clean_rel}| n{tgt}")

    # Layer styling
    layer_colors = {
        "Motivation": "#FFFFCC",
        "Strategy":   "#F5DEAA",
        "Business":   "#FFFFB5",
        "Application": "#B5FFFF",
        "Technology":  "#C9E7B7",
        "Implementation": "#FFE0E0",
    }
    lines.append("")
    for layer, color in layer_colors.items():
        if layer in layer_elements:
            lines.append(f"    style {layer} fill:{color},stroke:#666")

    mermaid_code = "\n".join(lines)
    total = sum(len(v) for v in layer_elements.values())
    return f"""MERMAID_DIAGRAM
Render the following as a Mermaid artifact (.mermaid file) in Claude Desktop:

```mermaid
{mermaid_code}
```

ArchiMate layer view with {total} elements across {len(layer_elements)} layers and {len(connectors)} relationships."""


@mcp.tool()
def generate_catalog(
    qea_path: str,
    catalog_type: str = "elements",
    stereotype: str = "",
    format: str = "json",
) -> str:
    """Generate a structured catalog for rendering as an interactive artifact.

    Claude should render the returned data as a React (.jsx) or HTML (.html)
    artifact with an interactive, sortable, filterable table.

    Catalog types:
      - elements: Element catalog (name, type, stereotype, layer, package, status)
      - relationships: Relationship matrix (source, target, type, layer crossings)
      - diagrams: Diagram inventory (name, type, package, element count)
      - packages: Package hierarchy with element counts
      - coverage: Elements per diagram coverage analysis

    Args:
        qea_path: Path to the .qea model file
        catalog_type: Type of catalog (elements, relationships, diagrams, packages, coverage)
        stereotype: Optional filter (e.g., 'ArchiMate_Business%')
        format: 'json' for React/HTML artifacts, 'markdown' for .md artifacts

    Returns:
        Structured data with rendering instructions for Claude.
    """
    conn = _get_conn(qea_path)

    if catalog_type == "elements":
        sql = """
            SELECT o.Object_ID, o.Name, o.Object_Type, o.Stereotype,
                   o.Status, o.Phase, o.Author, p.Name as Package,
                   (SELECT COUNT(*) FROM t_connector c WHERE c.Start_Object_ID = o.Object_ID OR c.End_Object_ID = o.Object_ID) as Connections,
                   (SELECT COUNT(*) FROM t_diagramobjects do WHERE do.Object_ID = o.Object_ID) as OnDiagrams
            FROM t_object o
            LEFT JOIN t_package p ON o.Package_ID = p.Package_ID
            WHERE 1=1
        """
        params = []
        if stereotype:
            sql += " AND o.Stereotype LIKE ?"
            params.append(f"%{stereotype}%")
        sql += " ORDER BY o.Name"
        rows = conn.execute(sql, params).fetchall()

        if format == "json":
            data = []
            for r in rows:
                stereo = r[3] or ""
                layer = _get_layer(stereo) if "ArchiMate" in stereo else ""
                clean_stereo = stereo.replace("ArchiMate_", "").replace("ArchiMate3::", "")
                data.append({
                    "id": r[0], "name": r[1], "type": r[2],
                    "stereotype": clean_stereo, "layer": layer,
                    "status": r[4] or "", "phase": r[5] or "",
                    "author": r[6] or "", "package": r[7] or "",
                    "connections": r[8], "onDiagrams": r[9],
                })
            conn.close()
            return f"""CATALOG_DATA
Type: Element Catalog
Count: {len(data)}
Format: JSON

Claude should render this as an interactive React artifact (.jsx) with:
- A sortable, filterable table with search box
- Color-coded rows by ArchiMate layer (Business=yellow, Application=cyan, Technology=green)
- Click to expand showing connections and diagrams count
- Summary stats bar at top (total elements, by layer, orphans)

```json
{json.dumps(data, indent=2)}
```"""
        else:  # markdown
            lines = [f"# Element Catalog ({len(rows)} elements)\n"]
            lines.append("| Name | Type | Stereotype | Layer | Package | Connections | Diagrams |")
            lines.append("|------|------|-----------|-------|---------|------------|----------|")
            for r in rows:
                stereo = (r[3] or "").replace("ArchiMate_", "")
                layer = _get_layer(r[3] or "") if r[3] and "ArchiMate" in r[3] else ""
                lines.append(f"| {r[1]} | {r[2]} | {stereo} | {layer} | {r[7] or ''} | {r[8]} | {r[9]} |")
            conn.close()
            return "\n".join(lines)

    elif catalog_type == "relationships":
        rows = conn.execute(
            """SELECT src.Name, src.Stereotype, c.Connector_Type, c.Stereotype as CStereo,
                      tgt.Name, tgt.Stereotype
               FROM t_connector c
               JOIN t_object src ON c.Start_Object_ID = src.Object_ID
               JOIN t_object tgt ON c.End_Object_ID = tgt.Object_ID
               ORDER BY src.Name"""
        ).fetchall()

        data = []
        for r in rows:
            src_layer = _get_layer(r[1] or "") if r[1] and "ArchiMate" in r[1] else ""
            tgt_layer = _get_layer(r[5] or "") if r[5] and "ArchiMate" in r[5] else ""
            rel = (r[3] or r[2] or "").replace("ArchiMate_", "")
            data.append({
                "source": r[0], "sourceLayer": src_layer,
                "relationship": rel,
                "target": r[4], "targetLayer": tgt_layer,
                "crossLayer": src_layer != tgt_layer and src_layer and tgt_layer,
            })
        conn.close()
        return f"""CATALOG_DATA
Type: Relationship Catalog
Count: {len(data)}
Format: JSON

Claude should render this as an interactive React artifact (.jsx) with:
- Sortable table with source, relationship type, target columns
- Layer badges (colored chips) for source and target
- Highlight cross-layer relationships
- Filter by relationship type and layer

```json
{json.dumps(data[:500], indent=2)}
```"""

    elif catalog_type == "diagrams":
        rows = conn.execute(
            """SELECT d.Diagram_ID, d.Name, d.Diagram_Type, p.Name as Package,
                      d.Author, d.Version,
                      (SELECT COUNT(*) FROM t_diagramobjects do WHERE do.Diagram_ID = d.Diagram_ID) as Elements
               FROM t_diagram d
               LEFT JOIN t_package p ON d.Package_ID = p.Package_ID
               ORDER BY d.Name"""
        ).fetchall()

        data = [
            {"id": r[0], "name": r[1], "type": r[2], "package": r[3] or "",
             "author": r[4] or "", "version": r[5] or "", "elements": r[6]}
            for r in rows
        ]
        conn.close()
        return f"""CATALOG_DATA
Type: Diagram Catalog
Count: {len(data)}
Format: JSON

Claude should render this as an interactive React artifact (.jsx) with:
- Table with diagram name, type, package, element count
- Group by type or package
- Bar chart showing elements per diagram

```json
{json.dumps(data, indent=2)}
```"""

    elif catalog_type == "packages":
        rows = conn.execute(
            """SELECT p.Package_ID, p.Name, p.Parent_ID,
                      (SELECT COUNT(*) FROM t_object o WHERE o.Package_ID = p.Package_ID) as Elements,
                      (SELECT COUNT(*) FROM t_diagram d WHERE d.Package_ID = p.Package_ID) as Diagrams
               FROM t_package p
               ORDER BY p.Name"""
        ).fetchall()

        data = [
            {"id": r[0], "name": r[1], "parentId": r[2] or 0,
             "elements": r[3], "diagrams": r[4]}
            for r in rows
        ]
        conn.close()
        return f"""CATALOG_DATA
Type: Package Catalog
Count: {len(data)}
Format: JSON

Claude should render this as an interactive React artifact (.jsx) with:
- Tree/hierarchy view (expandable/collapsible)
- Element and diagram counts per package
- Visual size indicator (larger packages = bigger)

```json
{json.dumps(data, indent=2)}
```"""

    elif catalog_type == "coverage":
        rows = conn.execute(
            """SELECT o.Object_ID, o.Name, o.Object_Type, o.Stereotype,
                      p.Name as Package,
                      (SELECT COUNT(*) FROM t_diagramobjects do WHERE do.Object_ID = o.Object_ID) as DiagramCount,
                      (SELECT GROUP_CONCAT(d.Name, '; ')
                       FROM t_diagramobjects do2
                       JOIN t_diagram d ON do2.Diagram_ID = d.Diagram_ID
                       WHERE do2.Object_ID = o.Object_ID) as DiagramNames
               FROM t_object o
               LEFT JOIN t_package p ON o.Package_ID = p.Package_ID
               ORDER BY DiagramCount ASC, o.Name"""
        ).fetchall()

        data = []
        orphan_count = 0
        for r in rows:
            stereo = (r[3] or "").replace("ArchiMate_", "").replace("ArchiMate3::", "")
            layer = _get_layer(r[3] or "") if r[3] and "ArchiMate" in r[3] else ""
            diagrams = r[6] or ""
            count = r[5]
            if count == 0:
                orphan_count += 1
            data.append({
                "name": r[1], "type": r[2], "stereotype": stereo,
                "layer": layer, "package": r[4] or "",
                "diagramCount": count, "diagrams": diagrams,
                "isOrphan": count == 0,
            })
        conn.close()
        return f"""CATALOG_DATA
Type: Diagram Coverage Analysis
Count: {len(data)}
Orphans: {orphan_count} ({orphan_count/len(data)*100:.1f}% of elements not on any diagram)
Format: JSON

Claude should render this as an interactive React artifact (.jsx) with:
- Table sorted by diagram count (orphans first, highlighted red)
- Coverage bar chart by layer
- Summary: total elements, covered, orphans percentage
- Filter to show only orphans

```json
{json.dumps(data[:500], indent=2)}
```"""

    else:
        conn.close()
        return f"Unknown catalog type: '{catalog_type}'. Use: elements, relationships, diagrams, packages, coverage"


@mcp.tool()
def get_diagram_layout(qea_path: str, diagram_name: str) -> str:
    """Get a diagram's elements with their EXACT positions from the EA database.

    EA stores pixel-perfect element positions (RectTop, RectLeft, RectRight, RectBottom)
    and connector routing geometry in the database. This tool extracts that layout data
    so Claude can render the diagram with the same layout as in EA.

    Claude should render the returned JSON as a React (.jsx) artifact using
    absolute positioning (or SVG) to place elements at their exact EA coordinates.

    Args:
        qea_path: Path to the .qea model file
        diagram_name: Name of the diagram in EA

    Returns:
        JSON with exact element positions and connector geometry for rendering.
    """
    conn = _get_conn(qea_path)

    diag = conn.execute(
        "SELECT Diagram_ID, Name, Diagram_Type, cx, cy FROM t_diagram WHERE Name = ?",
        (diagram_name,),
    ).fetchone()
    if not diag:
        conn.close()
        return f"Diagram '{diagram_name}' not found."

    diag_id, diag_name, diag_type = diag[0], diag[1], diag[2]
    # cx, cy are diagram canvas size (may be 0)
    canvas_cx = diag[3] or 0
    canvas_cy = diag[4] or 0

    # ── Get elements WITH their diagram placement coordinates ──
    # t_diagramobjects stores: RectTop, RectLeft, RectRight, RectBottom
    # These are EA's pixel coordinates for each element on this diagram.
    # EA uses a coordinate system where Y increases downward (screen coords).
    elements = conn.execute(
        """SELECT o.Object_ID, o.Name, o.Object_Type, o.Stereotype, o.Note,
                  do.RectTop, do.RectLeft, do.RectRight, do.RectBottom,
                  do.Sequence, do.ObjectStyle
           FROM t_diagramobjects do
           JOIN t_object o ON do.Object_ID = o.Object_ID
           WHERE do.Diagram_ID = ?
           ORDER BY do.Sequence""",
        (diag_id,),
    ).fetchall()

    element_ids = {e[0] for e in elements}

    # ── Get connectors with routing geometry ──
    # t_diagramlinks stores connector rendering on this specific diagram
    if element_ids:
        id_list = ",".join(str(i) for i in element_ids)
        connectors = conn.execute(
            f"""SELECT c.Connector_ID, c.Start_Object_ID, c.End_Object_ID,
                       c.Connector_Type, c.Stereotype, c.Name, c.Direction,
                       dl.Geometry, dl.Style, dl.Hidden, dl.Path
                FROM t_connector c
                LEFT JOIN t_diagramlinks dl
                  ON dl.ConnectorID = c.Connector_ID AND dl.DiagramID = ?
                WHERE c.Start_Object_ID IN ({id_list})
                  AND c.End_Object_ID IN ({id_list})
                  AND (dl.Hidden IS NULL OR dl.Hidden = 0)""",
            (diag_id,),
        ).fetchall()
    else:
        connectors = []

    conn.close()

    if not elements:
        return f"Diagram '{diagram_name}' has no elements."

    # ── Compute bounding box and normalize coordinates ──
    min_x = min(e[6] for e in elements)  # RectLeft
    min_y = min(e[5] for e in elements)  # RectTop
    max_x = max(e[7] for e in elements)  # RectRight
    max_y = max(e[8] for e in elements)  # RectBottom

    # Add padding
    pad = 40
    min_x -= pad
    min_y -= pad

    # Build normalized element list
    node_data = []
    for e in elements:
        oid, name, otype, stereo, note = e[0], e[1], e[2], e[3] or "", e[4] or ""
        top, left, right, bottom = e[5], e[6], e[7], e[8]

        # Normalize to 0,0 origin
        x = left - min_x
        y = top - min_y
        w = right - left
        h = bottom - top

        # Handle negative dimensions (EA sometimes stores inverted rects)
        if w < 0:
            x = x + w
            w = abs(w)
        if h < 0:
            y = y + h
            h = abs(h)

        layer = _get_layer(stereo) if "ArchiMate" in stereo else ""
        clean_stereo = stereo.replace("ArchiMate_", "").replace("ArchiMate3::", "")

        node_data.append({
            "id": oid,
            "name": name,
            "type": otype,
            "stereotype": clean_stereo,
            "layer": layer,
            "x": x, "y": y,
            "width": max(w, 80),
            "height": max(h, 40),
            "description": note[:200] if note else "",
        })

    # Build connector list
    edge_data = []
    for c in connectors:
        cid, src, tgt, ctype, cstereo, cname, direction = c[0:7]
        geometry, style, hidden, path = c[7], c[8], c[9], c[10]

        rel = (cstereo or ctype or "Association").replace("ArchiMate_", "")

        # Parse geometry string if available
        # EA geometry format: "SX=x;SY=y;EX=x;EY=y;EDGE=n;$LLB=label;..." or waypoints
        waypoints = []
        if geometry:
            # Extract waypoint coordinates from geometry string
            parts = geometry.split(";")
            for part in parts:
                part = part.strip()
                if part.startswith("SX="):
                    try: waypoints.append({"role": "start", "x": int(part.split("=")[1]) - min_x})
                    except: pass
                elif part.startswith("SY="):
                    try:
                        if waypoints: waypoints[-1]["y"] = int(part.split("=")[1]) - min_y
                    except: pass
                elif part.startswith("EX="):
                    try: waypoints.append({"role": "end", "x": int(part.split("=")[1]) - min_x})
                    except: pass
                elif part.startswith("EY="):
                    try:
                        if waypoints: waypoints[-1]["y"] = int(part.split("=")[1]) - min_y
                    except: pass

        # Parse path waypoints if present
        if path:
            try:
                path_points = []
                coords = path.split(";")
                for coord in coords:
                    coord = coord.strip()
                    if ":" in coord:
                        px, py = coord.split(":")
                        path_points.append({
                            "x": int(px) - min_x,
                            "y": int(py) - min_y,
                        })
                if path_points:
                    waypoints = path_points
            except:
                pass

        edge_data.append({
            "id": cid,
            "source": src,
            "target": tgt,
            "relationship": rel,
            "label": cname or "",
            "waypoints": waypoints,
        })

    # Diagram metadata
    # ── Detect sub-diagrams for each element ──
    # EA stores composite/child diagrams in multiple ways:
    #   1. t_object.PDATA1 = diagram_id (composite elements)
    #   2. Elements with Object_Type 'Package' → diagrams in that package
    #   3. t_xref with @COMP property
    # We check all of these to build a navigation map.
    for nd in node_data:
        nd["childDiagram"] = None
        nd["childDiagramName"] = None

    # Method 1: PDATA1 references a diagram
    oid_list = ",".join(str(nd["id"]) for nd in node_data)
    if oid_list:
        conn2 = _get_conn(qea_path)
        pdata_rows = conn2.execute(
            f"""SELECT o.Object_ID, o.PDATA1, d.Diagram_ID, d.Name
                FROM t_object o
                LEFT JOIN t_diagram d ON CAST(o.PDATA1 AS INTEGER) = d.Diagram_ID
                WHERE o.Object_ID IN ({oid_list})
                  AND o.PDATA1 IS NOT NULL AND o.PDATA1 != ''
                  AND d.Diagram_ID IS NOT NULL"""
        ).fetchall()
        pdata_map = {r[0]: {"id": r[2], "name": r[3]} for r in pdata_rows}

        # Method 2: Package elements → diagrams inside the package
        pkg_rows = conn2.execute(
            f"""SELECT o.Object_ID, d.Diagram_ID, d.Name
                FROM t_object o
                JOIN t_package p ON o.Name = p.Name
                JOIN t_diagram d ON d.Package_ID = p.Package_ID
                WHERE o.Object_ID IN ({oid_list})
                  AND o.Object_Type IN ('Package', 'Component', 'Class')
                ORDER BY o.Object_ID, d.Diagram_ID"""
        ).fetchall()
        # Take first diagram per element
        pkg_map = {}
        for r in pkg_rows:
            if r[0] not in pkg_map:
                pkg_map[r[0]] = {"id": r[1], "name": r[2]}

        # Method 3: t_xref composite flag
        xref_rows = conn2.execute(
            f"""SELECT x.Client, d.Diagram_ID, d.Name
                FROM t_xref x
                JOIN t_diagram d ON CAST(x.Description AS INTEGER) = d.Diagram_ID
                WHERE x.Client IN ({oid_list})
                  AND x.Name = 'CustomProperties'
                  AND x.Description IS NOT NULL
                  AND d.Diagram_ID IS NOT NULL"""
        ).fetchall()
        xref_map = {r[0]: {"id": r[1], "name": r[2]} for r in xref_rows}
        conn2.close()

        # Merge: priority PDATA1 > xref > package
        for nd in node_data:
            oid = nd["id"]
            child = pdata_map.get(oid) or xref_map.get(oid) or pkg_map.get(oid)
            if child:
                nd["childDiagram"] = child["id"]
                nd["childDiagramName"] = child["name"]

    diagram_data = {
        "name": diag_name,
        "type": diag_type,
        "canvasWidth": max_x - min_x + pad * 2,
        "canvasHeight": max_y - min_y + pad * 2,
        "elementCount": len(node_data),
        "connectorCount": len(edge_data),
        "hasPositions": True,
        "nodes": node_data,
        "edges": edge_data,
    }

    return f"""DIAGRAM_LAYOUT
Type: EA Diagram with exact positions
Name: {diag_name} [{diag_type}]
Elements: {len(node_data)} | Connectors: {len(edge_data)}
Canvas: {diagram_data['canvasWidth']}x{diagram_data['canvasHeight']}px
Has Positions: YES (from EA t_diagramobjects.Rect* columns)

Claude should render this as a React (.jsx) artifact using SVG with:
- Elements placed at EXACT x,y coordinates (these are EA's real positions)
- Element dimensions from width/height (EA's real sizes)
- ArchiMate layer colors (Business=#FFFFB5, Application=#B5FFFF, Technology=#C9E7B7)
- Connectors routed using the waypoints (if provided) or straight lines
- ArchiMate notation: rounded rect for Business, rect for Application, double-bordered for Technology
- Stereotypes shown as «stereotype» below element name
- Zoom/pan controls for large diagrams
- Click element to show properties

```json
{json.dumps(diagram_data, indent=2)}
```"""


@mcp.tool()
def get_diagram_elements(qea_path: str, diagram_name: str) -> str:
    """Get all elements and relationships on a specific diagram for Mermaid rendering.

    For approximate Mermaid rendering. Use get_diagram_layout instead for
    exact EA-position rendering in React artifacts.

    Args:
        qea_path: Path to the .qea model file
        diagram_name: Name of the diagram in EA

    Returns:
        Mermaid code representing the diagram contents.
    """
    conn = _get_conn(qea_path)

    diag = conn.execute(
        "SELECT Diagram_ID, Name, Diagram_Type FROM t_diagram WHERE Name = ?",
        (diagram_name,),
    ).fetchone()
    if not diag:
        conn.close()
        return f"Diagram '{diagram_name}' not found."

    diag_id, diag_name, diag_type = diag

    elements = conn.execute(
        """SELECT o.Object_ID, o.Name, o.Object_Type, o.Stereotype
           FROM t_diagramobjects do
           JOIN t_object o ON do.Object_ID = o.Object_ID
           WHERE do.Diagram_ID = ?""",
        (diag_id,),
    ).fetchall()

    element_ids = {e[0] for e in elements}

    if element_ids:
        id_list = ",".join(str(i) for i in element_ids)
        connectors = conn.execute(
            f"""SELECT c.Start_Object_ID, c.End_Object_ID,
                       c.Connector_Type, c.Stereotype, c.Name
                FROM t_connector c
                WHERE c.Start_Object_ID IN ({id_list})
                  AND c.End_Object_ID IN ({id_list})"""
        ).fetchall()
    else:
        connectors = []

    conn.close()

    if not elements:
        return f"Diagram '{diagram_name}' has no elements."

    lines = [f"flowchart TD"]
    lines.append(f"    %% EA Diagram: {diag_name} [{diag_type}]")
    lines.append("")

    layer_groups: dict[str, list] = defaultdict(list)
    for oid, name, otype, stereo in elements:
        layer = _get_layer(stereo or "") if stereo and "ArchiMate" in stereo else "Other"
        layer_groups[layer].append((oid, name, otype, stereo or ""))

    for layer, elems in layer_groups.items():
        if layer not in ("Other", "Unknown") and len(layer_groups) > 1:
            lines.append(f"    subgraph {layer}[\"{layer} Layer\"]")
        for oid, name, otype, stereo in elems:
            safe = f"n{oid}"
            lyr = _get_layer(stereo) if "ArchiMate" in stereo else "Unknown"
            open_b, close_b = _MERMAID_SHAPES.get(lyr, ("[", "]"))
            clean = stereo.replace("ArchiMate_", "").replace("ArchiMate3::", "")
            label = f"{name}\\n«{clean}»" if clean else name
            lines.append(f"        {safe}{open_b}\"{label}\"{close_b}")
        if layer not in ("Other", "Unknown") and len(layer_groups) > 1:
            lines.append(f"    end")
        lines.append("")

    for src, tgt, ctype, cstereo, cname in connectors:
        rel = (cstereo or ctype or "Association").replace("ArchiMate_", "")
        arrow = _MERMAID_ARROWS.get(rel, "-->")
        label = cname or rel
        lines.append(f"    n{src} {arrow}|\"{label}\"| n{tgt}")

    layer_colors = {
        "Motivation": "#FFFFCC", "Strategy": "#F5DEAA",
        "Business": "#FFFFB5", "Application": "#B5FFFF",
        "Technology": "#C9E7B7", "Implementation": "#FFE0E0",
    }
    lines.append("")
    for layer, color in layer_colors.items():
        if layer in layer_groups:
            lines.append(f"    style {layer} fill:{color},stroke:#666")

    mermaid_code = "\n".join(lines)
    return f"""MERMAID_DIAGRAM
Render the following as a Mermaid artifact (.mermaid file) titled "{diag_name}":

```mermaid
{mermaid_code}
```

EA Diagram "{diag_name}" [{diag_type}] with {len(elements)} elements and {len(connectors)} connectors.
Tip: For exact EA layout, use get_diagram_layout instead."""



# =========================================================================
# TOOLS — Full model export for EA Explorer artifact
# =========================================================================

@mcp.tool()
def export_model_for_explorer(
    qea_path: str,
    max_diagrams: int = 50,
    include_positions: bool = True,
) -> str:
    """Export the complete model dataset for the EA Explorer React artifact.

    Extracts ALL diagrams with element positions, all elements, relationships,
    and packages in a single call. The EA Explorer artifact uses this data
    for client-side diagram navigation — no further MCP calls needed.

    This is the recommended way to use the EA Explorer: call this tool once,
    then inject the JSON into the EXPLORER_DATA constant in the artifact.

    Args:
        qea_path: Path to the .qea model file
        max_diagrams: Maximum diagrams to extract (default 50, 0=unlimited)
        include_positions: Extract element positions from t_diagramobjects (default True)

    Returns:
        Complete model dataset as JSON for the EA Explorer artifact.
    """
    conn = _get_conn(qea_path)

    # ── 1. Packages ──────────────────────────────────────────────────────
    packages = []
    for r in conn.execute(
        """SELECT p.Package_ID, p.Name, p.Parent_ID,
                  (SELECT COUNT(*) FROM t_object o WHERE o.Package_ID = p.Package_ID) as Elements,
                  (SELECT COUNT(*) FROM t_diagram d WHERE d.Package_ID = p.Package_ID) as Diagrams
           FROM t_package p ORDER BY p.Name"""
    ).fetchall():
        packages.append({
            "id": r[0], "name": r[1], "parentId": r[2] or 0,
            "elements": r[3], "diagrams": r[4],
        })

    # ── 2. All elements ──────────────────────────────────────────────────
    elements = []
    element_map = {}  # id → element dict
    for r in conn.execute(
        """SELECT o.Object_ID, o.Name, o.Object_Type, o.Stereotype, o.Note,
                  o.Status, o.Phase, o.Author, p.Name as Package,
                  (SELECT COUNT(*) FROM t_connector c
                   WHERE c.Start_Object_ID = o.Object_ID OR c.End_Object_ID = o.Object_ID) as Connections,
                  (SELECT COUNT(*) FROM t_diagramobjects do
                   WHERE do.Object_ID = o.Object_ID) as OnDiagrams
           FROM t_object o
           LEFT JOIN t_package p ON o.Package_ID = p.Package_ID
           ORDER BY o.Name"""
    ).fetchall():
        stereo = r[3] or ""
        layer = _get_layer(stereo) if "ArchiMate" in stereo else ""
        clean_stereo = stereo.replace("ArchiMate_", "").replace("ArchiMate3::", "")
        el = {
            "id": r[0], "name": r[1], "type": r[2],
            "stereotype": clean_stereo, "layer": layer,
            "description": (r[4] or "")[:300],
            "status": r[5] or "", "phase": r[6] or "",
            "author": r[7] or "", "package": r[8] or "",
            "connections": r[9], "onDiagrams": r[10],
        }
        elements.append(el)
        element_map[r[0]] = el

    # ── 3. All relationships ─────────────────────────────────────────────
    relationships = []
    for r in conn.execute(
        """SELECT c.Connector_ID, c.Start_Object_ID, c.End_Object_ID,
                  c.Connector_Type, c.Stereotype, c.Name
           FROM t_connector c
           ORDER BY c.Connector_ID"""
    ).fetchall():
        src = element_map.get(r[1])
        tgt = element_map.get(r[2])
        if not src or not tgt:
            continue
        rel = (r[4] or r[3] or "Association").replace("ArchiMate_", "").replace("ArchiMate3::", "")
        relationships.append({
            "id": r[0],
            "source": src["name"], "sourceId": r[1], "sourceLayer": src["layer"],
            "target": tgt["name"], "targetId": r[2], "targetLayer": tgt["layer"],
            "relationship": rel, "label": r[5] or "",
        })

    # ── 4. Diagrams with element positions ───────────────────────────────
    diagram_rows = conn.execute(
        """SELECT d.Diagram_ID, d.Name, d.Diagram_Type, p.Name as Package,
                  d.Author, d.Version,
                  (SELECT COUNT(*) FROM t_diagramobjects do
                   WHERE do.Diagram_ID = d.Diagram_ID) as ElementCount
           FROM t_diagram d
           LEFT JOIN t_package p ON d.Package_ID = p.Package_ID
           ORDER BY d.Name"""
    ).fetchall()

    diagrams = []
    diagram_limit = max_diagrams if max_diagrams > 0 else len(diagram_rows)

    for dr in diagram_rows[:diagram_limit]:
        diag_id, diag_name, diag_type, diag_pkg = dr[0], dr[1], dr[2], dr[3] or ""
        diag_author, diag_version, el_count = dr[4] or "", dr[5] or "", dr[6]

        diag_entry = {
            "id": diag_id,
            "name": diag_name,
            "type": diag_type,
            "package": diag_pkg,
            "author": diag_author,
            "elementCount": el_count,
            "nodes": [],
            "edges": [],
            "canvasWidth": 0,
            "canvasHeight": 0,
            "hasPositions": False,
        }

        if include_positions and el_count > 0:
            # Get elements WITH their exact positions on this diagram
            diag_elements = conn.execute(
                """SELECT o.Object_ID, o.Name, o.Object_Type, o.Stereotype, o.Note,
                          do.RectTop, do.RectLeft, do.RectRight, do.RectBottom,
                          do.Sequence
                   FROM t_diagramobjects do
                   JOIN t_object o ON do.Object_ID = o.Object_ID
                   WHERE do.Diagram_ID = ?
                   ORDER BY do.Sequence""",
                (diag_id,),
            ).fetchall()

            if diag_elements:
                # Compute bounding box
                all_left = [e[6] for e in diag_elements]
                all_top = [e[5] for e in diag_elements]
                all_right = [e[7] for e in diag_elements]
                all_bottom = [e[8] for e in diag_elements]

                min_x = min(all_left) - 40
                min_y = min(all_top) - 40

                nodes = []
                diag_element_ids = set()
                for e in diag_elements:
                    oid, name, otype, stereo, note = e[0], e[1], e[2], e[3] or "", e[4] or ""
                    top, left, right, bottom = e[5], e[6], e[7], e[8]

                    x = left - min_x
                    y = top - min_y
                    w = right - left
                    h = bottom - top
                    if w < 0: x, w = x + w, abs(w)
                    if h < 0: y, h = y + h, abs(h)

                    layer = _get_layer(stereo) if "ArchiMate" in stereo else ""
                    clean = stereo.replace("ArchiMate_", "").replace("ArchiMate3::", "")

                    # Check if this element has child diagrams (composite element)
                    child_diagrams = conn.execute(
                        """SELECT d.Diagram_ID, d.Name, d.Diagram_Type
                           FROM t_diagram d
                           WHERE d.ParentID = ?""",
                        (oid,),
                    ).fetchall()

                    # Also check diagrams where this element is the "context"
                    # (element appears as a boundary/container on sub-diagrams)
                    if not child_diagrams:
                        child_diagrams = conn.execute(
                            """SELECT DISTINCT d.Diagram_ID, d.Name, d.Diagram_Type
                               FROM t_diagram d
                               JOIN t_package pkg ON d.Package_ID = pkg.Package_ID
                               WHERE pkg.Name = ?
                               AND d.Diagram_ID != ?""",
                            (name, diag_id),
                        ).fetchall()

                    child_diag_refs = [
                        {"id": cd[0], "name": cd[1], "type": cd[2]}
                        for cd in child_diagrams
                    ] if child_diagrams else []

                    nodes.append({
                        "id": oid,
                        "name": name,
                        "type": otype,
                        "stereotype": clean,
                        "layer": layer,
                        "x": x, "y": y,
                        "width": max(w, 80),
                        "height": max(h, 40),
                        "childDiagrams": child_diag_refs,
                    })
                    diag_element_ids.add(oid)

                # Get connectors visible on this diagram
                if diag_element_ids:
                    id_list = ",".join(str(i) for i in diag_element_ids)
                    diag_connectors = conn.execute(
                        f"""SELECT c.Connector_ID, c.Start_Object_ID, c.End_Object_ID,
                                   c.Connector_Type, c.Stereotype, c.Name,
                                   dl.Geometry, dl.Path
                            FROM t_connector c
                            LEFT JOIN t_diagramlinks dl
                              ON dl.ConnectorID = c.Connector_ID AND dl.DiagramID = ?
                            WHERE c.Start_Object_ID IN ({id_list})
                              AND c.End_Object_ID IN ({id_list})
                              AND (dl.Hidden IS NULL OR dl.Hidden = 0)""",
                        (diag_id,),
                    ).fetchall()

                    edges = []
                    for c in diag_connectors:
                        rel = (c[4] or c[3] or "Association").replace("ArchiMate_", "")

                        # Parse waypoints from geometry/path
                        waypoints = []
                        if c[7]:  # path field
                            try:
                                for coord in c[7].split(";"):
                                    coord = coord.strip()
                                    if ":" in coord:
                                        px, py = coord.split(":")
                                        waypoints.append({"x": int(px) - min_x, "y": int(py) - min_y})
                            except:
                                pass

                        edges.append({
                            "id": c[0],
                            "source": c[1],
                            "target": c[2],
                            "relationship": rel,
                            "label": c[5] or "",
                            "waypoints": waypoints,
                        })

                    diag_entry["edges"] = edges

                diag_entry["nodes"] = nodes
                diag_entry["canvasWidth"] = max(all_right) - min_x + 40
                diag_entry["canvasHeight"] = max(all_bottom) - min_y + 40
                diag_entry["hasPositions"] = True

        diagrams.append(diag_entry)

    conn.close()

    # ── 5. Build navigation index ────────────────────────────────────────
    # element name → list of diagram IDs it appears on
    element_diagram_index = {}
    for d in diagrams:
        for n in d["nodes"]:
            if n["name"] not in element_diagram_index:
                element_diagram_index[n["name"]] = []
            element_diagram_index[n["name"]].append({
                "diagramId": d["id"],
                "diagramName": d["name"],
            })

    model_data = {
        "modelInfo": {
            "totalElements": len(elements),
            "totalRelationships": len(relationships),
            "totalDiagrams": len(diagram_rows),
            "extractedDiagrams": len(diagrams),
            "totalPackages": len(packages),
        },
        "packages": packages,
        "elements": elements,
        "relationships": relationships,
        "diagrams": diagrams,
        "elementDiagramIndex": element_diagram_index,
    }

    return f"""EXPLORER_MODEL_DATA
Complete model export for EA Explorer artifact.

Model: {len(elements)} elements, {len(relationships)} relationships,
       {len(diagrams)} diagrams (of {len(diagram_rows)} total), {len(packages)} packages

Navigation features included:
- Element positions on all {len(diagrams)} diagrams (from EA's t_diagramobjects)
- Connector routing waypoints (from EA's t_diagramlinks)
- Child diagram references (for drill-down navigation)
- Element-to-diagram index (for "find in diagram" feature)

Claude should inject this JSON into the EA Explorer artifact as EXPLORER_DATA,
replacing the DEMO_ constants. The artifact handles all navigation client-side.

```json
{json.dumps(model_data)}
```"""


# =========================================================================
# PROMPTS — Reusable context for Claude
# =========================================================================

@mcp.prompt()
def visualization_guide() -> str:
    """Guide for rendering EA model content visually in Claude Desktop."""
    return """When the user asks to SEE, DISPLAY, SHOW, or VISUALIZE model content:

## Diagrams → Mermaid Artifacts
Use these MCP tools and render the result as a .mermaid artifact:
- generate_dependency_diagram: Trace from one element → dependency graph
- generate_layer_diagram: Full ArchiMate layer view with cross-layer connectors
- get_diagram_elements: Recreate an existing EA diagram

## Catalogs → React Artifacts
Use generate_catalog and render the JSON data as a React (.jsx) artifact:
- catalog_type='elements': Sortable/filterable element table with layer color coding
- catalog_type='relationships': Relationship matrix with cross-layer highlighting
- catalog_type='diagrams': Diagram inventory with element counts
- catalog_type='packages': Tree hierarchy view
- catalog_type='coverage': Orphan analysis with coverage charts

## Statistics → React/HTML Artifacts
Use model_statistics and render as a dashboard artifact with:
- Pie/bar charts for layer distribution (use recharts)
- Coverage percentage bars
- Key metrics cards

## Color Scheme for ArchiMate Layers (use consistently):
- Business:       #FFFFB5 (warm yellow)
- Application:    #B5FFFF (cyan)
- Technology:     #C9E7B7 (green)
- Motivation:     #FFFFCC (light yellow)
- Strategy:       #F5DEAA (peach)
- Implementation: #FFE0E0 (pink)

## Rendering Rules:
1. Always create an ARTIFACT — never dump raw Mermaid/JSON in chat
2. For Mermaid: create a .mermaid file artifact
3. For catalogs: create a .jsx React artifact with Tailwind styling
4. For dashboards: create a .jsx artifact with recharts
5. Keep diagrams under 50 nodes for readability (filter or paginate)
6. Add a brief text summary BEFORE the artifact"""


@mcp.prompt()
def archimate_analysis_guide() -> str:
    """Guide for analyzing ArchiMate models in EA .qea files."""
    return """When analyzing an ArchiMate model in a .qea file:

1. Start with model_statistics to understand scale and layer distribution
2. Use list_elements with stereotype filters to explore each layer:
   - Business: stereotype='ArchiMate_Business%'
   - Application: stereotype='ArchiMate_Application%'
   - Technology: stereotype='ArchiMate_Node' or 'ArchiMate_Device' etc.
3. Use trace_dependencies to map impact chains between layers
4. Use validate_archimate to check relationship correctness
5. Use get_element_detail for deep-dive on specific components

Key EA database tables:
- t_object: All elements (Object_Type, Stereotype, Package_ID)
- t_connector: All relationships (Start_Object_ID, End_Object_ID)
- t_package: Package hierarchy (Parent_ID for nesting)
- t_diagram: Diagrams (Diagram_Type for notation)
- t_objectproperties: Tagged values (Property, Value)
- t_xref: Extended stereotypes (semicolon-delimited)

ArchiMate stereotypes in EA use prefix 'ArchiMate_' or 'ArchiMate3::ArchiMate_'"""


@mcp.prompt()
def impact_analysis_guide() -> str:
    """Guide for conducting impact analysis using the EA model."""
    return """To conduct an impact analysis:

1. Identify the changing element: get_element_detail for full context
2. Trace outbound dependencies: trace_dependencies(direction='outbound', depth=3)
3. Trace inbound dependencies: trace_dependencies(direction='inbound', depth=2)
4. For each affected element, assess:
   - Direct impact: connected by Serving, Realization, or Assignment
   - Indirect impact: connected by Flow, Triggering, or Association
   - Potential impact: 2+ hops away
5. Check which diagrams are affected: get_element_detail shows diagram list
6. Summarize blast radius by layer and severity"""


# =========================================================================
# Entry point
# =========================================================================

if __name__ == "__main__":
    mcp.run(transport="stdio")
