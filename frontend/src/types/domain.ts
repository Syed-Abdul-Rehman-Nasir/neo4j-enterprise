import type { GraphResponse } from './graph';

export type HealthStatus = 'healthy' | 'warning' | 'critical' | 'unknown';

export interface ScaleTarget {
  components: number;
  relationships: number;
  liveBlastRadiusP90Ms: number;
  precomputedTierMsMin: number;
  precomputedTierMsMax: number;
}

export interface OverviewScenario {
  databaseId: string;
  databaseName: string;
  serviceCount: number;
  applicationId: string;
  applicationName: string;
  employeeCount: number;
  employeeNames: string[];
}

export interface OverviewResponse {
  nodeCount: number;
  relationshipCount: number;
  applicationCount: number;
  incidentCount: number;
  activeIncidentCount: number;
  highRiskApplication?: Record<string, unknown> | null;
  db001Scenario: OverviewScenario;
  scaleTarget: ScaleTarget;
  seedLoaded: boolean;
}

export interface CatalogItem { id: string; name: string; extra: Record<string, unknown>; }
export interface LabelDefinition { label: string; count: number; properties: string[]; description: string; }
export interface RelationshipDefinition { type: string; count: number; demoEdges: number; scaleOnly: boolean; description: string; }
export interface MetaModelResponse { labels: LabelDefinition[]; relationships: RelationshipDefinition[]; notes: string[]; }

export interface ApplicationStatsDTO { name: string; applicationId: string; tier: number; uniqueUsers: number; incidentCount: number; }
export interface ApplicationSummaryDTO { application: string; id: string; owner: string; tier: number; }
export interface DependencyChainDTO { employee: string; application: string; applicationId: string; service: string; serviceType: string; database: string; dbEngine: string; criticality: number; }
export interface ImpactedEmployeeDTO { name: string; email: string; role: string; department: string; viaApplication: string; viaService: string; }
export interface IncidentSummaryDTO { incidentId: string; title: string; severity: string; status: string; applicationName: string; mttrMinutes?: number | null; }
export interface FullDownstreamChainDTO { application: string; appVersion: string; service: string; svcType: string; svcSlaMs: number; database: string; dbEngine: string; dbSizeGb: number; server: string; serverRegion: string; serverOs: string; criticality: number; }
export interface SharedDatabaseEmployeeDTO { employee: string; sharedDatabase: string; applications: string[]; appCount: number; }
export interface ImpactResponse { databaseId: string; employees: ImpactedEmployeeDTO[]; summary: { uniqueEmployees: number; applications: string[]; services: string[]; departments: string[]; pathRowCount: number; }; graph?: GraphResponse | Record<string, unknown> | null; }
export interface PathSegment { nodes: string[]; nodeNames: string[]; hopCount: number; edges: Record<string, unknown>[]; }
export interface PathResponse { applicationId: string; databaseId: string; paths: PathSegment[]; }

export interface MetricPoint { timestamp: number; value?: number | null; }
export interface MetricSeriesResponse { metric: string; unit: string; status: HealthStatus; thresholds: Record<string, number>; points: MetricPoint[]; source: string; detail?: string | null; }
export interface ClusterMember { role: string; address: string; status: string; }
export interface OperationsSummary { mode: 'standalone' | 'cluster' | 'unknown'; label: string; productionTargetLabel: string; members: ClusterMember[]; databaseStatus: string; constraintCount: number; indexOnlineCount: number; replicationLagMs?: number | null; health: HealthStatus; }
export interface AlertDefinition { name: string; severity: string; query: string; message: string; thresholds: Record<string, number>; evaluatedStatus: HealthStatus; tags: string[]; }
export interface RunbookStep { id: string; title: string; summary: string; commands: string[]; thresholds: string[]; }
