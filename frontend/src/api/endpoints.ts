import { apiFetch, withQuery } from './client';
import type { GraphResponse, NodeDetailResponse } from '../types/graph';
import type { QueryCatalogItem, QueryExecutionRequest, QueryExecutionResponse } from '../types/api';
import type {
  AlertDefinition,
  ApplicationStatsDTO,
  ApplicationSummaryDTO,
  CatalogItem,
  DependencyChainDTO,
  FullDownstreamChainDTO,
  ImpactResponse,
  IncidentSummaryDTO,
  MetaModelResponse,
  MetricSeriesResponse,
  OperationsSummary,
  OverviewResponse,
  PathResponse,
  RunbookStep,
  SharedDatabaseEmployeeDTO
} from '../types/domain';

export const endpoints = {
  health: () => apiFetch<{ status: string }>('/health'),
  overview: () => apiFetch<OverviewResponse>('/overview'),
  metaModel: () => apiFetch<MetaModelResponse>('/meta/model'),
  catalogApplications: () => apiFetch<CatalogItem[]>('/catalog/applications'),
  catalogDatabases: () => apiFetch<CatalogItem[]>('/catalog/databases'),
  catalogEmployees: () => apiFetch<CatalogItem[]>('/catalog/employees'),
  graph: (filters: { labels?: string; relationships?: string; tier?: number; severity?: string; environment?: string }) => apiFetch<GraphResponse>(withQuery('/graph', filters)),
  nodeDetail: (label: string, nodeId: string, depth = 1) => apiFetch<NodeDetailResponse>(withQuery(`/nodes/${label}/${nodeId}`, { depth })),
  departmentApplications: (departmentName: string) => apiFetch<ApplicationStatsDTO[]>(`/departments/${departmentName}/applications`),
  employeeDependencyChain: (employeeId: string) => apiFetch<DependencyChainDTO[]>(`/employees/${employeeId}/dependency-chain`),
  highIncidents: (minIncidents = 3) => apiFetch<Record<string, unknown>[]>(withQuery('/applications/high-incidents', { minIncidents })),
  databaseImpact: (databaseId: string) => apiFetch<ImpactResponse>(`/databases/${databaseId}/impact`),
  applicationPaths: (applicationId: string, databaseId: string) => apiFetch<PathResponse>(`/applications/${applicationId}/paths/${databaseId}`),
  topApplicationsByUsers: (limit = 3) => apiFetch<ApplicationStatsDTO[]>(withQuery('/applications/top-by-users', { limit })),
  sharedDatabaseExposure: (minApps = 2) => apiFetch<SharedDatabaseEmployeeDTO[]>(withQuery('/exposure/shared-database', { minApps })),
  noIncidents: (asOf?: string | null) => apiFetch<ApplicationSummaryDTO[]>(withQuery('/applications/no-incidents', { asOf })),
  downstream: (applicationId: string) => apiFetch<FullDownstreamChainDTO[]>(`/applications/${applicationId}/downstream`),
  incidents: (filters: { applicationId?: string; severity?: string; status?: string }) => apiFetch<IncidentSummaryDTO[]>(withQuery('/incidents', filters)),
  operationsSummary: () => apiFetch<OperationsSummary>('/operations/summary'),
  operationsMetrics: (metrics?: string, window = '15m', step = '15s') => apiFetch<MetricSeriesResponse[]>(withQuery('/operations/metrics', { metrics, window, step })),
  operationsAlerts: () => apiFetch<AlertDefinition[]>('/operations/alerts'),
  operationsRunbook: () => apiFetch<RunbookStep[]>('/operations/runbook'),
  queries: () => apiFetch<QueryCatalogItem[]>('/queries'),
  query: (queryId: string) => apiFetch<QueryCatalogItem>(`/queries/${queryId}`),
  executeQuery: (queryId: string, body: QueryExecutionRequest) => apiFetch<QueryExecutionResponse>(`/queries/${queryId}/execute`, { method: 'POST', body: JSON.stringify(body) })
};
