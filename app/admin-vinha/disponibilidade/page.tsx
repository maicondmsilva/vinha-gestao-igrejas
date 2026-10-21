import { releaseCatalog } from '../../lib/release-availability';

export default function OperationalAvailability() {
 return <main className="team-chat-page">
  <a href="/admin-vinha">← Central da Vinha</a>
  <h1>Disponibilidade operacional</h1>
  <p>A liberação é individual por módulo e pelo escopo descrito abaixo. Este catálogo não altera contratos, preços, permissões ou dados das igrejas.</p>
  <article className="sector-card"><h2>Antes de oferecer ou habilitar um módulo</h2>
   <p>Plano contratado, módulo habilitado e recurso operacional são coisas diferentes. Não prometa operação real de módulos em desenvolvimento. Alterar um contrato não remove os bloqueios técnicos de lançamento.</p>
   <p>Recorrência de cartão e emissão fiscal da Central continuam restritas à homologação. O financeiro da igreja é outro módulo e ainda não está liberado.</p>
  </article>
  {releaseCatalog.map(feature=><article className="sector-card" key={feature.id}>
   <h2>{feature.title}</h2><strong>{feature.status==='ready'?'Escopo interno disponível':feature.status==='validation'?'Em validação':'Em desenvolvimento — não liberado'}</strong>
   <p>{feature.detail}</p>
  </article>)}
  <p>Próximos critérios: segurança do núcleo, isolamento entre organizações e unidades, migração restante, recuperação de dados e jornadas completas aprovadas.</p>
 </main>;
}
