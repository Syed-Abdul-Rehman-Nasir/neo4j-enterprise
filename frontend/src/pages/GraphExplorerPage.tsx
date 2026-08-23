import { useEffect, useMemo, useRef } from 'react';
import { useQuery } from '@tanstack/react-query';
import cytoscape from 'cytoscape';
import dagre from 'cytoscape-dagre';
import { endpoints } from '../api/endpoints';
import { queryKeys } from '../api/queryKeys';
import { Badge, Button, EmptyState, Spinner } from '../components/foundation';
import { PageContainer, SplitPane } from '../components/layout';
import { useGraphStore } from '../store/graphStore';
import type { GraphNode, NodeLabel } from '../types/graph';
import common from './PageCommon.module.css';
import styles from './GraphExplorerPage.module.css';

cytoscape.use(dagre);
const labels: NodeLabel[] = ['Employee', 'Department', 'Application', 'Service', 'Database', 'Server', 'Incident'];
const colorFor = (label: string) => `var(--node-${label.replace(/[A-Z]/g, (m, i) => `${i ? '-' : ''}${m.toLowerCase()}`)})`;

export function GraphExplorerPage() {
  const containerRef = useRef<HTMLDivElement | null>(null);
  const { labels: activeLabels, relationships, layout, selectedNodeId, selectedNodeLabel, toggleLabel, clearFilters, setSelectedNode, setLayout } = useGraphStore();
  const filters = useMemo(() => ({ labels: activeLabels.join(',') || undefined, relationships: relationships.join(',') || undefined }), [activeLabels, relationships]);
  const { data, isLoading, isError } = useQuery({ queryKey: queryKeys.graph(filters), queryFn: () => endpoints.graph(filters) });
  const selectedNode = data?.nodes.find((node) => node.id === selectedNodeId);

  useEffect(() => {
    if (!containerRef.current || !data) return;
    const cy = cytoscape({
      container: containerRef.current,
      elements: [
        ...data.nodes.map((node) => ({ data: { id: node.id, label: node.label, name: node.displayName } })),
        ...data.edges.map((edge) => ({ data: { id: edge.id, source: edge.source, target: edge.target, type: edge.type } }))
      ],
      style: [
        { selector: 'node', style: { label: 'data(name)', 'background-color': (ele) => colorFor(ele.data('label')), color: '#fcf8ef', 'font-size': 10, 'text-outline-color': '#151411', 'text-outline-width': 2 } },
        { selector: 'edge', style: { width: 1.8, 'line-color': '#8c806e', 'target-arrow-color': '#8c806e', 'target-arrow-shape': 'triangle', 'curve-style': 'bezier', label: 'data(type)', 'font-size': 7, color: '#cfc3ad' } },
        { selector: 'node:selected', style: { 'border-width': 4, 'border-color': '#c8f23a' } }
      ],
      layout: { name: layout === 'dagre' ? 'dagre' : layout, animate: false, fit: true, padding: 40 } as cytoscape.LayoutOptions
    });
    cy.on('tap', 'node', (event) => { const node = event.target; setSelectedNode(node.id(), node.data('label')); });
    return () => cy.destroy();
  }, [data, layout, setSelectedNode]);

  return <PageContainer eyebrow="Graph explorer" title="Topology Signal Room" description="Explore employees, apps, services, databases, servers, and incidents as an operational graph.">
    <SplitPane main={<div className={common.stack}><div className={common.card}><div className={styles.controls}><div className={styles.chips}>{labels.map((label) => <button key={label} className={`${styles.chip} ${activeLabels.includes(label) ? styles.chipActive : ''}`} onClick={() => toggleLabel(label)}>{label}</button>)}</div><div className={styles.chips}>{(['dagre', 'circle', 'concentric'] as const).map((item) => <Button key={item} size="small" variant={layout === item ? 'primary' : 'ghost'} onClick={() => setLayout(item)}>{item}</Button>)}<Button size="small" variant="ghost" onClick={clearFilters}>Clear filters</Button></div></div></div>{isLoading && <Spinner label="Loading graph" />}{isError && <EmptyState title="Graph API unavailable" description="Start the backend and reload the topology." />}<div ref={containerRef} className={styles.graph} aria-label="Cytoscape topology graph" /></div>} side={<div className={`${common.stack} ${styles.drawer}`}><article className={common.card}><span className={common.label}>Legend</span><ul className={common.list}>{labels.map((label) => <li key={label}><span className={styles.legendDot} style={{ background: colorFor(label) }} />{label} <Badge tone="neutral">{data?.countsByLabel[label] ?? 0}</Badge></li>)}</ul></article><article className={common.card}><span className={common.label}>Inspector</span>{selectedNode ? <NodeInspector node={selectedNode} label={selectedNodeLabel} /> : <p>Select a node to inspect properties and neighborhood hints.</p>}</article></div>} />
  </PageContainer>;
}
function NodeInspector({ node }: { node: GraphNode; label?: NodeLabel }) { return <div><h2>{node.displayName}</h2><Badge>{node.label}</Badge><p>ID: {node.id}</p><pre className={`${common.code} ${styles.props}`}>{JSON.stringify(node.properties, null, 2)}</pre></div>; }
