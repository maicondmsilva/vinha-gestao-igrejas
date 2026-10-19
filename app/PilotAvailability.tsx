'use client';

import type { ReactNode } from 'react';
import { pilotViewAllowed, releaseCatalog } from './lib/release-availability';

export function UnavailableFeature({ title = 'Recurso em desenvolvimento', detail }: { title?: string; detail?: string }) {
  return <section className="content" aria-label="Disponibilidade do recurso">
    <div className="card" style={{ padding: 28, maxWidth: 850 }}>
      <p className="section-over">EM DESENVOLVIMENTO · VISUALIZAÇÃO DISPONÍVEL</p>
      <h1>{title}</h1>
      <p>{detail || 'Este recurso depende de migração e validação antes de operar com dados reais.'}</p>
      <p>Nenhuma operação deste módulo está disponível nesta etapa. Não utilize telas antigas de demonstração para cadastrar dados, receber pagamentos ou emitir documentos.</p>
      <a href="/suporte">Conversar com a equipe Vinha →</a>
    </div>
    <section aria-label="Todos os módulos da Vinha" className="card" style={{padding:28,marginTop:20,maxWidth:850}}>
      <h2>Conheça os módulos da Vinha</h2>
      <p>Os módulos em desenvolvimento podem ser consultados aqui, mas suas operações continuam indisponíveis. Esta visualização não altera o plano contratado nem as permissões de acesso.</p>
      <div style={{display:'grid',gridTemplateColumns:'repeat(auto-fit,minmax(220px,1fr))',gap:12}}>
        {releaseCatalog.map(module=><button key={module.id} type="button" style={{textAlign:'left',padding:16,border:'1px solid #dce5df',borderRadius:12,background:'#fff',color:'#193f30',cursor:'pointer'}} onClick={()=>{const target=new URL(location.href);target.searchParams.set('pagina',module.id);location.assign(target.href)}}>
          <strong>{module.title}</strong><br/><small>{module.status==='development'?'Em desenvolvimento':'Piloto em validação'}</small>
        </button>)}
      </div>
    </section>
  </section>;
}

export function PilotModuleBoundary({ view, children }: { view: string; children: ReactNode }) {
  const feature = releaseCatalog.find(item => item.id === view);
  if (!pilotViewAllowed(view)) return <UnavailableFeature title={feature?.title} detail={feature?.detail}/>;
  return <><aside role="note" style={{ margin: '16px 24px', padding: 16, background: '#fff4da', color: '#604400', borderRadius: 12 }}>
    <strong>Piloto em preparação.</strong> Este núcleo ainda está em validação. Módulo contratado não significa recurso operacionalmente liberado. {feature?.detail}
  </aside>{children}</>;
}
