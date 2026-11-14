'use client';
import {useEffect, useState} from 'react';

type T = {kind: string; version: number; title: string; body: string; custom: boolean};
const names: Record<string, string> = {
  adult_data: 'Dados pessoais (adulto)',
  adult_image: 'Uso de imagem e voz (adulto)',
  kids_guardian: 'Responsável pela criança (Kids)',
  kids_image: 'Imagem da criança (Kids)',
};
const tenantQuery = () => {
  const t = typeof window === 'undefined' ? '' : new URLSearchParams(location.search).get('tenant');
  return t ? {tenant: t} : ({} as Record<string, string>);
};

/** Pessoas › Termos: textos que os membros assinam no app. Cada publicação cria uma nova versão; aceites antigos guardam o texto da versão assinada. */
export default function ConsentTemplates() {
  const [items, setItems] = useState<T[] | null>(null),
    [editing, setEditing] = useState<T | null>(null),
    [error, setError] = useState(''),
    [notice, setNotice] = useState(''),
    [busy, setBusy] = useState(false),
    [rev, setRev] = useState(0);
  useEffect(() => {
    const c = new AbortController();
    fetch('/api/consent/templates?' + new URLSearchParams(tenantQuery()), {cache: 'no-store', signal: c.signal})
      .then(async (r) => {
        const d = (await r.json()) as {items?: T[]; error?: string};
        if (!r.ok) throw Error(d.error || 'Indisponível.');
        setItems(d.items || []);
      })
      .catch((e) => {
        if (!c.signal.aborted) setError(e instanceof Error ? e.message : 'Indisponível.');
      });
    return () => c.abort();
  }, [rev]);
  async function save() {
    if (!editing || busy) return;
    setBusy(true);
    setError('');
    try {
      const r = await fetch('/api/consent/templates?' + new URLSearchParams(tenantQuery()), {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({kind: editing.kind, title: editing.title, body: editing.body}),
      });
      const d = (await r.json()) as {version?: number; error?: string};
      if (!r.ok) throw Error(d.error || 'Não confirmado.');
      setNotice(`Versão ${d.version} publicada. Novos aceites usam este texto; os anteriores continuam com o texto que foi assinado.`);
      setEditing(null);
      setRev((n) => n + 1);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Não confirmado.');
    } finally {
      setBusy(false);
    }
  }
  return (
    <section className="pd-card" style={{display: 'grid', gap: 12}}>
      <div>
        <p className="section-over">LGPD E IMAGEM</p>
        <h2 style={{margin: '4px 0'}}>Termos de consentimento</h2>
        <p>
          Os membros assinam pelo aplicativo (adultos em Meu perfil; responsáveis em Kids, para cada criança). Cada assinatura gera um PDF com código de
          verificação e impressão digital SHA-256.
        </p>
      </div>
      {notice && (
        <p className="program-notice" role="status">
          {notice}
        </p>
      )}
      {error && (
        <p className="program-error" role="alert">
          {error}
        </p>
      )}
      {!items && !error && <p>Consultando…</p>}
      {items?.map((t) =>
        editing?.kind === t.kind ? (
          <div key={t.kind} style={{display: 'grid', gap: 8, border: '1px solid var(--line,#dce6df)', borderRadius: 16, padding: 14}}>
            <b>{names[t.kind]}</b>
            <label>
              Título
              <input value={editing.title} maxLength={120} onChange={(e) => setEditing({...editing, title: e.target.value})} />
            </label>
            <label>
              Texto
              <textarea rows={12} value={editing.body} maxLength={8000} onChange={(e) => setEditing({...editing, body: e.target.value})} />
            </label>
            <div style={{display: 'flex', gap: 8, justifyContent: 'flex-end'}}>
              <button type="button" onClick={() => setEditing(null)}>
                Voltar
              </button>
              <button type="button" className="program-primary" disabled={busy} onClick={() => void save()}>
                {busy ? 'Publicando…' : 'Publicar nova versão'}
              </button>
            </div>
          </div>
        ) : (
          <div
            key={t.kind}
            style={{
              display: 'flex',
              gap: 12,
              alignItems: 'center',
              justifyContent: 'space-between',
              border: '1px solid var(--line,#dce6df)',
              borderRadius: 16,
              padding: 14,
            }}
          >
            <div>
              <b>{names[t.kind]}</b>
              <br />
              <small>
                {t.custom ? `Versão ${t.version} da igreja` : 'Texto padrão da Vinha'} · {t.title}
              </small>
            </div>
            <button
              type="button"
              onClick={() => {
                setNotice('');
                setEditing(t);
              }}
            >
              Editar texto
            </button>
          </div>
        ),
      )}
    </section>
  );
}
