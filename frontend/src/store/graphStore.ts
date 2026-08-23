import { create } from 'zustand';
import type { NodeLabel, RelationshipType } from '../types/graph';

type GraphLayout = 'dagre' | 'circle' | 'concentric';

interface GraphStore {
  selectedNodeId?: string;
  selectedNodeLabel?: NodeLabel;
  focusedNodeId?: string;
  labels: NodeLabel[];
  relationships: RelationshipType[];
  tier?: number;
  severity?: string;
  environment?: string;
  layout: GraphLayout;
  setSelectedNode: (id?: string, label?: NodeLabel) => void;
  setFocusedNode: (id?: string) => void;
  toggleLabel: (label: NodeLabel) => void;
  toggleRelationship: (relationship: RelationshipType) => void;
  setTier: (tier?: number) => void;
  setSeverity: (severity?: string) => void;
  setEnvironment: (environment?: string) => void;
  setLayout: (layout: GraphLayout) => void;
  clearFilters: () => void;
}

export const useGraphStore = create<GraphStore>((set) => ({
  labels: [],
  relationships: [],
  layout: 'dagre',
  setSelectedNode: (id, label) => set({ selectedNodeId: id, selectedNodeLabel: label }),
  setFocusedNode: (id) => set({ focusedNodeId: id }),
  toggleLabel: (label) => set((state) => ({ labels: state.labels.includes(label) ? state.labels.filter((item) => item !== label) : [...state.labels, label] })),
  toggleRelationship: (relationship) => set((state) => ({ relationships: state.relationships.includes(relationship) ? state.relationships.filter((item) => item !== relationship) : [...state.relationships, relationship] })),
  setTier: (tier) => set({ tier }),
  setSeverity: (severity) => set({ severity }),
  setEnvironment: (environment) => set({ environment }),
  setLayout: (layout) => set({ layout }),
  clearFilters: () => set({ labels: [], relationships: [], tier: undefined, severity: undefined, environment: undefined, focusedNodeId: undefined })
}));
