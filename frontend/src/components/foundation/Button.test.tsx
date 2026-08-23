import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { Button } from './Button';

test('button renders children and handles click', async () => {
  const user = userEvent.setup();
  const onClick = vi.fn();
  render(<Button onClick={onClick}>Execute</Button>);
  await user.click(screen.getByRole('button', { name: /execute/i }));
  expect(onClick).toHaveBeenCalledTimes(1);
});
