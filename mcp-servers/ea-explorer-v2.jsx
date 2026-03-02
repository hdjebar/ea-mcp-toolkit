import { useState, useMemo, useCallback, useEffect, useRef } from "react";
import * as d3 from "d3";
import { Search, ChevronRight, ChevronDown, Package, FileBox, Layers, Link2, LayoutGrid, X, Filter, Table2, GitBranch, Info, ArrowRight, ZoomIn, ZoomOut, Maximize, Move } from "lucide-react";

/*
 * EA Explorer v2 — Sparx EA-like interface with proper layout
 *
 * Layout modes:
 *   1. EXACT: When data comes from get_diagram_layout (has x,y,width,height from EA)
 *   2. HIERARCHICAL: Sugiyama-style layered layout for generated views
 *
 * Claude: When user asks to explore a model, call MCP tools and inject data below.
 * For EXACT layout: call get_diagram_layout("diagram name") → inject into DIAGRAM_DATA
 * For catalog views: call generate_catalog tools → inject into DEMO_ELEMENTS etc.
 */

// ─── DATA (replace with MCP output) ─────────────────────────────────────

// If get_diagram_layout was called, this has exact positions. Otherwise null.
const DIAGRAM_DATA = null;
/* Example from get_diagram_layout:
const DIAGRAM_DATA = {
  name: "Application Cooperation", type: "ArchiMate",
  canvasWidth: 900, canvasHeight: 600, hasPositions: true,
  nodes: [
    { id: 10, name: "CRM System", stereotype: "ApplicationComponent", layer: "Application",
      x: 50, y: 100, width: 140, height: 60 },
    ...
  ],
  edges: [
    { id: 1, source: 10, target: 11, relationship: "Serving", label: "", waypoints: [] },
    ...
  ],
};
*/

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
  { id: 30, name: "Improve CX", type: "Goal", stereotype: "Goal", layer: "Motivation", package: "Motivation", status: "", connections: 3, onDiagrams: 1 },
  { id: 31, name: "Reduce OpCost", type: "Goal", stereotype: "Goal", layer: "Motivation", package: "Motivation", status: "", connections: 2, onDiagrams: 1 },
  { id: 32, name: "Digital First", type: "Principle", stereotype: "Principle", layer: "Motivation", package: "Motivation", status: "", connections: 4, onDiagrams: 1 },
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
  { source: "Improve CX", sourceLayer: "Motivation", relationship: "Realization", target: "Digital First", targetLayer: "Motivation" },
  { source: "Digital First", sourceLayer: "Motivation", relationship: "Realization", target: "CRM System", targetLayer: "Application" },
  { source: "Reduce OpCost", sourceLayer: "Motivation", relationship: "Influence", target: "Kubernetes Platform", targetLayer: "Technology" },
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
];

// ─── ARCHIMATE VISUAL CONSTANTS ──────────────────────────────────────────
const LAYER_THEME = {
  Motivation:     { bg: "#FFFDE7", fill: "#FFF9C4", stroke: "#F9A825", text: "#5D4037", band: "#FFF59D" },
  Strategy:       { bg: "#FFF3E0", fill: "#FFE0B2", stroke: "#EF6C00", text: "#4E342E", band: "#FFCC80" },
  Business:       { bg: "#FFFDE7", fill: "#FFF9C4", stroke: "#F9A825", text: "#33691E", band: "#FFF176" },
  Application:    { bg: "#E0F7FA", fill: "#B2EBF2", stroke: "#00838F", text: "#004D40", band: "#80DEEA" },
  Technology:     { bg: "#E8F5E9", fill: "#C8E6C9", stroke: "#2E7D32", text: "#1B5E20", band: "#A5D6A7" },
  Implementation: { bg: "#FCE4EC", fill: "#F8BBD0", stroke: "#C62828", text: "#B71C1C", band: "#F48FB1" },
};
const getTheme = (layer) => LAYER_THEME[layer] || { bg: "#F5F5F5", fill: "#E0E0E0", stroke: "#9E9E9E", text: "#333", band: "#BDBDBD" };

// ArchiMate notation: different shapes per stereotype family
const SHAPE_MAP = {
  BusinessActor: "actor", BusinessRole: "role", BusinessCollaboration: "collab",
  BusinessProcess: "round", BusinessFunction: "round", BusinessInteraction: "round",
  BusinessEvent: "event", BusinessService: "service", BusinessObject: "data",
  ApplicationComponent: "component", ApplicationService: "service",
  ApplicationFunction: "round", ApplicationInterface: "interface",
  DataObject: "data",
  Node: "node", Device: "device", SystemSoftware: "system",
  TechnologyService: "service", Artifact: "data",
  Goal: "motivation", Principle: "motivation", Requirement: "motivation",
  Driver: "motivation", Stakeholder: "actor", Constraint: "motivation",
  Capability: "round", CourseOfAction: "round", ValueStream: "round",
  WorkPackage: "round", Deliverable: "data", Gap: "motivation",
};

const CONNECTOR_STYLE = {
  Composition:    { dash: "",    width: 1.8, color: "#455A64", head: "diamond-filled" },
  Aggregation:    { dash: "",    width: 1.8, color: "#455A64", head: "diamond" },
  Assignment:     { dash: "",    width: 1.5, color: "#37474F", head: "arrow-filled" },
  Realization:    { dash: "5,3", width: 1.5, color: "#558B2F", head: "triangle" },
  Serving:        { dash: "",    width: 1.5, color: "#E65100", head: "arrow" },
  Access:         { dash: "4,3", width: 1.2, color: "#6D4C41", head: "arrow" },
  Influence:      { dash: "2,3", width: 1.2, color: "#7B1FA2", head: "arrow" },
  Association:    { dash: "",    width: 1,   color: "#9E9E9E", head: "none" },
  Triggering:     { dash: "",    width: 1.5, color: "#C62828", head: "arrow-filled" },
  Flow:           { dash: "8,3", width: 1.5, color: "#1565C0", head: "arrow-filled" },
  Specialization: { dash: "",    width: 1.5, color: "#455A64", head: "triangle" },
};

// ─── SUGIYAMA HIERARCHICAL LAYOUT ────────────────────────────────────────
// Proper layered graph layout: assign layers → order within layers → assign coordinates
function computeHierarchicalLayout(elements, relationships, filterLayer) {
  const NODE_W = 140, NODE_H = 56, PAD_X = 32, PAD_Y = 24, LAYER_GAP = 28;
  const layerOrder = ["Motivation", "Strategy", "Business", "Application", "Technology", "Implementation"];

  let els = elements;
  if (filterLayer && filterLayer !== "All") els = elements.filter(e => e.layer === filterLayer);
  const nameSet = new Set(els.map(e => e.name));
  const rels = relationships.filter(r => nameSet.has(r.source) && nameSet.has(r.target));

  // Group elements by ArchiMate layer
  const layerGroups = {};
  els.forEach(e => {
    const l = e.layer || "Other";
    if (!layerGroups[l]) layerGroups[l] = [];
    layerGroups[l].push(e);
  });

  // Sort layers in ArchiMate order
  const sortedLayers = Object.keys(layerGroups).sort(
    (a, b) => (layerOrder.indexOf(a) === -1 ? 99 : layerOrder.indexOf(a)) -
              (layerOrder.indexOf(b) === -1 ? 99 : layerOrder.indexOf(b))
  );

  // Within each layer, order by # of outbound connections (heuristic: more connected → center)
  const outDeg = {};
  rels.forEach(r => { outDeg[r.source] = (outDeg[r.source] || 0) + 1; });

  sortedLayers.forEach(layer => {
    layerGroups[layer].sort((a, b) => (outDeg[b.name] || 0) - (outDeg[a.name] || 0));
  });

  // ── Minimize crossings with barycenter heuristic ──
  // For each layer (except the first), order nodes by the average position of their
  // connected nodes in the previous layer.
  const nodePos = {}; // name → column index
  if (sortedLayers.length > 0) {
    layerGroups[sortedLayers[0]].forEach((e, i) => { nodePos[e.name] = i; });
  }
  for (let li = 1; li < sortedLayers.length; li++) {
    const layer = sortedLayers[li];
    const prevNames = new Set(sortedLayers.slice(0, li).flatMap(l => layerGroups[l].map(e => e.name)));

    layerGroups[layer].forEach(e => {
      const connected = rels
        .filter(r => (r.source === e.name && prevNames.has(r.target)) ||
                     (r.target === e.name && prevNames.has(r.source)))
        .map(r => r.source === e.name ? r.target : r.source)
        .filter(n => nodePos[n] !== undefined);

      if (connected.length > 0) {
        const bary = connected.reduce((s, n) => s + nodePos[n], 0) / connected.length;
        nodePos[e.name] = bary;
      }
    });

    // Sort by barycenter
    layerGroups[layer].sort((a, b) => (nodePos[a.name] || 0) - (nodePos[b.name] || 0));
    // Reassign integer positions
    layerGroups[layer].forEach((e, i) => { nodePos[e.name] = i; });
  }

  // ── Assign pixel coordinates ──
  const nodes = [];
  const layerBands = [];
  let currentY = PAD_Y;

  sortedLayers.forEach(layer => {
    const group = layerGroups[layer];
    const layerW = group.length * (NODE_W + PAD_X) - PAD_X;
    const startX = PAD_X;
    const bandTop = currentY - LAYER_GAP / 2;

    group.forEach((e, i) => {
      nodes.push({
        ...e,
        x: startX + i * (NODE_W + PAD_X),
        y: currentY,
        width: NODE_W,
        height: NODE_H,
      });
    });

    const bandBottom = currentY + NODE_H + LAYER_GAP / 2;
    layerBands.push({ layer, top: bandTop, height: bandBottom - bandTop, width: layerW + PAD_X * 2 });
    currentY = bandBottom + PAD_Y;
  });

  // ── Edges with node id lookup ──
  const nodeMap = {};
  nodes.forEach(n => { nodeMap[n.name] = n; });

  const edges = rels.map((r, i) => ({
    id: i,
    source: nodeMap[r.source]?.id,
    target: nodeMap[r.target]?.id,
    relationship: r.relationship,
    label: "",
  })).filter(e => e.source !== undefined && e.target !== undefined);

  const totalW = Math.max(...nodes.map(n => n.x + n.width)) + PAD_X * 2;
  const totalH = currentY + PAD_Y;

  return { nodes, edges, layerBands, canvasWidth: totalW, canvasHeight: totalH };
}

// ─── SVG ARCHIMATE SHAPES ────────────────────────────────────────────────
function ArchiMateElement({ node, isSelected, onClick }) {
  const theme = getTheme(node.layer);
  const shape = SHAPE_MAP[node.stereotype] || "round";
  const { x, y, width: w, height: h, name, stereotype } = node;

  const strokeW = isSelected ? 2.5 : 1.2;
  const stroke = isSelected ? "#1565C0" : theme.stroke;

  // Truncate name
  const maxChars = Math.floor(w / 7.5);
  const displayName = name.length > maxChars ? name.slice(0, maxChars - 1) + "…" : name;

  let shapeEl;
  switch (shape) {
    case "component":
      shapeEl = (
        <g>
          <rect x={x} y={y} width={w} height={h} rx={2} fill={theme.fill} stroke={stroke} strokeWidth={strokeW} />
          {/* Component icon: two small boxes on left edge */}
          <rect x={x - 6} y={y + 10} width={12} height={8} rx={1} fill={theme.fill} stroke={stroke} strokeWidth={0.8} />
          <rect x={x - 6} y={y + 22} width={12} height={8} rx={1} fill={theme.fill} stroke={stroke} strokeWidth={0.8} />
        </g>
      );
      break;
    case "service":
      // Rounded rectangle (more rounded than component)
      shapeEl = <rect x={x} y={y} width={w} height={h} rx={h / 2} fill={theme.fill} stroke={stroke} strokeWidth={strokeW} />;
      break;
    case "node":
      // 3D box (node)
      const d = 8;
      shapeEl = (
        <g>
          <polygon points={`${x},${y + d} ${x + d},${y} ${x + w + d},${y} ${x + w},${y + d}`} fill={theme.band} stroke={stroke} strokeWidth={strokeW * 0.6} />
          <polygon points={`${x + w},${y + d} ${x + w + d},${y} ${x + w + d},${y + h} ${x + w},${y + h + d}`} fill={theme.band} stroke={stroke} strokeWidth={strokeW * 0.6} />
          <rect x={x} y={y + d} width={w} height={h} fill={theme.fill} stroke={stroke} strokeWidth={strokeW} />
        </g>
      );
      break;
    case "device":
      // Trapezoid bottom
      shapeEl = (
        <g>
          <rect x={x} y={y} width={w} height={h - 8} rx={2} fill={theme.fill} stroke={stroke} strokeWidth={strokeW} />
          <polygon points={`${x + 10},${y + h - 8} ${x - 4},${y + h} ${x + w + 4},${y + h} ${x + w - 10},${y + h - 8}`} fill={theme.fill} stroke={stroke} strokeWidth={strokeW} />
        </g>
      );
      break;
    case "system":
      // Circle in top-right corner
      shapeEl = (
        <g>
          <rect x={x} y={y} width={w} height={h} rx={2} fill={theme.fill} stroke={stroke} strokeWidth={strokeW} />
          <circle cx={x + w - 12} cy={y + 12} r={6} fill="none" stroke={stroke} strokeWidth={0.8} />
        </g>
      );
      break;
    case "data":
      shapeEl = (
        <g>
          <rect x={x} y={y} width={w} height={h} rx={2} fill={theme.fill} stroke={stroke} strokeWidth={strokeW} />
          {/* Folded corner */}
          <polygon points={`${x + w - 12},${y} ${x + w},${y + 12} ${x + w - 12},${y + 12}`} fill={theme.band} stroke={stroke} strokeWidth={0.6} />
        </g>
      );
      break;
    case "event":
      // Notched rectangle
      shapeEl = (
        <path d={`M${x + 8},${y} L${x + w},${y} L${x + w - 8},${y + h / 2} L${x + w},${y + h} L${x + 8},${y + h} L${x},${y + h / 2} Z`}
          fill={theme.fill} stroke={stroke} strokeWidth={strokeW} />
      );
      break;
    case "motivation":
      // Rounded rect with extra rounding
      shapeEl = <rect x={x} y={y} width={w} height={h} rx={10} fill={theme.fill} stroke={stroke} strokeWidth={strokeW} />;
      break;
    case "actor":
      shapeEl = (
        <g>
          <rect x={x} y={y} width={w} height={h} rx={2} fill={theme.fill} stroke={stroke} strokeWidth={strokeW} />
          {/* Stick figure icon */}
          <circle cx={x + 14} cy={y + 12} r={5} fill="none" stroke={stroke} strokeWidth={0.8} />
          <line x1={x + 14} y1={y + 17} x2={x + 14} y2={y + 28} stroke={stroke} strokeWidth={0.8} />
          <line x1={x + 8} y1={y + 21} x2={x + 20} y2={y + 21} stroke={stroke} strokeWidth={0.8} />
        </g>
      );
      break;
    case "interface":
      shapeEl = (
        <g>
          <rect x={x} y={y} width={w} height={h} rx={2} fill={theme.fill} stroke={stroke} strokeWidth={strokeW} />
          {/* Interface icon: circle with line */}
          <circle cx={x + w - 16} cy={y + 12} r={4} fill="none" stroke={stroke} strokeWidth={0.8} />
          <line x1={x + w - 20} y1={y + 12} x2={x + w - 28} y2={y + 12} stroke={stroke} strokeWidth={0.8} />
        </g>
      );
      break;
    default:
      shapeEl = <rect x={x} y={y} width={w} height={h} rx={4} fill={theme.fill} stroke={stroke} strokeWidth={strokeW} />;
  }

  return (
    <g onClick={onClick} style={{ cursor: "pointer" }}>
      {shapeEl}
      <text x={x + w / 2} y={y + h / 2 - 5} textAnchor="middle" fontSize={11} fontWeight={600}
        fill={theme.text} fontFamily="'IBM Plex Sans', sans-serif">{displayName}</text>
      <text x={x + w / 2} y={y + h / 2 + 10} textAnchor="middle" fontSize={8.5}
        fill={theme.text} opacity={0.6} fontFamily="'IBM Plex Sans', sans-serif">«{stereotype}»</text>
    </g>
  );
}

function ArchiMateConnector({ edge, nodeMap }) {
  const src = nodeMap[edge.source];
  const tgt = nodeMap[edge.target];
  if (!src || !tgt) return null;

  const style = CONNECTOR_STYLE[edge.relationship] || CONNECTOR_STYLE.Association;

  // Calculate connection points (center of nearest edges)
  let sx = src.x + src.width / 2, sy = src.y + src.height / 2;
  let tx = tgt.x + tgt.width / 2, ty = tgt.y + tgt.height / 2;

  // Snap to nearest edge
  const dx = tx - sx, dy = ty - sy;
  if (Math.abs(dx) > Math.abs(dy)) {
    sx = dx > 0 ? src.x + src.width : src.x;
    tx = dx > 0 ? tgt.x : tgt.x + tgt.width;
  } else {
    sy = dy > 0 ? src.y + src.height : src.y;
    ty = dy > 0 ? tgt.y : tgt.y + tgt.height;
  }

  // Use waypoints if available
  let pathD;
  if (edge.waypoints && edge.waypoints.length > 0) {
    const pts = [{ x: sx, y: sy }, ...edge.waypoints, { x: tx, y: ty }];
    pathD = `M${pts[0].x},${pts[0].y}` + pts.slice(1).map(p => `L${p.x},${p.y}`).join("");
  } else {
    // Orthogonal routing: add bend points
    if (Math.abs(sy - ty) > 15 && Math.abs(sx - tx) > 15) {
      const midY = (sy + ty) / 2;
      pathD = `M${sx},${sy} L${sx},${midY} L${tx},${midY} L${tx},${ty}`;
    } else {
      pathD = `M${sx},${sy} L${tx},${ty}`;
    }
  }

  const markerId = `marker-${edge.id}-${edge.relationship}`;

  return (
    <g>
      <defs>
        {style.head !== "none" && (
          <marker id={markerId} viewBox="0 -5 10 10" refX="9" refY="0"
            markerWidth={7} markerHeight={7} orient="auto">
            {style.head === "arrow" && <path d="M0,-4L10,0L0,4" fill="none" stroke={style.color} strokeWidth={1.2} />}
            {style.head === "arrow-filled" && <path d="M0,-4L10,0L0,4Z" fill={style.color} />}
            {style.head === "triangle" && <path d="M0,-5L10,0L0,5Z" fill="none" stroke={style.color} strokeWidth={1} />}
            {style.head === "diamond" && <path d="M0,0L5,-4L10,0L5,4Z" fill="none" stroke={style.color} strokeWidth={1} />}
            {style.head === "diamond-filled" && <path d="M0,0L5,-4L10,0L5,4Z" fill={style.color} />}
          </marker>
        )}
      </defs>
      <path d={pathD} fill="none" stroke={style.color}
        strokeWidth={style.width} strokeDasharray={style.dash}
        markerEnd={style.head !== "none" ? `url(#${markerId})` : undefined} />
      {edge.label && (
        <text x={(sx + tx) / 2} y={(sy + ty) / 2 - 6} textAnchor="middle"
          fontSize={8} fill="#777" fontFamily="'IBM Plex Sans', sans-serif">
          {edge.relationship}
        </text>
      )}
    </g>
  );
}

// ─── DIAGRAM CANVAS (SVG with zoom/pan) ──────────────────────────────────
function DiagramCanvas({ elements, relationships, filterLayer, selectedElement, onSelectElement }) {
  const containerRef = useRef(null);
  const svgRef = useRef(null);
  const [dimensions, setDimensions] = useState({ width: 800, height: 500 });
  const [transform, setTransform] = useState({ x: 20, y: 20, k: 1 });

  useEffect(() => {
    if (!containerRef.current) return;
    const ro = new ResizeObserver(entries => {
      const { width, height } = entries[0].contentRect;
      setDimensions({ width, height });
    });
    ro.observe(containerRef.current);
    return () => ro.disconnect();
  }, []);

  const layout = useMemo(() => {
    if (DIAGRAM_DATA && DIAGRAM_DATA.hasPositions) {
      return {
        nodes: DIAGRAM_DATA.nodes,
        edges: DIAGRAM_DATA.edges,
        layerBands: [],
        canvasWidth: DIAGRAM_DATA.canvasWidth,
        canvasHeight: DIAGRAM_DATA.canvasHeight,
      };
    }
    return computeHierarchicalLayout(elements, relationships, filterLayer);
  }, [elements, relationships, filterLayer]);

  const nodeMap = useMemo(() => {
    const m = {};
    layout.nodes.forEach(n => { m[n.id] = n; });
    return m;
  }, [layout]);

  // D3 zoom behavior
  useEffect(() => {
    if (!svgRef.current) return;
    const svg = d3.select(svgRef.current);
    const zoom = d3.zoom()
      .scaleExtent([0.2, 3])
      .on("zoom", (event) => {
        setTransform({ x: event.transform.x, y: event.transform.y, k: event.transform.k });
      });
    svg.call(zoom);

    // Fit content
    const cw = layout.canvasWidth, ch = layout.canvasHeight;
    const scale = Math.min(dimensions.width / (cw + 40), dimensions.height / (ch + 40), 1.2);
    const tx = (dimensions.width - cw * scale) / 2;
    const ty = 20;
    svg.call(zoom.transform, d3.zoomIdentity.translate(tx, ty).scale(scale));

    return () => svg.on(".zoom", null);
  }, [layout, dimensions]);

  return (
    <div ref={containerRef} style={{ flex: 1, position: "relative", overflow: "hidden", background: "#FAFBFC" }}>
      {/* Zoom controls */}
      <div style={{
        position: "absolute", top: 8, right: 8, zIndex: 10,
        display: "flex", flexDirection: "column", gap: 2,
        background: "#FFF", border: "1px solid #E0E0E0", borderRadius: 6, padding: 2,
        boxShadow: "0 1px 4px rgba(0,0,0,0.08)",
      }}>
        {[
          { icon: <ZoomIn size={14} />, action: () => d3.select(svgRef.current).transition().call(d3.zoom().scaleBy, 1.3) },
          { icon: <ZoomOut size={14} />, action: () => d3.select(svgRef.current).transition().call(d3.zoom().scaleBy, 0.7) },
          { icon: <Maximize size={14} />, action: () => {
            const scale = Math.min(dimensions.width / (layout.canvasWidth + 40), dimensions.height / (layout.canvasHeight + 40), 1.2);
            d3.select(svgRef.current).transition().call(
              d3.zoom().transform,
              d3.zoomIdentity.translate((dimensions.width - layout.canvasWidth * scale) / 2, 20).scale(scale)
            );
          }},
        ].map((btn, i) => (
          <button key={i} onClick={btn.action} style={{
            background: "none", border: "none", cursor: "pointer", padding: 4,
            color: "#666", borderRadius: 4,
          }}
          onMouseEnter={e => e.currentTarget.style.background = "#F0F0F0"}
          onMouseLeave={e => e.currentTarget.style.background = "none"}
          >{btn.icon}</button>
        ))}
      </div>

      {/* Layout mode indicator */}
      <div style={{
        position: "absolute", bottom: 8, left: 8, zIndex: 10,
        fontSize: 9, padding: "2px 8px", background: "#FFF",
        border: "1px solid #E0E0E0", borderRadius: 4, color: "#999",
      }}>
        {DIAGRAM_DATA?.hasPositions ? "📐 EA Exact Layout" : "📊 Hierarchical Layout"} •
        {layout.nodes.length} elements • {Math.round(transform.k * 100)}%
      </div>

      <svg ref={svgRef} width={dimensions.width} height={dimensions.height}>
        <g transform={`translate(${transform.x},${transform.y}) scale(${transform.k})`}>
          {/* Layer band backgrounds */}
          {layout.layerBands.map((band, i) => {
            const theme = getTheme(band.layer);
            return (
              <g key={`band-${i}`}>
                <rect x={0} y={band.top} width={band.width + 60} height={band.height}
                  fill={theme.bg} opacity={0.4} rx={6} />
                <text x={8} y={band.top + 14} fontSize={10} fontWeight={700}
                  fill={theme.text} opacity={0.5} fontFamily="'IBM Plex Sans', sans-serif">
                  {band.layer}
                </text>
              </g>
            );
          })}

          {/* Connectors (behind elements) */}
          {layout.edges.map((edge, i) => (
            <ArchiMateConnector key={`e-${i}`} edge={edge} nodeMap={nodeMap} />
          ))}

          {/* Elements */}
          {layout.nodes.map(node => (
            <ArchiMateElement key={node.id} node={node}
              isSelected={selectedElement?.id === node.id}
              onClick={() => onSelectElement(node)} />
          ))}
        </g>
      </svg>
    </div>
  );
}

// ─── PROPERTIES PANEL ────────────────────────────────────────────────────
function PropertiesPanel({ element, relationships, onClose }) {
  const [tab, setTab] = useState("general");
  if (!element) return (
    <div style={{ display: "flex", alignItems: "center", justifyContent: "center",
      height: "100%", color: "#AAA", fontSize: 12, padding: 20, textAlign: "center" }}>
      <div><Info size={28} color="#DDD" style={{ margin: "0 auto 8px" }} /><div>Select an element</div></div>
    </div>
  );

  const outbound = relationships.filter(r => r.source === element.name);
  const inbound = relationships.filter(r => r.target === element.name);
  const theme = getTheme(element.layer);

  return (
    <div style={{ display: "flex", flexDirection: "column", height: "100%", fontSize: 11 }}>
      <div style={{ padding: "8px 10px", background: theme.bg, borderBottom: `2px solid ${theme.stroke}` }}>
        <div style={{ display: "flex", justifyContent: "space-between" }}>
          <div>
            <div style={{ fontSize: 13, fontWeight: 700, color: theme.text }}>{element.name}</div>
            <div style={{ fontSize: 9, color: theme.text, opacity: 0.65, marginTop: 1 }}>«{element.stereotype}»</div>
          </div>
          <button onClick={onClose} style={{ background: "none", border: "none", cursor: "pointer" }}>
            <X size={13} color="#999" />
          </button>
        </div>
      </div>
      <div style={{ display: "flex", borderBottom: "1px solid #E5E5E5" }}>
        {["general", "connections"].map(t => (
          <button key={t} onClick={() => setTab(t)} style={{
            flex: 1, padding: "5px", fontSize: 10, fontWeight: 600,
            background: tab === t ? "#FFF" : "#F9F9F9",
            border: "none", borderBottom: tab === t ? "2px solid #1565C0" : "2px solid transparent",
            color: tab === t ? "#1565C0" : "#999", cursor: "pointer",
          }}>{t === "general" ? "General" : `Connections (${outbound.length + inbound.length})`}</button>
        ))}
      </div>
      <div style={{ flex: 1, overflowY: "auto", padding: 8 }}>
        {tab === "general" && (
          <div style={{ display: "flex", flexDirection: "column", gap: 6 }}>
            {[["Type", element.type], ["Stereotype", element.stereotype], ["Layer", element.layer],
              ["Package", element.package], ["Status", element.status || "—"],
              ["Connections", element.connections], ["Diagrams", element.onDiagrams],
            ].map(([k, v]) => (
              <div key={k} style={{ display: "flex", justifyContent: "space-between" }}>
                <span style={{ color: "#888" }}>{k}</span><span style={{ color: "#333" }}>{v}</span>
              </div>
            ))}
          </div>
        )}
        {tab === "connections" && (
          <div>
            {outbound.length > 0 && <>
              <div style={{ fontSize: 9, fontWeight: 700, color: "#666", marginBottom: 3 }}>OUTBOUND</div>
              {outbound.map((r, i) => (
                <div key={i} style={{ padding: "3px 0", borderBottom: "1px solid #F0F0F0", display: "flex", alignItems: "center", gap: 3, flexWrap: "wrap" }}>
                  <span style={{ fontSize: 9, padding: "0 4px", borderRadius: 2, background: `${(CONNECTOR_STYLE[r.relationship] || CONNECTOR_STYLE.Association).color}15`,
                    color: (CONNECTOR_STYLE[r.relationship] || CONNECTOR_STYLE.Association).color, fontWeight: 500 }}>{r.relationship}</span>
                  <ArrowRight size={9} color="#CCC" />
                  <span style={{ fontWeight: 500 }}>{r.target}</span>
                </div>
              ))}
            </>}
            {inbound.length > 0 && <>
              <div style={{ fontSize: 9, fontWeight: 700, color: "#666", margin: "6px 0 3px" }}>INBOUND</div>
              {inbound.map((r, i) => (
                <div key={i} style={{ padding: "3px 0", borderBottom: "1px solid #F0F0F0", display: "flex", alignItems: "center", gap: 3, flexWrap: "wrap" }}>
                  <span style={{ fontWeight: 500 }}>{r.source}</span>
                  <span style={{ fontSize: 9, padding: "0 4px", borderRadius: 2, background: `${(CONNECTOR_STYLE[r.relationship] || CONNECTOR_STYLE.Association).color}15`,
                    color: (CONNECTOR_STYLE[r.relationship] || CONNECTOR_STYLE.Association).color, fontWeight: 500 }}>{r.relationship}</span>
                </div>
              ))}
            </>}
          </div>
        )}
      </div>
    </div>
  );
}

// ─── CATALOG TABLE ───────────────────────────────────────────────────────
function CatalogTable({ elements, search, filterLayer, onSelectElement, selectedElement }) {
  const [sortKey, setSortKey] = useState("name");
  const [sortAsc, setSortAsc] = useState(true);
  const data = useMemo(() => {
    let f = elements;
    if (search) { const q = search.toLowerCase(); f = f.filter(e => e.name.toLowerCase().includes(q) || e.stereotype.toLowerCase().includes(q)); }
    if (filterLayer && filterLayer !== "All") f = f.filter(e => e.layer === filterLayer);
    return [...f].sort((a, b) => { const av = a[sortKey], bv = b[sortKey]; const c = typeof av === "number" ? av - bv : String(av).localeCompare(String(bv)); return sortAsc ? c : -c; });
  }, [elements, search, filterLayer, sortKey, sortAsc]);

  const handleSort = (k) => { if (sortKey === k) setSortAsc(!sortAsc); else { setSortKey(k); setSortAsc(true); } };
  const cols = [{ k: "name", l: "Name", f: 2 }, { k: "stereotype", l: "Stereotype", f: 1.4 }, { k: "layer", l: "Layer", f: 0.8 }, { k: "package", l: "Package", f: 1.2 }, { k: "connections", l: "Conn", f: 0.4 }];

  return (
    <div style={{ display: "flex", flexDirection: "column", height: "100%", fontSize: 11 }}>
      <div style={{ display: "flex", background: "#F5F5F5", borderBottom: "1px solid #E0E0E0" }}>
        {cols.map(c => (
          <div key={c.k} onClick={() => handleSort(c.k)} style={{
            flex: c.f, padding: "5px 6px", fontSize: 10, fontWeight: 700,
            color: sortKey === c.k ? "#1565C0" : "#888", cursor: "pointer" }}>
            {c.l} {sortKey === c.k && (sortAsc ? "↑" : "↓")}
          </div>
        ))}
      </div>
      <div style={{ flex: 1, overflowY: "auto" }}>
        {data.map(el => {
          const theme = getTheme(el.layer);
          return (
            <div key={el.id} onClick={() => onSelectElement(el)} style={{
              display: "flex", borderBottom: "1px solid #F0F0F0", cursor: "pointer",
              background: selectedElement?.id === el.id ? "#E3F2FD" : "transparent",
              borderLeft: `3px solid ${selectedElement?.id === el.id ? "#1565C0" : "transparent"}`,
            }}
            onMouseEnter={e => { if (selectedElement?.id !== el.id) e.currentTarget.style.background = "#FAFAFA"; }}
            onMouseLeave={e => { if (selectedElement?.id !== el.id) e.currentTarget.style.background = "transparent"; }}>
              <div style={{ flex: 2, padding: "4px 6px", fontWeight: 500 }}>{el.name}</div>
              <div style={{ flex: 1.4, padding: "4px 6px", color: "#777" }}>«{el.stereotype}»</div>
              <div style={{ flex: 0.8, padding: "4px 6px" }}>
                <span style={{ fontSize: 9, padding: "0 5px", borderRadius: 3, background: theme.fill, color: theme.text, border: `1px solid ${theme.stroke}`, fontWeight: 600 }}>{el.layer}</span>
              </div>
              <div style={{ flex: 1.2, padding: "4px 6px", color: "#999" }}>{el.package}</div>
              <div style={{ flex: 0.4, padding: "4px 6px", color: "#AAA", textAlign: "center" }}>{el.connections}</div>
            </div>
          );
        })}
      </div>
      <div style={{ padding: "3px 8px", fontSize: 9, color: "#BBB", background: "#FAFAFA", borderTop: "1px solid #E5E5E5" }}>
        {data.length} of {elements.length} elements
      </div>
    </div>
  );
}

// ─── PACKAGE TREE ────────────────────────────────────────────────────────
function PackageTree({ packages, elements, diagrams, onSelectElement }) {
  const [expanded, setExpanded] = useState(new Set([100]));
  const tree = useMemo(() => {
    const m = {}; packages.forEach(p => m[p.id] = { ...p, children: [] });
    const r = []; packages.forEach(p => { if (p.parentId && m[p.parentId]) m[p.parentId].children.push(m[p.id]); else r.push(m[p.id]); });
    return r;
  }, [packages]);

  const toggle = (id) => setExpanded(p => { const n = new Set(p); n.has(id) ? n.delete(id) : n.add(id); return n; });

  const renderNode = (node, depth = 0) => {
    const isExp = expanded.has(node.id);
    const pkgEls = elements.filter(e => e.package === node.name);
    const pkgDiags = diagrams.filter(d => d.package === node.name);
    return (
      <div key={node.id}>
        <div onClick={() => toggle(node.id)} style={{
          display: "flex", alignItems: "center", gap: 3, padding: "3px 4px",
          paddingLeft: 6 + depth * 14, cursor: "pointer", fontSize: 11,
        }}
        onMouseEnter={e => e.currentTarget.style.background = "#F5F5F5"}
        onMouseLeave={e => e.currentTarget.style.background = "transparent"}>
          {node.children.length > 0 ? (isExp ? <ChevronDown size={11} color="#888" /> : <ChevronRight size={11} color="#888" />) : <span style={{ width: 11 }} />}
          <Package size={12} color="#E65100" />
          <span style={{ flex: 1, fontWeight: node.children.length ? 600 : 400, color: "#333" }}>{node.name}</span>
          <span style={{ fontSize: 9, color: "#BBB" }}>{node.elements}</span>
        </div>
        {isExp && <>
          {node.children.map(c => renderNode(c, depth + 1))}
          {pkgDiags.map(d => (
            <div key={`d-${d.id}`} style={{ display: "flex", alignItems: "center", gap: 3, padding: "2px 4px", paddingLeft: 20 + depth * 14, fontSize: 10, color: "#777" }}>
              <LayoutGrid size={10} color="#00838F" />{d.name}
            </div>
          ))}
          {pkgEls.map(el => (
            <div key={`e-${el.id}`} onClick={() => onSelectElement(el)} style={{
              display: "flex", alignItems: "center", gap: 3, padding: "2px 4px",
              paddingLeft: 20 + depth * 14, fontSize: 10, color: "#666", cursor: "pointer",
            }}
            onMouseEnter={e => e.currentTarget.style.background = "#F0F0F0"}
            onMouseLeave={e => e.currentTarget.style.background = "transparent"}>
              <FileBox size={10} color={getTheme(el.layer).stroke} />{el.name}
            </div>
          ))}
        </>}
      </div>
    );
  };
  return <div style={{ overflowY: "auto", flex: 1 }}>{tree.map(n => renderNode(n))}</div>;
}

// ─── MAIN ────────────────────────────────────────────────────────────────
export default function EAExplorerV2() {
  const [view, setView] = useState("diagram");
  const [selectedElement, setSelectedElement] = useState(null);
  const [search, setSearch] = useState("");
  const [filterLayer, setFilterLayer] = useState("All");
  const [showProps, setShowProps] = useState(false);
  const [treeOpen, setTreeOpen] = useState(true);

  const handleSelect = useCallback((el) => { setSelectedElement(el); setShowProps(true); }, []);
  const layers = useMemo(() => ["All", ...new Set(DEMO_ELEMENTS.map(e => e.layer))], []);

  return (
    <div style={{ display: "flex", flexDirection: "column", height: "100vh",
      fontFamily: "'IBM Plex Sans', -apple-system, sans-serif", background: "#FFF", overflow: "hidden" }}>

      {/* Top bar */}
      <div style={{ display: "flex", alignItems: "center", gap: 8, padding: "5px 12px",
        background: "linear-gradient(135deg, #0D1B2A 0%, #1B2838 50%, #1a365d 100%)", flexShrink: 0 }}>
        <Layers size={15} color="#5DADE2" />
        <span style={{ fontSize: 13, fontWeight: 700, color: "#FFF", letterSpacing: 0.3 }}>EA Explorer</span>
        <span style={{ fontSize: 9, color: "#78909C" }}>ArchiMate Model Browser</span>
        <div style={{ flex: 1 }} />
        <span style={{ fontSize: 9, color: "#546E7A", padding: "1px 6px", background: "rgba(255,255,255,0.08)", borderRadius: 3 }}>
          {DEMO_ELEMENTS.length} elements • {DEMO_RELATIONSHIPS.length} relationships
        </span>
      </div>

      {/* Toolbar */}
      <div style={{ display: "flex", alignItems: "center", gap: 5, padding: "4px 10px",
        borderBottom: "1px solid #E5E5E5", background: "#FAFAFA", flexShrink: 0 }}>
        {[{ id: "diagram", icon: <GitBranch size={12} />, label: "Diagram" },
          { id: "table", icon: <Table2 size={12} />, label: "Catalog" }].map(v => (
          <button key={v.id} onClick={() => setView(v.id)} style={{
            display: "flex", alignItems: "center", gap: 3, padding: "3px 8px",
            border: view === v.id ? "1px solid #1565C0" : "1px solid #DDD",
            background: view === v.id ? "#E3F2FD" : "#FFF",
            color: view === v.id ? "#1565C0" : "#777",
            borderRadius: 4, fontSize: 10, fontWeight: 500, cursor: "pointer",
          }}>{v.icon} {v.label}</button>
        ))}
        <div style={{ width: 1, height: 18, background: "#E0E0E0" }} />
        <Filter size={11} color="#999" />
        <select value={filterLayer} onChange={e => setFilterLayer(e.target.value)} style={{
          padding: "2px 6px", border: "1px solid #DDD", borderRadius: 3, fontSize: 10, color: "#555", background: "#FFF" }}>
          {layers.map(l => <option key={l}>{l === "All" ? "All Layers" : l}</option>)}
        </select>
        <div style={{ flex: 1 }} />
        <div style={{ display: "flex", alignItems: "center", gap: 3, padding: "2px 6px",
          border: "1px solid #DDD", borderRadius: 4, background: "#FFF", width: 180 }}>
          <Search size={11} color="#BBB" />
          <input type="text" placeholder="Search..." value={search} onChange={e => setSearch(e.target.value)}
            style={{ border: "none", outline: "none", fontSize: 10, flex: 1, background: "transparent" }} />
          {search && <button onClick={() => setSearch("")} style={{ background: "none", border: "none", cursor: "pointer", padding: 0 }}><X size={10} color="#CCC" /></button>}
        </div>
      </div>

      {/* Content */}
      <div style={{ display: "flex", flex: 1, overflow: "hidden" }}>
        {/* Tree */}
        {treeOpen ? (
          <div style={{ width: 220, borderRight: "1px solid #E5E5E5", display: "flex", flexDirection: "column", flexShrink: 0 }}>
            <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", padding: "4px 8px", borderBottom: "1px solid #F0F0F0" }}>
              <span style={{ fontSize: 9, fontWeight: 700, color: "#999", letterSpacing: 0.5 }}>PROJECT BROWSER</span>
              <button onClick={() => setTreeOpen(false)} style={{ background: "none", border: "none", cursor: "pointer" }}><X size={10} color="#CCC" /></button>
            </div>
            <PackageTree packages={DEMO_PACKAGES} elements={DEMO_ELEMENTS} diagrams={DEMO_DIAGRAMS} onSelectElement={handleSelect} />
          </div>
        ) : (
          <button onClick={() => setTreeOpen(true)} style={{
            width: 20, background: "#F9F9F9", border: "none", borderRight: "1px solid #E5E5E5",
            cursor: "pointer", writingMode: "vertical-lr", fontSize: 8, color: "#AAA", fontWeight: 600 }}>
            BROWSER ▸
          </button>
        )}

        {/* Main view */}
        <div style={{ flex: 1, display: "flex", flexDirection: "column", overflow: "hidden" }}>
          {view === "diagram" ? (
            <DiagramCanvas elements={DEMO_ELEMENTS} relationships={DEMO_RELATIONSHIPS}
              filterLayer={filterLayer} selectedElement={selectedElement} onSelectElement={handleSelect} />
          ) : (
            <CatalogTable elements={DEMO_ELEMENTS} search={search} filterLayer={filterLayer}
              onSelectElement={handleSelect} selectedElement={selectedElement} />
          )}
        </div>

        {/* Properties */}
        {showProps && (
          <div style={{ width: 240, borderLeft: "1px solid #E5E5E5", flexShrink: 0 }}>
            <PropertiesPanel element={selectedElement} relationships={DEMO_RELATIONSHIPS}
              onClose={() => { setShowProps(false); setSelectedElement(null); }} />
          </div>
        )}
      </div>

      {/* Status bar */}
      <div style={{ display: "flex", alignItems: "center", gap: 10, padding: "2px 10px",
        borderTop: "1px solid #E5E5E5", background: "#F9F9F9", fontSize: 9, color: "#BBB", flexShrink: 0 }}>
        <span>{DEMO_ELEMENTS.length} elements</span><span>•</span>
        <span>{DEMO_RELATIONSHIPS.length} relationships</span>
        {selectedElement && <><span style={{ flex: 1 }} /><span style={{ color: "#1565C0" }}>▸ {selectedElement.name}</span></>}
      </div>
    </div>
  );
}
