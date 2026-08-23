export type NodeLabel = 'Employee' | 'Department' | 'Application' | 'Service' | 'Database' | 'Server' | 'Incident';
export type RelationshipType = 'BELONGS_TO' | 'USES' | 'DEPENDS_ON' | 'READS_FROM' | 'HOSTED_ON' | 'AFFECTS' | 'EXTENDS';

export interface GraphNode {
  id: string;
  label: NodeLabel;
  displayName: string;
  properties: Record<string, unknown>;
  incidentCount?: number | null;
}

export interface GraphEdge {
  id: string;
  type: RelationshipType;
  source: string;
  target: string;
  properties: Record<string, unknown>;
}

export interface GraphResponse {
  nodes: GraphNode[];
  edges: GraphEdge[];
  countsByLabel: Record<string, number>;
  countsByRelationship: Record<string, number>;
  generatedAt: string;
}

export interface NodeDetailResponse {
  node: GraphNode;
  neighborhood: GraphResponse;
}
