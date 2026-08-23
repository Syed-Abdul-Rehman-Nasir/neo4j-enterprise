import { FormEvent, useEffect, useMemo, useState } from 'react';
import { Navigate, NavLink, useParams } from 'react-router-dom';
import { useMutation, useQuery } from '@tanstack/react-query';
import { createColumnHelper, flexRender, getCoreRowModel, useReactTable } from '@tanstack/react-table';
import { Bar, BarChart, ResponsiveContainer, Tooltip as ChartTooltip, XAxis, YAxis } from 'recharts';
import { endpoints } from '../api/endpoints';
import { queryKeys } from '../api/queryKeys';
import { Badge, Button, EmptyState, Spinner } from '../components/foundation';
import { PageContainer } from '../components/layout';
import type { QueryCatalogItem, QueryExecutionResponse } from '../types/api';
import common from './PageCommon.module.css';

const helper = createColumnHelper<Record<string, unknown>>();

export function QueryWorkbenchPage() {
  const { queryId } = useParams();
  if (!queryId) return <Navigate to="/queries/q4" replace />;
  const catalog = useQuery({ queryKey: queryKeys.queries, queryFn: endpoints.queries });
  const query = useQuery({ queryKey: queryKeys.query(queryId), queryFn: () => endpoints.query(queryId) });
  const [params, setParams] = useState<Record<string, unknown>>({});
  const mutation = useMutation({ mutationFn: () => endpoints.executeQuery(queryId, { parameters: params }) });

  useEffect(() => { if (query.data) setParams(query.data.defaultParams); }, [query.data]);
  const onSubmit = (event: FormEvent) => { event.preventDefault(); mutation.mutate(); };

  return <PageContainer eyebrow="Query workbench" title="Q1-Q9 Cypher navigator" description="Inspect allowlisted production Cypher, tune parameters, execute through the API, and review result sets.">
    <div className={common.grid2}><article className={common.card}><span className={common.label}>Navigator</span>{catalog.isLoading ? <Spinner /> : <div className={common.row} style={{ flexWrap: 'wrap', justifyContent: 'flex-start' }}>{catalog.data?.map((item) => <NavLink key={item.queryId} to={`/queries/${item.queryId}`}><Button variant={item.queryId === queryId ? 'primary' : 'ghost'} size="small">{item.queryId.toUpperCase()}</Button></NavLink>)}</div>}</article><article className={common.card}><span className={common.label}>Expected operators</span><div className={common.row} style={{ justifyContent: 'flex-start', flexWrap: 'wrap' }}>{query.data?.expectedOperators.map((op) => <Badge key={op}>{op}</Badge>)}</div></article></div>
    {query.isLoading && <Spinner label="Loading query" />}{query.isError && <EmptyState title="Query unavailable" description="Select another Q1-Q9 query or check the backend catalog." />}
    {query.data && <WorkbenchForm query={query.data} params={params} setParams={setParams} onSubmit={onSubmit} isPending={mutation.isPending} />}
    {mutation.data && <Results response={mutation.data} queryId={queryId} />}
    {mutation.isError && <EmptyState title="Execution failed" description="The API rejected the execution. Check parameters and backend connectivity." />}
  </PageContainer>;
}
function WorkbenchForm({ query, params, setParams, onSubmit, isPending }: { query: QueryCatalogItem; params: Record<string, unknown>; setParams: (params: Record<string, unknown>) => void; onSubmit: (event: FormEvent) => void; isPending: boolean }) { return <div className={common.grid2}><article className={common.card}><div className={common.row}><div><span className={common.label}>{query.queryId.toUpperCase()}</span><h2>{query.title}</h2><p>{query.description}</p></div><Badge>{query.presentation}</Badge></div><pre className={common.code}>{query.cypher}</pre></article><form className={common.card} onSubmit={onSubmit}><span className={common.label}>Parameters</span><div className={common.stack}>{query.parameters.map((parameter) => <label key={parameter.name}><strong>{parameter.name}</strong><input className={common.input} value={String(params[parameter.name] ?? '')} onChange={(event) => setParams({ ...params, [parameter.name]: parameter.type === 'integer' ? Number(event.target.value) : event.target.value || null })} /><small>{parameter.description}</small></label>)}<Button type="submit" variant="primary" disabled={isPending}>{isPending ? 'Executing...' : 'Execute query'}</Button></div></form></div>; }
function Results({ response, queryId }: { response: QueryExecutionResponse; queryId: string }) {
  const columns = useMemo(() => response.columns.map((column) => helper.accessor((row) => row[column], { id: column, header: column, cell: (info) => String(info.getValue() ?? '') })), [response.columns]);
  const table = useReactTable({ data: response.rows, columns, getCoreRowModel: getCoreRowModel() });
  const chartData = response.rows.slice(0, 8).map((row, index) => ({ name: String(row.name ?? row.application ?? row.employee ?? `Row ${index + 1}`), value: Number(row.incidentCount ?? row.uniqueUsers ?? row.appCount ?? row.hops ?? index + 1) }));
  if (queryId === 'q7' && response.rows.length === 0) {
    return <article className={common.card}><Badge tone="healthy">Positive empty</Badge><h2>No concentrated shared-database exposure</h2><p>At minApps=2 the lab dataset intentionally returns zero rows — employees do not share multiple apps onto one database.</p><Badge>{response.executionMs.toFixed(1)} ms</Badge></article>;
  }
  return <div className={common.grid2}><article className={common.card}><div className={common.row}><span className={common.label}>Results</span><Badge>{response.executionMs.toFixed(1)} ms</Badge></div><table className={common.table}><thead>{table.getHeaderGroups().map((group) => <tr key={group.id}>{group.headers.map((header) => <th key={header.id}>{flexRender(header.column.columnDef.header, header.getContext())}</th>)}</tr>)}</thead><tbody>{table.getRowModel().rows.map((row) => <tr key={row.id}>{row.getVisibleCells().map((cell) => <td key={cell.id}>{flexRender(cell.column.columnDef.cell, cell.getContext())}</td>)}</tr>)}</tbody></table></article><article className={common.card}><span className={common.label}>Simple visualization</span><ResponsiveContainer width="100%" height={300}><BarChart data={chartData}><XAxis dataKey="name" hide /><YAxis hide /><ChartTooltip /><Bar dataKey="value" fill="#c8f23a" /></BarChart></ResponsiveContainer></article></div>;
}
