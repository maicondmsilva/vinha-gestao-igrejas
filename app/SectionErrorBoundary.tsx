'use client';
import {Component, Fragment, type ErrorInfo, type ReactNode} from 'react';

/** Pass a function to build the content inside the boundary, so errors in that JSX are caught here too. */
type Props = {area: string; children: ReactNode | (() => ReactNode)};
type State = {failed: boolean; attempt: number};

/** Runs the builder as a child, because a boundary only catches errors thrown below it, not in its own render. */
function Build({build}: {build: () => ReactNode}) {
  return <>{build()}</>;
}

/**
 * Keeps a rendering failure inside one module or section: the rest of the panel (menu, header, other
 * sections) keeps working and the person can try again. It never retries operations on its own and shows
 * no technical detail; the error goes to the browser console for support.
 */
export default class SectionErrorBoundary extends Component<Props, State> {
  state: State = {failed: false, attempt: 0};

  static getDerivedStateFromError(): Partial<State> {
    return {failed: true};
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    console.error('[Vinha] Falha ao exibir ' + this.props.area, error, info.componentStack);
  }

  retry = () => this.setState((s) => ({failed: false, attempt: s.attempt + 1}));

  render() {
    if (this.state.failed)
      return (
        <div className="section-error" role="alert">
          <strong>{this.props.area} não pôde ser exibida.</strong>
          <p>Nenhuma operação foi repetida ou desfeita. Tente de novo; se continuar, atualize a página ou fale com a Vinha.</p>
          <button type="button" onClick={this.retry}>
            Tentar de novo
          </button>
        </div>
      );
    const {children} = this.props;
    return <Fragment key={this.state.attempt}>{typeof children === 'function' ? <Build build={children} /> : children}</Fragment>;
  }
}
