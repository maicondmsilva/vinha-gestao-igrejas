'use client';
import {useEffect, useState} from 'react';

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Finds the event attempt saved by EventCheckout in this browser for the returned order. */
function savedEventFor(order: string) {
  try {
    for (let i = 0; i < localStorage.length; i++) {
      const key = localStorage.key(i) || '';
      if (!key.startsWith('vinha-event-order:')) continue;
      const event = key.slice('vinha-event-order:'.length);
      const attempt = JSON.parse(localStorage.getItem(key) || 'null') as {id?: string} | null;
      if (uuid.test(event) && attempt?.id === order) return event;
    }
  } catch {
    /* Storage can be disabled; the buyer still has the e-mail link. */
  }
  return null;
}

export default function PaymentReturn() {
  const [lost, setLost] = useState(false);
  useEffect(() => {
    const order = new URLSearchParams(location.search).get('pedido') || '';
    const event = uuid.test(order) ? savedEventFor(order) : null;
    if (event) location.replace('/eventos/e-' + event + '?pedido=' + encodeURIComponent(order) + '#inscricoes');
    else {
      const timer = window.setTimeout(() => setLost(true), 0);
      return () => window.clearTimeout(timer);
    }
  }, []);
  return (
    <main style={{maxWidth: 560, margin: '12vh auto', padding: '32px 20px', fontFamily: 'system-ui', color: '#173f35'}}>
      <p style={{letterSpacing: '.08em', fontSize: 12, color: '#5f6f64'}}>VINHA · PAGAMENTO</p>
      <h1 style={{fontSize: 26}}>{lost ? 'Estamos conferindo seu pagamento' : 'Voltando para o seu pedido…'}</h1>
      {lost && (
        <>
          <p>
            A confirmação chega da instituição de pagamento em alguns instantes. O comprovante e o link do pedido são
            enviados para o e-mail informado na compra.
          </p>
          <p>Não pague novamente enquanto o primeiro pagamento estiver em análise.</p>
          <button
            type="button"
            onClick={() => history.back()}
            style={{marginTop: 12, padding: '12px 20px', borderRadius: 9, border: '1px solid #285c45', background: '#285c45', color: '#fff', font: 'inherit', cursor: 'pointer'}}
          >
            Voltar
          </button>
        </>
      )}
    </main>
  );
}
