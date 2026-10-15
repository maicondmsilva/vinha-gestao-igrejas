import type { ReactNode } from 'react';
import { pilotViewAllowed, releaseCatalog } from './lib/release-availability';

export function UnavailableFeature({ title = 'Recurso em desenvolvimento', detail }: { title?: string; detail?: string }) {
  return <section className="content" aria-label="Disponibilidade do recurso">
    <div className="card" style={{ padding: 28, maxWidth: 850 }}>
      <p className="section-over">PRÉ-LANÇAMENTO · NÃO LIBERADO</p>
      <h1>{title}</h1>
      <p>{detail || 'Este recurso depende de migração e validação antes de operar com dados reais.'}</p>
      <p>Nenhuma operação deste módulo está disponível nesta etapa. Não utilize telas antigas de demonstração para cadastrar dados, receber pagamentos ou emitir documentos.</p>
      <a href="/suporte">Conversar com a equipe Vinha →</a>
    </div>
  </section>;
}

export function PilotModuleBoundary({ view, children }: { view: string; children: ReactNode }) {
  const feature = releaseCatalog.find(item => item.id === view);
  if (!pilotViewAllowed(view)) return <UnavailableFeature title={feature?.title} detail={feature?.detail}/>;
  return <><aside role="note" style={{ margin: '16px 24px', padding: 16, background: '#fff4da', color: '#604400', borderRadius: 12 }}>
    <strong>Piloto em preparação.</strong> Este núcleo ainda está em validação. Módulo contratado não significa recurso operacionalmente liberado. {feature?.detail}
  </aside>{children}</>;
}
