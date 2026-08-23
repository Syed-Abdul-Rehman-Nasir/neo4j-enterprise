import { useMemo, useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import { useQuery } from '@tanstack/react-query';
import { Cell, Pie, PieChart, ResponsiveContainer, Tooltip as ChartTooltip } from 'recharts';
import { endpoints } from '../api/endpoints';
import { queryKeys } from '../api/queryKeys';
import { Badge, Button, EmptyState, Spinner } from '../components/foundation';
import { PageContainer } from '../components/layout';
import common from './PageCommon.module.css';

export function ImpactAnalysisPage() {
  const [params, setParams] = useSearchParams();
  const [databaseId, setDatabaseId] = useState(params.get('databaseId') ?? 'DB-001');
  const [applicationId, setApplicationId] = useState(params.get('applicationId') ?? 'APP-001');
  const [simulating, setSimulating] = useState(false);

  const catalogs = useQuery({
    queryKey: ['catalogs'],
    queryFn: async () => ({
      databases: await endpoints.catalogDatabases(),
      applications: await endpoints.catalogApplications(),
    }),
  });

  const impact = useQuery({
    queryKey: queryKeys.impact(databaseId),
    queryFn: () => endpoints.databaseImpact(databaseId),
  });
  const paths = useQuery({
    queryKey: queryKeys.paths(applicationId, databaseId),
    queryFn: () => endpoints.applicationPaths(applicationId, databaseId),
  });

  const radiusData = useMemo(
    () => [
      { name: 'Employees', value: impact.data?.summary.uniqueEmployees ?? 0 },
      { name: 'Applications', value: impact.data?.summary.applications.length ?? 0 },
      { name: 'Services', value: impact.data?.summary.services.length ?? 0 },
      { name: 'Departments', value: impact.data?.summary.departments.length ?? 0 },
    ],
    [impact.data],
  );

  const applySelection = () => {
    setParams({ databaseId, applicationId });
  };

  return (
    <PageContainer
      eyebrow="Blast radius"
      title="Database impact analysis"
      description="Simulate a database failure visually (read-only). DISTINCT employee counts stay honest while path rows preserve multi-hop evidence."
      actions={
        <div className={common.row}>
          <select
            className={common.input}
            aria-label="Database"
            value={databaseId}
            onChange={(e) => setDatabaseId(e.target.value)}
          >
            {(catalogs.data?.databases ?? [{ id: 'DB-001', name: 'DB-001' }]).map((db) => (
              <option key={db.id} value={db.id}>
                {db.id} · {db.name}
              </option>
            ))}
          </select>
          <select
            className={common.input}
            aria-label="Application"
            value={applicationId}
            onChange={(e) => setApplicationId(e.target.value)}
          >
            {(catalogs.data?.applications ?? [{ id: 'APP-001', name: 'APP-001' }]).map((app) => (
              <option key={app.id} value={app.id}>
                {app.id} · {app.name}
              </option>
            ))}
          </select>
          <Button onClick={applySelection} variant="primary">
            Analyze
          </Button>
          <Button
            variant={simulating ? 'primary' : 'ghost'}
            onClick={() => setSimulating((v) => !v)}
          >
            {simulating ? 'Simulation on' : 'Simulate failure'}
          </Button>
        </div>
      }
    >
      {impact.isLoading && <Spinner label="Calculating impact" />}
      {impact.isError && (
        <EmptyState
          title="Impact API unavailable"
          description="No dependents can be computed until the BFF and Neo4j seed are reachable."
        />
      )}
      {impact.data && impact.data.summary.uniqueEmployees === 0 && (
        <EmptyState
          title="No dependents found"
          description={`Database ${databaseId} has no inbound application/employee blast radius in the current graph.`}
        />
      )}
      <div className={common.grid4}>
        <article className={common.card} style={simulating ? { outline: '2px solid var(--status-critical)' } : undefined}>
          <span className={common.label}>Unique people</span>
          <p className={common.metric}>{impact.data?.summary.uniqueEmployees ?? '—'}</p>
        </article>
        <article className={common.card}>
          <span className={common.label}>Applications</span>
          <p className={common.metric}>{impact.data?.summary.applications.length ?? '—'}</p>
        </article>
        <article className={common.card}>
          <span className={common.label}>Services</span>
          <p className={common.metric}>{impact.data?.summary.services.length ?? '—'}</p>
        </article>
        <article className={common.card}>
          <span className={common.label}>Path evidence rows</span>
          <p className={common.metric}>{impact.data?.summary.pathRowCount ?? '—'}</p>
        </article>
      </div>
      <div className={common.grid2}>
        <article className={common.card}>
          <span className={common.label}>
            Concentric blast summary {simulating ? '(failure simulation visual)' : ''}
          </span>
          <ResponsiveContainer width="100%" height={280}>
            <PieChart>
              <Pie data={radiusData} innerRadius={54} outerRadius={110} dataKey="value" label>
                {radiusData.map((_, index) => (
                  <Cell
                    key={index}
                    fill={
                      simulating
                        ? ['#d64545', '#d99100', '#a06a3b', '#5e6c84'][index]
                        : ['#b7f34a', '#008c95', '#8a5a44', '#7656b5'][index]
                    }
                  />
                ))}
              </Pie>
              <ChartTooltip />
            </PieChart>
          </ResponsiveContainer>
          <p className={common.label}>
            Simulation never writes to Neo4j — visualization state only.
          </p>
        </article>
        <article className={common.card}>
          <span className={common.label}>
            Q5 paths · {applicationId} → {databaseId}
          </span>
          {paths.isLoading ? (
            <Spinner />
          ) : (
            <ul className={common.list}>
              {(paths.data?.paths ?? []).map((path, index) => (
                <li className={common.item} key={index}>
                  <Badge>{path.hopCount} hops</Badge>
                  <p>{path.nodeNames.join(' → ')}</p>
                </li>
              ))}
              {!paths.data?.paths.length && (
                <li>
                  <EmptyState title="No bounded paths" description="No DEPENDS_ON*1..3 routes between this pair." />
                </li>
              )}
            </ul>
          )}
        </article>
      </div>
      <article className={common.card}>
        <span className={common.label}>Impacted employees (evidence table)</span>
        <table className={common.table}>
          <thead>
            <tr>
              <th>Name</th>
              <th>Email</th>
              <th>Department</th>
              <th>Via application</th>
              <th>Via service</th>
            </tr>
          </thead>
          <tbody>
            {impact.data?.employees.map((employee, idx) => (
              <tr key={`${employee.email}-${employee.viaService}-${idx}`}>
                <td>{employee.name}</td>
                <td>{employee.email}</td>
                <td>{employee.department}</td>
                <td>{employee.viaApplication}</td>
                <td>{employee.viaService}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </article>
    </PageContainer>
  );
}
