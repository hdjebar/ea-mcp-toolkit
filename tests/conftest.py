"""Shared fixtures for ea-mcp-toolkit tests.

Bootstraps a minimal .qea SQLite database and stubs out the ``mcp`` package
so ``ea-sqlite-mcp.py`` can be imported without the mcp[cli] package in the
test environment.  The ``@mcp.tool()`` and ``@mcp.prompt()`` decorators become
no-ops, so every tool function is a plain importable Python callable.
"""
import sys
import types
import importlib.util
import os
import sqlite3
import pytest


# ---------------------------------------------------------------------------
# Stub the mcp package before loading the server module
# ---------------------------------------------------------------------------

def _stub_mcp() -> None:
    """Insert minimal stub modules so the import-time @mcp.tool() works."""
    if "mcp" in sys.modules:
        return  # already stubbed (e.g. when pytest is re-running)

    mcp_mod = types.ModuleType("mcp")
    server_mod = types.ModuleType("mcp.server")
    fastmcp_mod = types.ModuleType("mcp.server.fastmcp")

    class _FakeFastMCP:
        """No-op stand-in for FastMCP; decorators pass functions through unchanged."""
        def __init__(self, *args, **kwargs): pass
        def tool(self):   return lambda f: f
        def prompt(self): return lambda f: f
        def run(self, *args, **kwargs): pass

    fastmcp_mod.FastMCP = _FakeFastMCP
    mcp_mod.server = server_mod
    server_mod.fastmcp = fastmcp_mod
    sys.modules["mcp"] = mcp_mod
    sys.modules["mcp.server"] = server_mod
    sys.modules["mcp.server.fastmcp"] = fastmcp_mod


_stub_mcp()

# Load ea-sqlite-mcp.py via importlib (hyphen in filename prevents normal import)
_SERVER_PATH = os.path.normpath(
    os.path.join(os.path.dirname(__file__), "..", "mcp-servers", "ea-sqlite-mcp.py")
)
_spec = importlib.util.spec_from_file_location("ea_sqlite_mcp", _SERVER_PATH)
_ea_mcp = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_ea_mcp)
sys.modules["ea_sqlite_mcp"] = _ea_mcp


# ---------------------------------------------------------------------------
# Minimal .qea fixture
# ---------------------------------------------------------------------------

_SCHEMA_SQL = """
CREATE TABLE t_object (
    Object_ID   INTEGER PRIMARY KEY,
    Name        TEXT, Object_Type TEXT, Stereotype TEXT,
    Note        TEXT, Alias TEXT, Status TEXT, Phase TEXT,
    Version     TEXT, Author TEXT, Complexity TEXT,
    Package_ID  INTEGER, PDATA1 TEXT
);
CREATE TABLE t_connector (
    Connector_ID    INTEGER PRIMARY KEY,
    Name TEXT, Connector_Type TEXT, Stereotype TEXT,
    Start_Object_ID INTEGER, End_Object_ID INTEGER, Direction TEXT
);
CREATE TABLE t_package (
    Package_ID INTEGER PRIMARY KEY, Name TEXT, Parent_ID INTEGER
);
CREATE TABLE t_diagram (
    Diagram_ID INTEGER PRIMARY KEY, Name TEXT, Diagram_Type TEXT,
    Package_ID INTEGER, Author TEXT, Version TEXT, ParentID INTEGER,
    cx INTEGER, cy INTEGER
);
CREATE TABLE t_diagramobjects (
    Diagram_ID INTEGER, Object_ID INTEGER,
    RectTop INTEGER, RectLeft INTEGER, RectRight INTEGER, RectBottom INTEGER,
    Sequence INTEGER, ObjectStyle TEXT
);
CREATE TABLE t_diagramlinks (
    ConnectorID INTEGER, DiagramID INTEGER,
    Geometry TEXT, Style TEXT, Hidden INTEGER, Path TEXT
);
CREATE TABLE t_objectproperties (
    PropertyID INTEGER PRIMARY KEY,
    Object_ID INTEGER, Property TEXT, Value TEXT
);
CREATE TABLE t_attribute (
    ID INTEGER PRIMARY KEY,
    Object_ID INTEGER, Name TEXT, Type TEXT,
    Default TEXT, Notes TEXT, Pos INTEGER
);
CREATE TABLE t_operation (
    OperationID INTEGER PRIMARY KEY,
    Object_ID INTEGER, Name TEXT, Type TEXT, Notes TEXT, Pos INTEGER
);
CREATE TABLE t_xref (
    XrefID TEXT PRIMARY KEY, Client INTEGER, Supplier INTEGER,
    Name TEXT, Type TEXT, Visibility TEXT,
    Namespace TEXT, Notes TEXT, Description TEXT
);
── Packages (3-level hierarchy)
INSERT INTO t_package VALUES (1,'Business',0);
INSERT INTO t_package VALUES (2,'Application',1);
INSERT INTO t_package VALUES (3,'Technology',2);
── Elements
INSERT INTO t_object VALUES
    (1,'Order Management','Class','ArchiMate_BusinessProcess','Handles orders',
     NULL,'Proposed','1.0','1','Alice','Medium',1,NULL);
INSERT INTO t_object VALUES
    (2,'CRM System','Class','ArchiMate_ApplicationComponent','CRM app',
     NULL,'Active','1.0','2','Bob','High',2,NULL);
INSERT INTO t_object VALUES
    (3,'Database Server','Node','ArchiMate_Node','DB host',
     NULL,'Active','1.0','1','Charlie','Low',3,NULL);
INSERT INTO t_object VALUES
    (4,'Payment Gateway','Class','ArchiMate_ApplicationComponent','Processes payments',
     NULL,'Active','1.0','1','Alice','High',2,NULL);
INSERT INTO t_object VALUES
    (5,'Customer Goal','Class','ArchiMate_Goal','Satisfy customers',
     NULL,'Active','1.0','1','Alice','Low',1,NULL);
INSERT INTO t_object VALUES
    (6,'Orphan Element','Class','ArchiMate_BusinessActor','Not on any diagram',
     NULL,'Proposed','1.0','1','Alice','Low',1,NULL);
── Connectors
──  CRM System --[Serving]--> Order Management (cross-layer Application->Business)
INSERT INTO t_connector VALUES
    (1,'Serves','Serving','ArchiMate_Serving',2,1,'Source->Destination');
──  CRM System --[Realization]--> Database Server (Application realizes Technology)
INSERT INTO t_connector VALUES
    (2,'Runs On','Realization','ArchiMate_Realization',2,3,'Source->Destination');
──  BadRelation: unknown type, should be caught by validate_archimate
INSERT INTO t_connector VALUES
    (3,'BadRelation','UnknownRelType','UnknownRelType',1,5,'Source->Destination');
── Diagrams
INSERT INTO t_diagram VALUES (1,'Application Architecture','Logical',2,'Alice','1.0',0,800,600);
INSERT INTO t_diagram VALUES (2,'Technology View','Logical',3,'Bob','1.0',0,600,400);
── Diagram placements (pixels from EA canvas)
INSERT INTO t_diagramobjects VALUES (1,1,100,100,300,200,1,NULL);
INSERT INTO t_diagramobjects VALUES (1,2,100,400,600,200,2,NULL);
INSERT INTO t_diagramobjects VALUES (1,3,300,100,500,400,3,NULL);
INSERT INTO t_diagramobjects VALUES (2,3,100,100,300,200,1,NULL);
── Tagged values on Order Management
INSERT INTO t_objectproperties VALUES (1,1,'Owner','Alice');
INSERT INTO t_objectproperties VALUES (2,1,'Priority','High');
"""


@pytest.fixture(scope="session")
def qea_path(tmp_path_factory):
    """Write a minimal .qea fixture file and return its path string."""
    db = tmp_path_factory.mktemp("qea") / "test.qea"
    conn = sqlite3.connect(str(db))
    # Strip the ── comment lines before executing
    ddl = "\n".join(
        line for line in _SCHEMA_SQL.splitlines()
        if not line.strip().startswith("──")
    )
    conn.executescript(ddl)
    conn.commit()
    conn.close()
    return str(db)
