'use client';
import '../../eventos/[slug]/public-event.css';
export default function PaymentReturn(){const status=typeof location==='undefined'?'pending':new URLSearchParams(location.search).get('status'),ok=status==='success';return <main className="public-event-state"><h1>{ok?'Pagamento enviado':'Pagamento em processamento'}</h1><p>{ok?'A confirmação será atualizada automaticamente assim que o provedor concluir a transação.':'Você pode fechar esta página. A igreja receberá a atualização automática do provedor.'}</p><button onClick={()=>history.back()}>Voltar ao evento</button></main>}
