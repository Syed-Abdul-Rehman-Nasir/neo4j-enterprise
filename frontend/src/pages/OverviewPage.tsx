import { useQuery } from '@tanstack/react-query';
import { Link } from 'react-router-dom';
import { motion } from 'motion/react';
import { Activity, AlertTriangle, Database, GitBranch, Network } from 'lucide-react';
import { endpoints } from '../api/endpoints';
import { queryKeys } from '../api/queryKeys';
import { Badge, Button, EmptyState, Icon, Spinner } from '../components/foundation';
import { PageContainer } from '../components/layout';
import styles from './PageCommon.module.css';

const metricIcons = [Network, GitBranch, Database, AlertTriangle, Activity];

export function OverviewPage() {
  const { data, isLoading, isError, refetch } = useQuery({
    queryKey: queryKeys.overview,
    queryFn: endpoints.overview,
  });

  const metrics = data
    ? [
        ['Nodes', data.nodeCount],
        ['Relationships', data.relationshipCount],
        ['Applications', data.applicationCount],
        ['Incidents', data.incidentCount],
        ['Active', data.activeIncidentCount],
      ]
    : [];

  const scenario = data?.db001Scenario;
  const ribbon = scenario
    ? `${scenario.databaseId} → ${scenario.serviceCount} services → ${scenario.applicationName} → ${scenario.employeeCount} employees`
    : null;

  return (
    <PageContainer
      eyebrow="Command overview"
      title="Trace failure impact from infrastructure to people"
      description="Live lab graph facts stay separate from the 5M/100M production scale target. Interview landing for topology, blast radius, and Neo4j ops."
    >
      {isLoading && <Spinner label="Loading overview" />}
      {isError && (
        <EmptyState
          title="Seed graph not loaded"
          description="Start Neo4j, apply cypher/00_constraints_indexes.cypher and cypher/01_sample_data.cypher, then start the FastAPI BFF."
          action={<Button onClick={() => refetch()}>Retry</Button>}
        />
      )}
      {data && !data.seedLoaded && (
        <EmptyState
          title="Seed graph incomplete"
          description="Overview counts are below the expected 38-node lab. Re-run the sample data script."
        />
      )}
      {data && (
        <>
          <div className={styles.grid4}>
            {metrics.map(([label, value], index) => {
              const IconComponent = metricIcons[index];
              return (
                <motion.article
                  key={String(label)}
                  className={styles.card}
                  initial={{ opacity: 0, y: 8 }}
                  animate={{ opacity: 1, y: 0 }}
                  transition={{ delay: index * 0.04 }}
                >
                  <div className={styles.row}>
                    <span className={styles.label}>{label}</span>
                    <Icon icon={IconComponent} />
                  </div>
                  <p className={styles.metric}>{String(value)}</p>
                </motion.article>
              );
            })}
          </div>
          <div className={styles.grid3}>
            <article className={styles.card}>
              <div className={styles.row}>
                <span className={styles.label}>Production scale target</span>
                <Badge tone="neutral">Not live demo counts</Badge>
              </div>
              <p className={styles.metric}>
                {(data.scaleTarget.components / 1_000_000).toFixed(0)}M /{' '}
                {(data.scaleTarget.relationships / 1_000_000).toFixed(0)}M
              </p>
              <p>
                Components / relationships · live blast-radius P90 ≤ {data.scaleTarget.liveBlastRadiusP90Ms}
                ms · precomputed tier-1 reads {data.scaleTarget.precomputedTierMsMin}–
                {data.scaleTarget.precomputedTierMsMax}ms
              </p>
            </article>
            <Link className={`${styles.card} ${styles.cardInteractive}`} to="/impact?databaseId=DB-001&applicationId=APP-001">
              <span className={styles.label}>DB-001 scenario</span>
              <h2>{scenario?.databaseName ?? 'fin-postgres-prod'}</h2>
              <p className={styles.label}>{ribbon}</p>
              <p>
                {(scenario?.employeeNames ?? []).slice(0, 4).join(', ') || 'Employees pending'}
              </p>
              <Button variant="primary" size="small">
                Open impact analysis
              </Button>
            </Link>
            <Link
              className={`${styles.card} ${styles.cardInteractive}`}
              to={`/applications?applicationId=${String(data.highRiskApplication?.applicationId ?? 'APP-001')}`}
            >
              <div className={styles.row}>
                <span className={styles.label}>High-risk application</span>
                <Badge tone="critical">
                  {String(data.highRiskApplication?.incidentCount ?? 0)} incidents
                </Badge>
              </div>
              <h2>{String(data.highRiskApplication?.name ?? '—')}</h2>
              <p>Tier {String(data.highRiskApplication?.tier ?? '—')} · open application health</p>
            </Link>
          </div>
          <div className={styles.row}>
            <Link to="/operations">
              <Button variant="ghost" size="small">
                Operations health
              </Button>
            </Link>
            <Link to="/graph">
              <Button variant="ghost" size="small">
                Full topology
              </Button>
            </Link>
            <Link to="/queries/q4">
              <Button variant="ghost" size="small">
                Query workbench
              </Button>
            </Link>
          </div>
        </>
      )}
    </PageContainer>
  );
}
