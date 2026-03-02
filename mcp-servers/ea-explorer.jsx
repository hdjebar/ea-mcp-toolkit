import { useState, useMemo, useCallback, useEffect, useRef } from "react";
import * as d3 from "d3";
import { Search, ChevronRight, ChevronDown, Package, FileBox, Layers, Link2, LayoutGrid, Activity, Eye, X, Filter, Table2, GitBranch, Info, ArrowRight, Maximize2 } from "lucide-react";

/*
 * EA Explorer — Sparx EA-like browsing experience for Claude Desktop
 *
 * Claude: When the user asks to explore/browse a .qea model, call these
 * MCP tools and embed the results in this artifact:
 *
 *   1. model_statistics(qea_path)
 *   2. generate_catalog(qea_path, "elements", format="json")
 *   3. generate_catalog(qea_path, "relationships", format="json")
 *   4. generate_catalog(qea_path, "packages", format="json")
 *   5. generate_catalog(qea_path, "diagrams", format="json")
 *
 * Replace the DEMO_DATA below with the actual MCP output.
 */

// ─── DEMO DATA (replace with MCP output) ────────────────────────────────
const DEMO_ELEMENTS = [
  { id: 1, name: "Customer", type: "Class", stereotype: "BusinessActor", layer: "Business", package: "Business Layer", status: "Approved", connections: 5, onDiagrams: 3 },
  { id: 2, name: "Order Management", type: "Class", stereotype: "BusinessProcess", layer: "Business", package: "Business Layer", status: "Approved", connections: 8, onDiagrams: 4 },
  { id: 3, name: "Invoice Processing", type: "Class", stereotype: "BusinessProcess", layer: "Business", package: "Business Layer", status: "Draft", connections: 4, onDiagrams: 2 },
  { id: 4, name: "Order Service", type: "Class", stereotype: "BusinessService", layer: "Business", package: "Business Layer", status: "Approved", connections: 6, onDiagrams: 3 },
  { id: 5, name: "Billing Service", type: "Class", stereotype: "BusinessService", layer: "Business", package: "Business Layer", status: "Approved", connections: 3, onDiagrams: 2 },
  { id: 10, name: "CRM System", type: "Component", stereotype: "ApplicationComponent", layer: "Application", package: "Application Layer", status: "Approved", connections: 7, onDiagrams: 5 },
  { id: 11, name: "ERP System", type: "Component", stereotype: "ApplicationComponent", layer: "Application", package: "Application Layer", status: "Approved", connections: 9, onDiagrams: 4 },
  { id: 12, name: "Payment Gateway", type: "Component", stereotype: "ApplicationComponent", layer: "Application", package: "Application Layer", status: "Draft", connections: 5, onDiagrams: 3 },
  { id: 13, name: "Order API", type: "Component", stereotype: "ApplicationService", layer: "Application", package: "Application Layer", status: "Approved", connections: 6, onDiagrams: 3 },
  { id: 14, name: "Customer API", type: "Component", stereotype: "ApplicationService", layer: "Application", package: "Application Layer", status: "Approved", connections: 4, onDiagrams: 2 },
  { id: 15, name: "Customer DB", type: "Component", stereotype: "DataObject", layer: "Application", package: "Application Layer", status: "Approved", connections: 3, onDiagrams: 2 },
  { id: 16, name: "Order DB", type: "Component", stereotype: "DataObject", layer: "Application", package: "Application Layer", status: "Approved", connections: 4, onDiagrams: 2 },
  { id: 20, name: "App Server Cluster", type: "Node", stereotype: "Node", layer: "Technology", package: "Technology Layer", status: "Approved", connections: 5, onDiagrams: 3 },
  { id: 21, name: "Database Server", type: "Node", stereotype: "Device", layer: "Technology", package: "Technology Layer", status: "Approved", connections: 4, onDiagrams: 2 },
  { id: 22, name: "Load Balancer", type: "Node", stereotype: "Node", layer: "Technology", package: "Technology Layer", status: "Approved", connections: 3, onDiagrams: 2 },
  { id: 23, name: "Kubernetes Platform", type: "Node", stereotype: "SystemSoftware", layer: "Technology", package: "Technology Layer", status: "Draft", connections: 6, onDiagrams: 3 },
  { id: 24, name: "PostgreSQL", type: "Node", stereotype: "SystemSoftware", layer: "Technology", package: "Technology Layer", status: "Approved", connections: 3, onDiagrams: 2 },
  { id: 30, name: "Improve Customer Experience", type: "Goal", stereotype: "Goal", layer: "Motivation", package: "Motivation", status: "", connections: 3, onDiagrams: 1 },
  { id: 31, name: "Reduce Operational Cost", type: "Goal", stereotype: "Goal", layer: "Motivation", package: "Motivation", status: "", connections: 2, onDiagrams: 1 },
  { id: 32, name: "Digital First Strategy", type: "Principle", stereotype: "Principle", layer: "Motivation", package: "Motivation", status: "", connections: 4, onDiagrams: 1 },
];

const DEMO_RELATIONSHIPS = [
  { source: "Customer", sourceLayer: "Business", relationship: "Serving", target: "Order Management", targetLayer: "Business" },
  { source: "Order Management", sourceLayer: "Business", relationship: "Triggering", target: "Invoice Processing", targetLayer: "Business" },
  { source: "Order Management", sourceLayer: "Business", relationship: "Realization", target: "Order Service", targetLayer: "Business" },
  { source: "Invoice Processing", sourceLayer: "Business", relationship: "Realization", target: "Billing Service", targetLayer: "Business" },
  { source: "CRM System", sourceLayer: "Application", relationship: "Serving", target: "Order Service", targetLayer: "Business" },
  { source: "ERP System", sourceLayer: "Application", relationship: "Serving", target: "Billing Service", targetLayer: "Business" },
  { source: "CRM System", sourceLayer: "Application", relationship: "Serving", target: "Customer API", targetLayer: "Application" },
  { source: "ERP System", sourceLayer: "Application", relationship: "Serving", target: "Order API", targetLayer: "Application" },
  { source: "Payment Gateway", sourceLayer: "Application", relationship: "Serving", target: "ERP System", targetLayer: "Application" },
  { source: "Order API", sourceLayer: "Application", relationship: "Access", target: "Order DB", targetLayer: "Application" },
  { source: "Customer API", sourceLayer: "Application", relationship: "Access", target: "Customer DB", targetLayer: "Application" },
  { source: "App Server Cluster", sourceLayer: "Technology", relationship: "Serving", target: "CRM System", targetLayer: "Application" },
  { source: "App Server Cluster", sourceLayer: "Technology", relationship: "Serving", target: "ERP System", targetLayer: "Application" },
  { source: "Database Server", sourceLayer: "Technology", relationship: "Serving", target: "Customer DB", targetLayer: "Application" },
  { source: "Database Server", sourceLayer: "Technology", relationship: "Serving", target: "Order DB", targetLayer: "Application" },
  { source: "Load Balancer", sourceLayer: "Technology", relationship: "Serving", target: "App Server Cluster", targetLayer: "Technology" },
  { source: "Kubernetes Platform", sourceLayer: "Technology", relationship: "Assignment", target: "App Server Cluster", targetLayer: "Technology" },
  { source: "PostgreSQL", sourceLayer: "Technology", relationship: "Assignment", target: "Database Server", targetLayer: "Technology" },
  { source: "Improve Customer Experience", sourceLayer: "Motivation", relationship: "Realization", target: "Digital First Strategy", targetLayer: "Motivation" },
  { source: "Digital First Strategy", sourceLayer: "Motivation", relationship: "Realization", target: "CRM System", targetLayer: "Application" },
  { source: "Reduce Operational Cost", sourceLayer: "Motivation", relationship: "Influence", target: "Kubernetes Platform", targetLayer: "Technology" },
];

const DEMO_PACKAGES = [
  { id: 100, name: "Enterprise Architecture", parentId: 0, elements: 0, diagrams: 0 },
  { id: 101, name: "Business Layer", parentId: 100, elements: 5, diagrams: 2 },
  { id: 102, name: "Application Layer", parentId: 100, elements: 7, diagrams: 3 },
  { id: 103, name: "Technology Layer", parentId: 100, elements: 5, diagrams: 2 },
  { id: 104, name: "Motivation", parentId: 100, elements: 3, diagrams: 1 },
];

const DEMO_DIAGRAMS = [
  { id: 1, name: "Business Process View", type: "ArchiMate", package: "Business Layer", elements: 8 },
  { id: 2, name: "Application Cooperation", type: "ArchiMate", package: "Application Layer", elements: 12 },
  { id: 3, name: "Infrastructure View", type: "ArchiMate", package: "Technology Layer", elements: 9 },
  { id: 4, name: "Layered View", type: "ArchiMate", package: "Enterprise Architecture", elements: 20 },
  { id: 5, name: "Motivation View", type: "ArchiMate", package: "Motivation", elements: 5 },
];

// ─── CONSTANTS ───────────────────────────────────────────────────────────
const LAYER_COLORS = {
  Business: { bg: "#FFF8DC", border: "#D4A843", text: "#8B6914", chip: "#F5DEB3", accent: "#DAA520" },
  Application: { bg: "#E0FFFF", border: "#5F9EA0", text: "#2F4F4F", chip: "#B0E0E6", accent: "#5F9EA0" },
  Technology: { bg: "#F0FFF0", border: "#6B8E23", text: "#2E4A1C", chip: "#C1E1C1", accent: "#6B8E23" },
  Motivation: { bg: "#FFFACD", border: "#BDB76B", text: "#6B6B00", chip: "#FAFAD2", accent: "#BDB76B" },
  Strategy: { bg: "#FFE4C4", border: "#CD853F", text: "#8B4513", chip: "#FFDAB9", accent: "#CD853F" },
  Implementation: { bg: "#FFE4E1", border: "#CD5C5C", text: "#8B0000", chip: "#FFC0CB", accent: "#CD5C5C" },
};

const REL_STYLES = {
  Composition: { dash: "", marker: "●", color: "#333" },
  Aggregation: { dash: "", marker: "◇", color: "#333" },
  Assignment: { dash: "", marker: "→", color: "#4A90D9" },
  Realization: { dash: "4,3", marker: "▷", color: "#6B8E23" },
  Serving: { dash: "", marker: "→", color: "#D4A843" },
  Access: { dash: "4,3", marker: "→", color: "#CD853F" },
  Influence: { dash: "2,3", marker: "→", color: "#BDB76B" },
  Association: { dash: "", marker: "—", color: "#999" },
  Triggering: { dash: "", marker: "→", color: "#C0392B" },
  Flow: { dash: "", marker: "⇒", color: "#2980B9" },
  Specialization: { dash: "", marker: "▷", color: "#333" },
};

// ─── HELPERS ─────────────────────────────────────────────────────────────
const getLayerColor = (layer) => LAYER_COLORS[layer] || { bg: "#F5F5F5", border: "#CCC", text: "#333", chip: "#DDD", accent: "#999" };

function LayerChip({ layer }) {
  const c = getLayerColor(layer);
  if (!layer) return null;
  return (
    <span style={{
      display: "inline-block", padding: "1px 8px", borderRadius: 3,
      fontSize: 10, fontWeight: 600, letterSpacing: "0.5px",
      background: c.chip, color: c.text, border: `1px solid ${c.border}`,
      textTransform: "uppercase", whiteSpace: "nowrap",
    }}>{layer}</span>
  );
}

function RelChip({ type }) {
  const s = REL_STYLES[type] || REL_STYLES.Association;
  return (
    <span style={{
      display: "inline-flex", alignItems: "center", gap: 3,
      padding: "1px 6px", borderRadius: 3, fontSize: 10,
      background: `${s.color}18`, color: s.color, border: `1px solid ${s.color}40`,
      fontWeight: 500, whiteSpace: "nowrap",
    }}>
      <span style={{ fontSize: 8 }}>{s.marker}</span> {type}
    </span>
  );
}

// ─── PACKAGE TREE ────────────────────────────────────────────────────────
function PackageTree({ packages, elements, diagrams, onSelectPackage, onSelectElement, selectedPkg }) {
  const [expanded, setExpanded] = useState(new Set([100]));

  const tree = useMemo(() => {
    const map = {};
    packages.forEach(p => map[p.id] = { ...p, children: [] });
    const roots = [];
    packages.forEach(p => {
      if (p.parentId && map[p.parentId]) map[p.parentId].children.push(map[p.id]);
      else roots.push(map[p.id]);
    });
    return roots;
  }, [packages]);

  const toggle = (id) => setExpanded(prev => {
    const next = new Set(prev);
    next.has(id) ? next.delete(id) : next.add(id);
    return next;
  });

  const renderNode = (node, depth = 0) => {
    const isExpanded = expanded.has(node.id);
    const isSelected = selectedPkg === node.id;
    const hasChildren = node.children.length > 0;
    const pkgElements = elements.filter(e => e.package === node.name);
    const pkgDiagrams = diagrams.filter(d => d.package === node.name);

    return (
      <div key={node.id}>
        <div
          onClick={() => { toggle(node.id); onSelectPackage(node.id, node.name); }}
          style={{
            display: "flex", alignItems: "center", gap: 4, padding: "4px 6px",
            paddingLeft: 8 + depth * 16, cursor: "pointer", fontSize: 12,
            background: isSelected ? "#E8F0FE" : "transparent",
            borderLeft: isSelected ? "2px solid #4A90D9" : "2px solid transparent",
            transition: "all 0.15s",
          }}
          onMouseEnter={e => { if (!isSelected) e.currentTarget.style.background = "#F5F5F5"; }}
          onMouseLeave={e => { if (!isSelected) e.currentTarget.style.background = "transparent"; }}
        >
          {hasChildren ? (
            isExpanded ? <ChevronDown size={12} color="#666" /> : <ChevronRight size={12} color="#666" />
          ) : <span style={{ width: 12 }} />}
          <Package size={13} color="#D4A843" />
          <span style={{ flex: 1, fontWeight: hasChildren ? 600 : 400, color: "#333" }}>{node.name}</span>
          <span style={{ fontSize: 10, color: "#999" }}>{node.elements}</span>
        </div>
        {isExpanded && (
          <>
            {node.children.map(child => renderNode(child, depth + 1))}
            {pkgDiagrams.map(d => (
              <div key={`d-${d.id}`} style={{
                display: "flex", alignItems: "center", gap: 4, padding: "3px 6px",
                paddingLeft: 24 + depth * 16, fontSize: 11, color: "#666", cursor: "pointer",
              }}
              onMouseEnter={e => e.currentTarget.style.background = "#F5F5F5"}
              onMouseLeave={e => e.currentTarget.style.background = "transparent"}
              >
                <LayoutGrid size={11} color="#5F9EA0" />
                <span>{d.name}</span>
                <span style={{ fontSize: 9, color: "#AAA", marginLeft: "auto" }}>{d.elements}</span>
              </div>
            ))}
            {pkgElements.map(el => (
              <div key={`e-${el.id}`} onClick={() => onSelectElement(el)}
                style={{
                  display: "flex", alignItems: "center", gap: 4, padding: "3px 6px",
                  paddingLeft: 24 + depth * 16, fontSize: 11, color: "#555", cursor: "pointer",
                }}
                onMouseEnter={e => e.currentTarget.style.background = "#F5F5F5"}
                onMouseLeave={e => e.currentTarget.style.background = "transparent"}
              >
                <FileBox size={11} color={getLayerColor(el.layer).accent} />
                <span>{el.name}</span>
                <span style={{ marginLeft: "auto" }}><LayerChip layer={el.layer} /></span>
              </div>
            ))}
          </>
        )}
      </div>
    );
  };

  return <div style={{ overflowY: "auto", flex: 1 }}>{tree.map(n => renderNode(n))}</div>;
}

// ─── DIAGRAM VIEW (D3 Force Graph) ──────────────────────────────────────
function DiagramView({ elements, relationships, onSelectElement, selectedElement, filterLayer }) {
  const svgRef = useRef(null);
  const containerRef = useRef(null);
  const [dimensions, setDimensions] = useState({ width: 800, height: 500 });

  const filtered = useMemo(() => {
    let els = elements;
    if (filterLayer && filterLayer !== "All") {
      els = elements.filter(e => e.layer === filterLayer);
    }
    const names = new Set(els.map(e => e.name));
    const rels = relationships.filter(r => names.has(r.source) && names.has(r.target));
    return { elements: els, relationships: rels };
  }, [elements, relationships, filterLayer]);

  useEffect(() => {
    if (!containerRef.current) return;
    const ro = new ResizeObserver(entries => {
      const { width, height } = entries[0].contentRect;
      setDimensions({ width: Math.max(width, 400), height: Math.max(height, 300) });
    });
    ro.observe(containerRef.current);
    return () => ro.disconnect();
  }, []);

  useEffect(() => {
    if (!svgRef.current || filtered.elements.length === 0) return;

    const { width, height } = dimensions;
    const svg = d3.select(svgRef.current);
    svg.selectAll("*").remove();

    // Defs for arrows
    const defs = svg.append("defs");
    Object.entries(REL_STYLES).forEach(([name, style]) => {
      defs.append("marker")
        .attr("id", `arrow-${name}`)
        .attr("viewBox", "0 -5 10 10")
        .attr("refX", 28).attr("refY", 0)
        .attr("markerWidth", 6).attr("markerHeight", 6)
        .attr("orient", "auto")
        .append("path").attr("d", "M0,-4L10,0L0,4").attr("fill", style.color);
    });

    // Layer backgrounds
    const layerOrder = ["Motivation", "Strategy", "Business", "Application", "Technology", "Implementation"];
    const presentLayers = [...new Set(filtered.elements.map(e => e.layer))].sort(
      (a, b) => layerOrder.indexOf(a) - layerOrder.indexOf(b)
    );
    const layerHeight = height / Math.max(presentLayers.length, 1);

    const layerBg = svg.append("g").attr("class", "layer-backgrounds");
    presentLayers.forEach((layer, i) => {
      const c = getLayerColor(layer);
      layerBg.append("rect")
        .attr("x", 0).attr("y", i * layerHeight)
        .attr("width", width).attr("height", layerHeight)
        .attr("fill", c.bg).attr("opacity", 0.5);
      layerBg.append("text")
        .attr("x", 8).attr("y", i * layerHeight + 16)
        .attr("font-size", 10).attr("font-weight", 700)
        .attr("fill", c.text).attr("opacity", 0.6)
        .text(`${layer} Layer`);
    });

    const nodes = filtered.elements.map(e => ({
      ...e,
      targetY: (presentLayers.indexOf(e.layer) + 0.5) * layerHeight,
    }));
    const links = filtered.relationships.map(r => ({
      ...r,
      sourceNode: nodes.find(n => n.name === r.source),
      targetNode: nodes.find(n => n.name === r.target),
    })).filter(l => l.sourceNode && l.targetNode);

    const simulation = d3.forceSimulation(nodes)
      .force("link", d3.forceLink(links).id(d => d.name)
        .distance(100).strength(0.3)
        .id(d => d.name))
      .force("charge", d3.forceManyBody().strength(-200))
      .force("x", d3.forceX(width / 2).strength(0.05))
      .force("y", d3.forceY(d => d.targetY).strength(0.4))
      .force("collision", d3.forceCollide().radius(45));

    // Fix links source/target to node references
    links.forEach(l => {
      l.source = l.sourceNode;
      l.target = l.targetNode;
    });

    const linkGroup = svg.append("g");
    const link = linkGroup.selectAll("line").data(links).enter().append("line")
      .attr("stroke", d => (REL_STYLES[d.relationship] || REL_STYLES.Association).color)
      .attr("stroke-width", 1.5)
      .attr("stroke-dasharray", d => (REL_STYLES[d.relationship] || REL_STYLES.Association).dash)
      .attr("marker-end", d => `url(#arrow-${d.relationship || "Association"})`);

    const linkLabels = linkGroup.selectAll("text").data(links).enter().append("text")
      .attr("font-size", 8).attr("fill", "#999").attr("text-anchor", "middle")
      .text(d => d.relationship);

    const nodeGroup = svg.append("g");
    const node = nodeGroup.selectAll("g").data(nodes).enter().append("g")
      .style("cursor", "pointer")
      .call(d3.drag()
        .on("start", (event, d) => { if (!event.active) simulation.alphaTarget(0.3).restart(); d.fx = d.x; d.fy = d.y; })
        .on("drag", (event, d) => { d.fx = event.x; d.fy = event.y; })
        .on("end", (event, d) => { if (!event.active) simulation.alphaTarget(0); d.fx = null; d.fy = null; })
      )
      .on("click", (event, d) => onSelectElement(d));

    // Node rectangles
    node.append("rect")
      .attr("width", 120).attr("height", 44)
      .attr("x", -60).attr("y", -22)
      .attr("rx", 4)
      .attr("fill", d => getLayerColor(d.layer).bg)
      .attr("stroke", d => selectedElement?.id === d.id ? "#4A90D9" : getLayerColor(d.layer).border)
      .attr("stroke-width", d => selectedElement?.id === d.id ? 2.5 : 1.2);

    // Element name
    node.append("text")
      .attr("text-anchor", "middle").attr("dy", -3)
      .attr("font-size", 10).attr("font-weight", 600)
      .attr("fill", d => getLayerColor(d.layer).text)
      .text(d => d.name.length > 16 ? d.name.slice(0, 15) + "…" : d.name);

    // Stereotype
    node.append("text")
      .attr("text-anchor", "middle").attr("dy", 10)
      .attr("font-size", 8).attr("fill", "#999")
      .text(d => `«${d.stereotype}»`);

    simulation.on("tick", () => {
      nodes.forEach(d => {
        d.x = Math.max(65, Math.min(width - 65, d.x));
        d.y = Math.max(25, Math.min(height - 25, d.y));
      });
      link.attr("x1", d => d.source.x).attr("y1", d => d.source.y)
        .attr("x2", d => d.target.x).attr("y2", d => d.target.y);
      linkLabels
        .attr("x", d => (d.source.x + d.target.x) / 2)
        .attr("y", d => (d.source.y + d.target.y) / 2 - 4);
      node.attr("transform", d => `translate(${d.x},${d.y})`);
    });

    return () => simulation.stop();
  }, [filtered, dimensions, selectedElement, onSelectElement]);

  return (
    <div ref={containerRef} style={{ flex: 1, position: "relative", overflow: "hidden" }}>
      <svg ref={svgRef} width={dimensions.width} height={dimensions.height}
        style={{ background: "#FAFBFC" }} />
    </div>
  );
}

// ─── PROPERTIES PANEL ────────────────────────────────────────────────────
function PropertiesPanel({ element, relationships, onClose }) {
  const [tab, setTab] = useState("general");
  if (!element) return (
    <div style={{ display: "flex", alignItems: "center", justifyContent: "center", height: "100%", color: "#AAA", fontSize: 12, padding: 20, textAlign: "center" }}>
      <div>
        <Info size={32} color="#DDD" style={{ margin: "0 auto 8px" }} />
        <div>Select an element to view properties</div>
      </div>
    </div>
  );

  const outbound = relationships.filter(r => r.source === element.name);
  const inbound = relationships.filter(r => r.target === element.name);
  const c = getLayerColor(element.layer);

  const tabs = [
    { id: "general", label: "General" },
    { id: "connections", label: `Connections (${outbound.length + inbound.length})` },
  ];

  return (
    <div style={{ display: "flex", flexDirection: "column", height: "100%" }}>
      {/* Header */}
      <div style={{ padding: "10px 12px", background: c.bg, borderBottom: `2px solid ${c.border}` }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "start" }}>
          <div>
            <div style={{ fontSize: 13, fontWeight: 700, color: c.text }}>{element.name}</div>
            <div style={{ fontSize: 10, color: c.text, opacity: 0.7, marginTop: 2 }}>«{element.stereotype}»</div>
          </div>
          <button onClick={onClose}
            style={{ background: "none", border: "none", cursor: "pointer", padding: 2 }}>
            <X size={14} color="#999" />
          </button>
        </div>
        <div style={{ display: "flex", gap: 4, marginTop: 6 }}>
          <LayerChip layer={element.layer} />
          {element.status && (
            <span style={{
              fontSize: 10, padding: "1px 6px", borderRadius: 3,
              background: element.status === "Approved" ? "#D4EDDA" : "#FFF3CD",
              color: element.status === "Approved" ? "#155724" : "#856404",
              fontWeight: 500,
            }}>{element.status}</span>
          )}
        </div>
      </div>

      {/* Tabs */}
      <div style={{ display: "flex", borderBottom: "1px solid #E5E5E5" }}>
        {tabs.map(t => (
          <button key={t.id} onClick={() => setTab(t.id)}
            style={{
              flex: 1, padding: "6px 8px", fontSize: 10, fontWeight: 600,
              background: tab === t.id ? "#FFF" : "#F9F9F9",
              border: "none", borderBottom: tab === t.id ? "2px solid #4A90D9" : "2px solid transparent",
              color: tab === t.id ? "#4A90D9" : "#999", cursor: "pointer",
            }}>
            {t.label}
          </button>
        ))}
      </div>

      {/* Content */}
      <div style={{ flex: 1, overflowY: "auto", padding: 10, fontSize: 11 }}>
        {tab === "general" && (
          <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
            {[
              ["Type", element.type],
              ["Stereotype", element.stereotype],
              ["Layer", element.layer],
              ["Package", element.package],
              ["Status", element.status || "—"],
              ["Connections", element.connections],
              ["On Diagrams", element.onDiagrams],
            ].map(([label, value]) => (
              <div key={label} style={{ display: "flex", justifyContent: "space-between" }}>
                <span style={{ color: "#888", fontWeight: 500 }}>{label}</span>
                <span style={{ color: "#333", fontWeight: 400, textAlign: "right" }}>{value}</span>
              </div>
            ))}
          </div>
        )}
        {tab === "connections" && (
          <div>
            {outbound.length > 0 && (
              <>
                <div style={{ fontSize: 10, fontWeight: 700, color: "#666", marginBottom: 4 }}>
                  OUTBOUND ({outbound.length})
                </div>
                {outbound.map((r, i) => (
                  <div key={`o-${i}`} style={{
                    padding: "4px 0", borderBottom: "1px solid #F0F0F0",
                    display: "flex", alignItems: "center", gap: 4, flexWrap: "wrap",
                  }}>
                    <RelChip type={r.relationship} />
                    <ArrowRight size={10} color="#CCC" />
                    <span style={{ fontWeight: 500 }}>{r.target}</span>
                    <LayerChip layer={r.targetLayer} />
                  </div>
                ))}
              </>
            )}
            {inbound.length > 0 && (
              <>
                <div style={{ fontSize: 10, fontWeight: 700, color: "#666", margin: "8px 0 4px" }}>
                  INBOUND ({inbound.length})
                </div>
                {inbound.map((r, i) => (
                  <div key={`i-${i}`} style={{
                    padding: "4px 0", borderBottom: "1px solid #F0F0F0",
                    display: "flex", alignItems: "center", gap: 4, flexWrap: "wrap",
                  }}>
                    <span style={{ fontWeight: 500 }}>{r.source}</span>
                    <LayerChip layer={r.sourceLayer} />
                    <RelChip type={r.relationship} />
                  </div>
                ))}
              </>
            )}
          </div>
        )}
      </div>
    </div>
  );
}

// ─── ELEMENT TABLE ───────────────────────────────────────────────────────
function ElementTable({ elements, relationships, search, filterLayer, onSelectElement, selectedElement }) {
  const [sortKey, setSortKey] = useState("name");
  const [sortAsc, setSortAsc] = useState(true);

  const data = useMemo(() => {
    let filtered = elements;
    if (search) {
      const q = search.toLowerCase();
      filtered = filtered.filter(e =>
        e.name.toLowerCase().includes(q) ||
        e.stereotype.toLowerCase().includes(q) ||
        e.package.toLowerCase().includes(q)
      );
    }
    if (filterLayer && filterLayer !== "All") {
      filtered = filtered.filter(e => e.layer === filterLayer);
    }
    return [...filtered].sort((a, b) => {
      const av = a[sortKey], bv = b[sortKey];
      const cmp = typeof av === "number" ? av - bv : String(av).localeCompare(String(bv));
      return sortAsc ? cmp : -cmp;
    });
  }, [elements, search, filterLayer, sortKey, sortAsc]);

  const handleSort = (key) => {
    if (sortKey === key) setSortAsc(!sortAsc);
    else { setSortKey(key); setSortAsc(true); }
  };

  const cols = [
    { key: "name", label: "Name", flex: 2 },
    { key: "stereotype", label: "Stereotype", flex: 1.5 },
    { key: "layer", label: "Layer", flex: 1 },
    { key: "package", label: "Package", flex: 1.5 },
    { key: "connections", label: "Conn", flex: 0.5 },
    { key: "onDiagrams", label: "Diag", flex: 0.5 },
  ];

  return (
    <div style={{ display: "flex", flexDirection: "column", height: "100%", overflow: "hidden" }}>
      {/* Header */}
      <div style={{
        display: "flex", background: "#F5F5F5", borderBottom: "1px solid #E0E0E0",
        position: "sticky", top: 0, zIndex: 1,
      }}>
        {cols.map(c => (
          <div key={c.key} onClick={() => handleSort(c.key)}
            style={{
              flex: c.flex, padding: "6px 8px", fontSize: 10, fontWeight: 700,
              color: sortKey === c.key ? "#4A90D9" : "#888",
              cursor: "pointer", userSelect: "none",
              display: "flex", alignItems: "center", gap: 2,
            }}>
            {c.label}
            {sortKey === c.key && <span>{sortAsc ? "↑" : "↓"}</span>}
          </div>
        ))}
      </div>
      {/* Rows */}
      <div style={{ flex: 1, overflowY: "auto" }}>
        {data.map(el => (
          <div key={el.id} onClick={() => onSelectElement(el)}
            style={{
              display: "flex", borderBottom: "1px solid #F0F0F0",
              background: selectedElement?.id === el.id ? "#E8F0FE" : "transparent",
              cursor: "pointer", transition: "background 0.1s",
            }}
            onMouseEnter={e => { if (selectedElement?.id !== el.id) e.currentTarget.style.background = "#FAFAFA"; }}
            onMouseLeave={e => { if (selectedElement?.id !== el.id) e.currentTarget.style.background = "transparent"; }}
          >
            <div style={{ flex: 2, padding: "5px 8px", fontSize: 11, fontWeight: 500, color: "#333" }}>{el.name}</div>
            <div style={{ flex: 1.5, padding: "5px 8px", fontSize: 10, color: "#666" }}>«{el.stereotype}»</div>
            <div style={{ flex: 1, padding: "5px 8px" }}><LayerChip layer={el.layer} /></div>
            <div style={{ flex: 1.5, padding: "5px 8px", fontSize: 10, color: "#888" }}>{el.package}</div>
            <div style={{ flex: 0.5, padding: "5px 8px", fontSize: 10, color: "#999", textAlign: "center" }}>{el.connections}</div>
            <div style={{ flex: 0.5, padding: "5px 8px", fontSize: 10, color: "#999", textAlign: "center" }}>{el.onDiagrams}</div>
          </div>
        ))}
        {data.length === 0 && (
          <div style={{ padding: 20, textAlign: "center", color: "#AAA", fontSize: 12 }}>No elements match the filter</div>
        )}
      </div>
      <div style={{ padding: "4px 8px", fontSize: 10, color: "#AAA", background: "#FAFAFA", borderTop: "1px solid #E5E5E5" }}>
        {data.length} of {elements.length} elements
      </div>
    </div>
  );
}

// ─── MAIN APP ────────────────────────────────────────────────────────────
export default function EAExplorer() {
  const [view, setView] = useState("diagram");
  const [selectedElement, setSelectedElement] = useState(null);
  const [selectedPkg, setSelectedPkg] = useState(null);
  const [search, setSearch] = useState("");
  const [filterLayer, setFilterLayer] = useState("All");
  const [showProperties, setShowProperties] = useState(false);
  const [treeCollapsed, setTreeCollapsed] = useState(false);

  const elements = DEMO_ELEMENTS;
  const relationships = DEMO_RELATIONSHIPS;
  const packages = DEMO_PACKAGES;
  const diagrams = DEMO_DIAGRAMS;

  const handleSelectElement = useCallback((el) => {
    setSelectedElement(el);
    setShowProperties(true);
  }, []);

  const layers = useMemo(() => {
    const s = new Set(elements.map(e => e.layer));
    return ["All", ...Array.from(s).sort()];
  }, [elements]);

  const stats = useMemo(() => ({
    elements: elements.length,
    relationships: relationships.length,
    diagrams: diagrams.length,
    packages: packages.length,
    layers: new Set(elements.map(e => e.layer)).size,
  }), [elements, relationships, diagrams, packages]);

  return (
    <div style={{
      display: "flex", flexDirection: "column", height: "100vh",
      fontFamily: "'IBM Plex Sans', 'SF Pro Text', -apple-system, sans-serif",
      background: "#FFFFFF", color: "#333", overflow: "hidden",
    }}>
      {/* ─── TOP BAR ─── */}
      <div style={{
        display: "flex", alignItems: "center", gap: 8, padding: "6px 12px",
        background: "linear-gradient(135deg, #1a1a2e 0%, #16213e 50%, #0f3460 100%)",
        color: "#FFF", flexShrink: 0,
      }}>
        <Layers size={16} color="#5DADE2" />
        <span style={{ fontSize: 13, fontWeight: 700, letterSpacing: "0.5px" }}>EA Explorer</span>
        <span style={{ fontSize: 10, opacity: 0.5, fontWeight: 300 }}>Enterprise Architecture Model Browser</span>

        <div style={{ flex: 1 }} />

        {/* Stats badges */}
        {[
          { label: "Elements", val: stats.elements, icon: <FileBox size={10} /> },
          { label: "Relations", val: stats.relationships, icon: <Link2 size={10} /> },
          { label: "Diagrams", val: stats.diagrams, icon: <LayoutGrid size={10} /> },
        ].map(s => (
          <div key={s.label} style={{
            display: "flex", alignItems: "center", gap: 3,
            padding: "2px 8px", background: "rgba(255,255,255,0.1)",
            borderRadius: 4, fontSize: 10,
          }}>
            {s.icon} {s.val} {s.label}
          </div>
        ))}
      </div>

      {/* ─── TOOLBAR ─── */}
      <div style={{
        display: "flex", alignItems: "center", gap: 6, padding: "5px 12px",
        borderBottom: "1px solid #E5E5E5", background: "#FAFAFA", flexShrink: 0,
      }}>
        {/* View toggles */}
        {[
          { id: "diagram", icon: <GitBranch size={13} />, label: "Diagram" },
          { id: "table", icon: <Table2 size={13} />, label: "Catalog" },
        ].map(v => (
          <button key={v.id} onClick={() => setView(v.id)}
            style={{
              display: "flex", alignItems: "center", gap: 4, padding: "4px 10px",
              border: view === v.id ? "1px solid #4A90D9" : "1px solid #DDD",
              background: view === v.id ? "#E8F0FE" : "#FFF",
              color: view === v.id ? "#4A90D9" : "#666",
              borderRadius: 4, fontSize: 11, fontWeight: 500, cursor: "pointer",
            }}>
            {v.icon} {v.label}
          </button>
        ))}

        <div style={{ width: 1, height: 20, background: "#E0E0E0", margin: "0 4px" }} />

        {/* Layer filter */}
        <Filter size={12} color="#999" />
        <select value={filterLayer} onChange={e => setFilterLayer(e.target.value)}
          style={{
            padding: "3px 8px", border: "1px solid #DDD", borderRadius: 4,
            fontSize: 11, color: "#555", background: "#FFF", cursor: "pointer",
          }}>
          {layers.map(l => <option key={l} value={l}>{l === "All" ? "All Layers" : l}</option>)}
        </select>

        <div style={{ flex: 1 }} />

        {/* Search */}
        <div style={{
          display: "flex", alignItems: "center", gap: 4,
          padding: "3px 8px", border: "1px solid #DDD", borderRadius: 4,
          background: "#FFF", width: 200,
        }}>
          <Search size={12} color="#AAA" />
          <input
            type="text" placeholder="Search elements..."
            value={search} onChange={e => setSearch(e.target.value)}
            style={{
              border: "none", outline: "none", fontSize: 11, flex: 1,
              background: "transparent", color: "#333",
            }}
          />
          {search && (
            <button onClick={() => setSearch("")}
              style={{ background: "none", border: "none", cursor: "pointer", padding: 0 }}>
              <X size={11} color="#CCC" />
            </button>
          )}
        </div>
      </div>

      {/* ─── MAIN CONTENT ─── */}
      <div style={{ display: "flex", flex: 1, overflow: "hidden" }}>
        {/* Left: Project Browser */}
        {!treeCollapsed && (
          <div style={{
            width: 240, borderRight: "1px solid #E5E5E5", display: "flex",
            flexDirection: "column", flexShrink: 0, background: "#FEFEFE",
          }}>
            <div style={{
              display: "flex", alignItems: "center", justifyContent: "space-between",
              padding: "6px 10px", borderBottom: "1px solid #F0F0F0",
            }}>
              <span style={{ fontSize: 10, fontWeight: 700, color: "#888", letterSpacing: "0.5px" }}>
                PROJECT BROWSER
              </span>
              <button onClick={() => setTreeCollapsed(true)}
                style={{ background: "none", border: "none", cursor: "pointer", padding: 2 }}>
                <X size={11} color="#CCC" />
              </button>
            </div>
            <PackageTree
              packages={packages} elements={elements} diagrams={diagrams}
              onSelectPackage={(id) => setSelectedPkg(id)}
              onSelectElement={handleSelectElement}
              selectedPkg={selectedPkg}
            />
          </div>
        )}

        {treeCollapsed && (
          <button onClick={() => setTreeCollapsed(false)}
            style={{
              width: 24, background: "#F5F5F5", border: "none",
              borderRight: "1px solid #E5E5E5", cursor: "pointer",
              display: "flex", alignItems: "center", justifyContent: "center",
              writingMode: "vertical-lr",
              fontSize: 9, color: "#999", fontWeight: 600, letterSpacing: 1,
            }}>
            BROWSER ▸
          </button>
        )}

        {/* Center: View */}
        <div style={{ flex: 1, display: "flex", flexDirection: "column", overflow: "hidden" }}>
          {view === "diagram" ? (
            <DiagramView
              elements={elements} relationships={relationships}
              onSelectElement={handleSelectElement}
              selectedElement={selectedElement}
              filterLayer={filterLayer}
            />
          ) : (
            <ElementTable
              elements={elements} relationships={relationships}
              search={search} filterLayer={filterLayer}
              onSelectElement={handleSelectElement}
              selectedElement={selectedElement}
            />
          )}
        </div>

        {/* Right: Properties Panel */}
        {showProperties && (
          <div style={{
            width: 260, borderLeft: "1px solid #E5E5E5",
            display: "flex", flexDirection: "column", flexShrink: 0,
          }}>
            <PropertiesPanel
              element={selectedElement}
              relationships={relationships}
              onClose={() => { setShowProperties(false); setSelectedElement(null); }}
            />
          </div>
        )}
      </div>

      {/* ─── STATUS BAR ─── */}
      <div style={{
        display: "flex", alignItems: "center", gap: 12, padding: "3px 12px",
        borderTop: "1px solid #E5E5E5", background: "#F9F9F9", fontSize: 10, color: "#AAA",
        flexShrink: 0,
      }}>
        <span>{stats.elements} elements</span>
        <span>•</span>
        <span>{stats.relationships} relationships</span>
        <span>•</span>
        <span>{stats.diagrams} diagrams</span>
        <span>•</span>
        <span>{stats.layers} layers</span>
        {selectedElement && (
          <>
            <span style={{ flex: 1 }} />
            <span style={{ color: "#4A90D9" }}>Selected: {selectedElement.name}</span>
          </>
        )}
      </div>
    </div>
  );
}
