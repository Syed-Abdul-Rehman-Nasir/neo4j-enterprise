import { Component, type ErrorInfo, type ReactNode } from 'react';

type Props = { children: ReactNode };
type State = { error: Error | null };

export class ErrorBoundary extends Component<Props, State> {
  state: State = { error: null };

  static getDerivedStateFromError(error: Error): State {
    return { error };
  }

  componentDidCatch(error: Error, info: ErrorInfo): void {
    console.error('UI error boundary', error, info);
  }

  render() {
    if (this.state.error) {
      return (
        <main style={{ padding: 32, fontFamily: 'IBM Plex Sans, sans-serif' }}>
          <h1>Something went wrong</h1>
          <p>The console hit an unexpected UI error. Reload to continue the interview demo.</p>
          <pre>{this.state.error.message}</pre>
          <button type="button" onClick={() => this.setState({ error: null })}>
            Dismiss
          </button>
        </main>
      );
    }
    return this.props.children;
  }
}
