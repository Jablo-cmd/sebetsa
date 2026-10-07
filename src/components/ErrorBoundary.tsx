import { Component, type ErrorInfo, type ReactNode } from 'react';
import { reportError } from '@/lib/errorReporting';

interface State {
  failed: boolean;
}

/** Last-resort boundary: reports the render error (scrubbed) and shows a calm recovery screen instead of a blank page. */
export class ErrorBoundary extends Component<{ children: ReactNode }, State> {
  state: State = { failed: false };

  static getDerivedStateFromError(): State {
    return { failed: true };
  }

  componentDidCatch(error: Error, _info: ErrorInfo): void {
    reportError('render', error);
  }

  render() {
    if (!this.state.failed) return this.props.children;
    return (
      <div role="alert" className="flex min-h-dvh flex-col items-center justify-center gap-4 bg-surface-sunken px-4 text-center">
        <h1 className="text-xl font-semibold text-content-primary">Something went wrong</h1>
        <p className="max-w-md text-sm text-content-secondary">
          The page hit an unexpected problem. It has been reported. Reloading usually fixes it.
        </p>
        <button type="button" className="focus-ring rounded-lg bg-brand-600 px-4 py-2 text-sm font-semibold text-white" onClick={() => window.location.assign('/')}>
          Reload
        </button>
      </div>
    );
  }
}
