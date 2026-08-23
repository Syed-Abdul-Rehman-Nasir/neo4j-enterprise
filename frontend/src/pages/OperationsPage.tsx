import { useQuery } from '@tanstack/react-query';
import { Line, LineChart, ResponsiveContainer, Tooltip as ChartTooltip, XAxis, YAxis } from 'recharts';
import { endpoints } from '../api/endpoints';
import { queryKeys } from '../api/queryKeys';
import { Badge, EmptyState, Spinner } from '../components/foundation';
import { PageContainer } from '../components/layout';
import common from './PageCommon.module.css';

export function OperationsPage() {
  const summary = useQuery({ queryKey: queryKeys.operationsSummary, queryFn: endpoints.operationsSummary, refetchInterval: 15000 });
  const metricKeys = 'heap_utilization,page_cache_hit_ratio,query_latency_p95,active_transactions,replication_lag';
  const metrics = useQuery({
    queryKey: queryKeys.operationsMetrics(metricKeys, '15m', '15s'),
    queryFn: () => endpoints.operationsMetrics(metricKeys),
    refetchInterval: 15000,
    refetchIntervalInBackground: false,
  });
  const alerts = useQuery({ queryKey: queryKeys.operationsAlerts, queryFn: endpoints.operationsAlerts });
  const runbook = useQuery({ queryKey: queryKeys.operationsRunbook, queryFn: endpoints.operationsRunbook });

  return <PageContainer eyebrow="Operations" title="Neo4j cluster health and runbooks" description="Polling operational signals for cluster mode, constraints, indexes, metrics, alerts, and remediation steps.">
    {summary.isLoading && <Spinner label="Polling operations" />}
    {summary.isError && <EmptyState title="Operations API unavailable" description="Metrics and cluster status will resume when the backend is reachable." />}
    <div className={common.grid4}><article className={common.card}><span className={common.label}>Mode</span><p className={common.metric}>{summary.data?.mode ?? 'n/a'}</p></article><article className={common.card}><span className={common.label}>Health</span><p className={common.metric}>{summary.data?.health ?? 'unknown'}</p></article><article className={common.card}><span className={common.label}>Constraints</span><p className={common.metric}>{summary.data?.constraintCount ?? 0}</p></article><article className={common.card}><span className={common.label}>Indexes online</span><p className={common.metric}>{summary.data?.indexOnlineCount ?? 0}</p></article></div>
    <div className={common.grid2}><article className={common.card}><span className={common.label}>Metric streams</span>{metrics.data?.map((series) => <div key={series.metric}><div className={common.row}><strong>{series.metric}</strong><Badge tone={series.status === 'healthy' ? 'healthy' : series.status === 'critical' ? 'critical' : 'warning'}>{series.status}</Badge></div><ResponsiveContainer width="100%" height={130}><LineChart data={series.points}><XAxis dataKey="timestamp" hide /><YAxis hide /><ChartTooltip /><Line type="monotone" dataKey="value" stroke="#c8f23a" dot={false} /></LineChart></ResponsiveContainer></div>)}</article><article className={common.card}><span className={common.label}>Cluster health</span><h2>{summary.data?.label ?? 'Standalone lab'}</h2><p>{summary.data?.productionTargetLabel}</p><ul className={common.list}>{summary.data?.members.map((member) => <li className={common.item} key={`${member.role}-${member.address}`}><div className={common.row}><strong>{member.role}</strong><Badge>{member.status}</Badge></div><p>{member.address || 'local member'}</p></li>)}</ul></article></div>
    <div className={common.grid2}><article className={common.card}><span className={common.label}>Alerts</span>{alerts.isLoading ? <Spinner /> : <ul className={common.list}>{alerts.data?.map((alert) => <li className={common.item} key={alert.name}><div className={common.row}><strong>{alert.name}</strong><Badge tone={alert.evaluatedStatus === 'critical' ? 'critical' : 'warning'}>{alert.severity}</Badge></div><p>{alert.message}</p></li>)}</ul>}</article><article className={common.card}><span className={common.label}>Runbook stepper</span>{runbook.isLoading ? <Spinner /> : <ol className={common.list}>{runbook.data?.map((step, index) => <li className={common.item} key={step.id}><Badge>Step {index + 1}</Badge><h3>{step.title}</h3><p>{step.summary}</p><pre className={common.code}>{step.commands.join('\n')}</pre></li>)}</ol>}</article></div>
  </PageContainer>;
}
