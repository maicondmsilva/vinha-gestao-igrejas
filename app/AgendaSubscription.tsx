'use client';
import {useEffect, useState} from 'react';
import {settingsUrl} from './lib/settings-navigation';
import {readApiError} from '../shared/contract/errors';

/** Subscription link of the church agenda for Google Agenda, Apple Calendário and Outlook. */
export default function AgendaSubscription({unit}: {unit: string}) {
  const [url, setUrl] = useState<string | null | undefined>(undefined),
    [open, setOpen] = useState(false),
    [busy, setBusy] = useState(false),
    [notice, setNotice] = useState(''),
    [denied, setDenied] = useState(false);
  const endpoint = settingsUrl('/api/agenda/feed-admin?' + new URLSearchParams({unit}));
  useEffect(() => {
    if (!open || url !== undefined) return;
    let live = true;
    fetch(endpoint, {cache: 'no-store'})
      .then(async (r) => {
        const d = await r.json().catch(() => ({}));
        if (!live) return;
        if (r.status === 403) setDenied(true);
        if (!r.ok) throw Error(readApiError(d).error);
        setUrl((d as {url: string | null}).url);
      })
      .catch((e) => live && setNotice((e as Error).message));
    return () => {
      live = false;
    };
  }, [open, url, endpoint]);
  async function act(action: 'rotate' | 'disable') {
    setBusy(true);
    setNotice('');
    try {
      const r = await fetch(endpoint, {method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({action})});
      const d = await r.json().catch(() => ({}));
      if (!r.ok) throw Error(readApiError(d).error);
      setUrl((d as {url: string | null}).url);
      setNotice(
        action === 'disable'
          ? 'Link desativado. Calendários que assinavam deixam de receber atualizações.'
          : 'Link novo criado. O anterior deixou de funcionar.',
      );
    } catch (e) {
      setNotice((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  const webcal = url ? url.replace(/^https?:/, 'webcal:') : '';
  return (
    <details className="program-subscribe" open={open} onToggle={(e) => setOpen((e.currentTarget as HTMLDetailsElement).open)}>
      <summary>Assinar esta agenda no Google Agenda, Apple Calendário ou Outlook</summary>
      {denied ? (
        <p>Somente quem gerencia a agenda desta igreja cria o link de assinatura.</p>
      ) : url === undefined && !notice ? (
        <p role="status">Carregando…</p>
      ) : url ? (
        <div>
          <p>
            Quem tiver o link vê os eventos publicados desta igreja (últimos 30 dias e próximos 12 meses). Os calendários atualizam sozinhos a cada poucas
            horas.
          </p>
          <div className="program-subscribe-row">
            <input readOnly value={url} aria-label="Link de assinatura" onFocus={(e) => e.currentTarget.select()} />
            <button type="button" onClick={() => void navigator.clipboard?.writeText(url).then(() => setNotice('Link copiado.'))}>
              Copiar
            </button>
            <a className="program-subscribe-open" href={webcal}>
              Abrir no calendário
            </a>
          </div>
          <p>
            <button type="button" disabled={busy} onClick={() => void act('rotate')}>
              Trocar link
            </button>{' '}
            <button type="button" disabled={busy} onClick={() => void act('disable')}>
              Desativar
            </button>
          </p>
        </div>
      ) : (
        <div>
          <p>Crie um link para que a igreja acompanhe a agenda no calendário do celular. Apenas eventos publicados aparecem.</p>
          <button type="button" disabled={busy} onClick={() => void act('rotate')}>
            {busy ? 'Criando…' : 'Criar link de assinatura'}
          </button>
        </div>
      )}
      {notice && (
        <p className="program-subscribe-notice" role="status">
          {notice}
        </p>
      )}
    </details>
  );
}
