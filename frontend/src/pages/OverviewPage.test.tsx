import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { OverviewPage } from './OverviewPage';

test('overview renders interview landing title while loading', () => {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(
    <QueryClientProvider client={client}>
      <MemoryRouter>
        <OverviewPage />
      </MemoryRouter>
    </QueryClientProvider>,
  );
  expect(
    screen.getByText('Trace failure impact from infrastructure to people'),
  ).toBeInTheDocument();
  expect(screen.getByText(/Loading overview/i)).toBeInTheDocument();
});
