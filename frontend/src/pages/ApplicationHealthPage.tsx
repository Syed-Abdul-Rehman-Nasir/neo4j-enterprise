import { useEffect, useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import { useQuery } from '@tanstack/react-query';
import { endpoints } from '../api/endpoints';
import { queryKeys } from '../api/queryKeys';
import { Badge, EmptyState, Spinner } from '../components/foundation';
import { PageContainer } from '../components/layout';
import common from './PageCommon.module.css';

export function ApplicationHealthPage() {
  const [searchParams, setParams] = useSearchParams();
  const [applicationId, setApplicationId] = useState(searchParams.get('applicationId') ?? 'APP-001');
  const [asOf, setAsOf] = useState(searchParams.get('asOf') ?? '2099-12-31T23:59:59');
  const [minIncidents, setMinIncidents] = useState(Number(searchParams.get('minIncidents') ?? '0'));

  useEffect(() => {
    setParams({ applicationId, asOf, minIncidents: String(minIncidents) });
  }, [applicationId, asOf, minIncidents, setParams]);

  const top = useQuery({
    queryKey: queryKeys.topApplications(5),
    queryFn: () => endpoints.topApplicationsByUsers(5),
  });
  const high = useQuery({
    queryKey: ['high-incidents', minIncidents],
    queryFn: () => endpoints.highIncidents(minIncidents),
  });
  const incidents = useQuery({
    queryKey: queryKeys.incidents({ applicationId }),
    queryFn: () => endpoints.incidents({ applicationId }),
  });
  const downstream = useQuery({
    queryKey: queryKeys.downstream(applicationId),
    queryFn: () => endpoints.downstream(applicationId),
  });
  const clean = useQuery({
    queryKey: queryKeys.noIncidents(asOf),
    queryFn: () => endpoints.noIncidents(asOf),
  });

  return (
    <PageContainer
      eyebrow="Application health"
      title="Risk rail and dependency health"
      description="Correlate incident history, user concentration, and downstream application chains."
      actions={
        <div className={common.row}>
          <label>
            minIncidents
            <input
              className={common.input}
              type="number"
              value={minIncidents}
              onChange={(e) => setMinIncidents(Number(e.target.value))}
            />
          </label>
          <label>
            asOf
            <input className={common.input} value={asOf} onChange={(e) => setAsOf(e.target.value)} />
          </label>
        </div>
      }
    >
      <div className={common.grid3}>
        <article className={common.card}>
          <span className={common.label}>Application risk rail</span>
          {top.isLoading ? (
            <Spinner />
          ) : (
            <ul className={common.list}>
              {top.data?.map((app) => (
                <li
                  className={common.item}
                  key={app.applicationId}
                  onClick={() => setApplicationId(app.applicationId)}
                  style={{
                    outline: app.applicationId === applicationId ? '2px solid var(--color-signal)' : undefined,
                    cursor: 'pointer',
                  }}
                >
                  <div className={common.row}>
                    <strong>{app.name}</strong>
                    <Badge tone={app.incidentCount > 2 ? 'critical' : 'warning'}>
                      {app.incidentCount} incidents
                    </Badge>
                  </div>
                  <p>
                    {app.uniqueUsers} users · tier {app.tier}
                  </p>
                </li>
              ))}
            </ul>
          )}
          <span className={common.label}>Q3 above threshold {minIncidents}</span>
          <ul className={common.list}>
            {(high.data ?? []).map((row) => (
              <li key={String(row.applicationId)}>
                {String(row.name)} · {String(row.incidentCount)} incidents
              </li>
            ))}
          </ul>
        </article>
        <article className={common.card}>
          <span className={common.label}>Incidents timeline · {applicationId}</span>
          {incidents.isLoading ? (
            <Spinner />
          ) : incidents.data?.length ? (
            <ul className={common.list}>
              {incidents.data.map((incident) => (
                <li className={common.item} key={incident.incidentId}>
                  <div className={common.row}>
                    <strong>{incident.title}</strong>
                    <Badge tone={incident.severity === 'P1' ? 'critical' : 'warning'}>
                      {incident.severity}
                    </Badge>
                  </div>
                  <p>
                    {incident.status} · MTTR {incident.mttrMinutes ?? 'n/a'} min
                  </p>
                </li>
              ))}
            </ul>
          ) : (
            <EmptyState title="No incidents for selection" description="This application has no matching incident history." />
          )}
        </article>
        <article className={common.card}>
          <span className={common.label}>Clean applications (Q8)</span>
          {clean.isLoading ? (
            <Spinner />
          ) : clean.data?.length ? (
            <ul className={common.list}>
              {clean.data.map((app) => (
                <li className={common.item} key={app.id}>
                  <div className={common.row}>
                    <strong>{app.application}</strong>
                    <Badge tone="healthy">clean</Badge>
                  </div>
                  <p>
                    {app.owner} · tier {app.tier}
                  </p>
                </li>
              ))}
            </ul>
          ) : (
            <EmptyState
              title="No clean applications at this asOf"
              description="Positive empty: every application has at least one incident before the cutoff."
            />
          )}
        </article>
      </div>
      <article className={common.card}>
        <span className={common.label}>Downstream chain for {applicationId}</span>
        {downstream.isLoading ? (
          <Spinner />
        ) : (
          <table className={common.table}>
            <thead>
              <tr>
                <th>Application</th>
                <th>Service</th>
                <th>Database</th>
                <th>Server</th>
                <th>Criticality</th>
              </tr>
            </thead>
            <tbody>
              {downstream.data?.map((row, index) => (
                <tr key={`${row.service}-${index}`}>
                  <td>
                    {row.application} {row.appVersion}
                  </td>
                  <td>
                    {row.service} ({row.svcType})
                  </td>
                  <td>
                    {row.database} · {row.dbEngine}
                  </td>
                  <td>
                    {row.server} · {row.serverRegion}
                  </td>
                  <td>{row.criticality}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </article>
    </PageContainer>
  );
}
