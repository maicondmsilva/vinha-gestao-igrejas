import '../../../access-flow.css';

// Informational only. Never trust checkout query parameters as payment evidence.
export default function SubscriptionReturn(){
 return <main className="access-flow"><section className="access-flow-card recovery-card">
  <a className="access-flow-brand" href="/"><i>V</i><span><b>Vinha</b><small>Assinaturas · homologação</small></span></a>
  <div className="access-step">RETORNO DO CHECKOUT</div>
  <h1>Você voltou do Mercado Pago</h1>
  <div className="access-flow-notice" role="status">Pagamento não confirmado nesta página.</div>
  <p>Este retorno não confirma a assinatura, o recebimento de valores ou a liberação de módulos. Mesmo que o checkout indique autorização, a Vinha precisa conferir o resultado diretamente com o provedor.</p>
  <p>Esta etapa está em homologação. A consulta automática da assinatura ainda não está disponível aqui. Não refaça o pagamento para tentar atualizar esta tela.</p>
  <a className="access-primary" href="/minha-assinatura">Consultar minha assinatura</a>
  <footer><a href="/suporte">Falar com a equipe Vinha</a><a href="/login">Voltar ao acesso</a></footer>
 </section></main>;
}
