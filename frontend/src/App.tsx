import { RouterProvider } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { ErrorBoundary } from './app/ErrorBoundary';
import { router } from './routes/router';

const queryClient = new QueryClient({
  defaultOptions: { queries: { retry: 1, staleTime: 20_000 } },
});

export function App() {
  return (
    <ErrorBoundary>
      <QueryClientProvider client={queryClient}>
        <RouterProvider router={router} />
      </QueryClientProvider>
    </ErrorBoundary>
  );
}
