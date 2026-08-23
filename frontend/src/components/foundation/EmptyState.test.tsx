import { render, screen } from '@testing-library/react';
import { EmptyState } from './EmptyState';

test('empty state announces title and description', () => {
  render(<EmptyState title="No graph" description="Start the backend." />);
  expect(screen.getByText('No graph')).toBeInTheDocument();
  expect(screen.getByText('Start the backend.')).toBeInTheDocument();
});
