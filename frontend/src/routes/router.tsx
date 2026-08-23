import { createBrowserRouter, Navigate } from 'react-router-dom';
import { AppShell } from '../components/layout';
import { ApplicationHealthPage } from '../pages/ApplicationHealthPage';
import { GraphExplorerPage } from '../pages/GraphExplorerPage';
import { ImpactAnalysisPage } from '../pages/ImpactAnalysisPage';
import { OperationsPage } from '../pages/OperationsPage';
import { OverviewPage } from '../pages/OverviewPage';
import { QueryWorkbenchPage } from '../pages/QueryWorkbenchPage';

export const router = createBrowserRouter([
  { path: '/', element: <AppShell />, children: [
    { index: true, element: <OverviewPage /> },
    { path: 'graph', element: <GraphExplorerPage /> },
    { path: 'impact', element: <ImpactAnalysisPage /> },
    { path: 'applications', element: <ApplicationHealthPage /> },
    { path: 'operations', element: <OperationsPage /> },
    { path: 'queries', element: <Navigate to="/queries/q4" replace /> },
    { path: 'queries/:queryId', element: <QueryWorkbenchPage /> }
  ] }
]);
