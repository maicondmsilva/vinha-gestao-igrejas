'use client';
import {useEffect, useState} from 'react';

type Item = {
  id: string;
  code: string;
  kind: string;
  version: number;
  title: string;
  choices: Record<string, boolean>;
  signerName: string;
  subjectName: string;
  acceptedAt: string;
  revokedAt: string | null;
  revokedReason: string | null;
};
const labels: Record<string, string> = {photos: 'fotos', videos: 'vídeos', social: 'redes sociais', live: 'transmissões'};
const tenantQuery = () => {
  const t = typeof window === 'undefined' ? '' : new URLSearchParams(location.search).get('tenant');
  return t ? {tenant: t} : ({} as Record<string, string>);
};

/** Ficha da pessoa: termos assinados (como titular ou como responsável por criança), com PDF e código de verificação. */
export default function PersonConsents({personId}: {personId: string}) {
  const [items, setItems] = useState<Item[] | null>(null),
    [error, setError] = useState('');
  useEffect(() => {
    if (!/^[0-9a-f-]{36}$/i.test(personId)) return;
    const c = new AbortController();
    fetch('/api/people/consents?' + new URLSearchParams({person: personId, ...tenantQuery()}), {cache: 'no-store', signal: c.signal})
      .then(async (r) => {
        const d = (await r.json()) as {items?: Item[]; error?: string};
        if (!r.ok) throw Error(d.error || 'Indisponível.');
        setItems(d.items || []);
      })
      .catch((e) => {
        if (!c.signal.aborted) setError(e instanceof Error ? e.message : 'Indisponível.');
      });
    return () => c.abort();
  }, [personId]);
  if (error) return null;
  return (
    <section>
      <h3>Termos assinados</h3>
      {!items && <p>Consultando…</p>}
      {items && !items.length && <p>Nenhum termo assinado pelo aplicativo ainda.</p>}
      {items?.map((i) => (
        <div key={i.id} className="profile-grid" style={{opacity: i.revokedAt ? 0.6 : 1, marginBottom: 8}}>
          <span>
            <small>
              {i.revokedAt ? i.revokedReason || 'Revogado' : 'Válido'} · versão {i.version || 'padrão'}
            </small>
            <b>{i.title}</b>
          </span>
          <span>
            <small>
              Assinado por {i.signerName}
              {i.kind.startsWith('kids_') ? ' · criança: ' + i.subjectName : ''}
            </small>
            <b>{new Date(i.acceptedAt).toLocaleString('pt-BR', {timeZone: 'America/Sao_Paulo'})}</b>
          </span>
          {Object.keys(i.choices || {}).length > 0 && (
            <span>
              <small>Autoriza</small>
              <b>
                {Object.entries(i.choices)
                  .filter(([, v]) => v)
                  .map(([k]) => labels[k] || k)
                  .join(', ') || 'nenhum uso de imagem'}
              </b>
            </span>
          )}
          <span>
            <small>Código</small>
            <b>
              <a href={'/api/consent/pdf?' + new URLSearchParams({code: i.code, ...tenantQuery()})} target="_blank" rel="noreferrer">
                {i.code} · PDF
              </a>
            </b>
          </span>
        </div>
      ))}
    </section>
  );
}
