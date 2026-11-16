'use client';
import {useEffect, useState} from 'react';
import {consentAudienceLabel, consentFixedNames, newConsentKind, type ConsentAudience} from '../shared/consent-terms';
import './consent-templates.css';

type T = {kind: string; version: number; title: string; body: string; custom: boolean};
type Custom = {kind: string; title: string; audience: ConsentAudience; version: number};
type Editing = {kind: string; title: string; body: string; audience: ConsentAudience; isNew: boolean};
const tenantQuery = () => {
  const t = typeof window === 'undefined' ? '' : new URLSearchParams(location.search).get('tenant');
  return t ? {tenant: t} : ({} as Record<string, string>);
};

/** Pessoas › Termos: os quatro termos padrão e os que a igreja criar (para adultos ou crianças). Cada publicação cria uma nova versão; aceites antigos guardam o texto assinado. */
export default function ConsentTemplates() {
  const [items, setItems] = useState<T[] | null>(null),
    [custom, setCustom] = useState<Custom[]>([]),
    [editing, setEditing] = useState<Editing | null>(null),
    [error, setError] = useState(''),
    [notice, setNotice] = useState(''),
    [busy, setBusy] = useState(false),
    [rev, setRev] = useState(0);
  const url = '/api/consent/templates?' + new URLSearchParams(tenantQuery());
  useEffect(() => {
    const c = new AbortController();
    fetch(url, {cache: 'no-store', signal: c.signal})
      .then(async (r) => {
        const d = (await r.json()) as {items?: T[]; custom?: Custom[]; error?: string};
        if (!r.ok) throw Error(d.error || 'Indisponível.');
        setItems(d.items || []);
        setCustom(d.custom || []);
      })
      .catch((e) => {
        if (!c.signal.aborted) setError(e instanceof Error ? e.message : 'Indisponível.');
      });
    return () => c.abort();
  }, [rev, url]);
  async function send(body: object, ok: string) {
    setBusy(true);
    setError('');
    try {
      const r = await fetch(url, {method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify(body)});
      const d = (await r.json()) as {version?: number; error?: string};
      if (!r.ok) throw Error(d.error || 'Não confirmado.');
      setNotice(ok.replace('{v}', String(d.version || '')));
      setEditing(null);
      setRev((n) => n + 1);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Não confirmado.');
    } finally {
      setBusy(false);
    }
  }
  const fixed = (items || []).filter((t) => !t.kind.startsWith('custom_'));
  const own = (items || []).filter((t) => t.kind.startsWith('custom_'));
  const audienceOf = (kind: string): ConsentAudience => custom.find((c) => c.kind === kind)?.audience || (kind.startsWith('kids_') ? 'kids' : 'adult');
  const editor = (e: Editing) => (
    <div className="ct-editor">
      <b>{e.isNew ? 'Novo termo' : consentFixedNames[e.kind] || e.title}</b>
      <label>
        Título
        <input value={e.title} maxLength={120} placeholder="Ex.: Autorização para o retiro" onChange={(x) => setEditing({...e, title: x.target.value})} />
      </label>
      {(e.isNew || e.kind.startsWith('custom_')) && (
        <fieldset className="ct-audience">
          <legend>Quem assina</legend>
          {(['adult', 'kids'] as ConsentAudience[]).map((a) => (
            <label key={a} className="program-check">
              <input type="radio" checked={e.audience === a} disabled={!e.isNew} onChange={() => setEditing({...e, audience: a})} />
              {consentAudienceLabel[a]}
            </label>
          ))}
        </fieldset>
      )}
      <label>
        Texto
        <textarea rows={12} value={e.body} maxLength={8000} onChange={(x) => setEditing({...e, body: x.target.value})} />
      </label>
      <small>{e.body.length} de 8.000 letras · mínimo 20</small>
      <div className="ct-actions">
        <button type="button" onClick={() => setEditing(null)}>
          Voltar
        </button>
        <button
          type="button"
          className="program-primary"
          disabled={busy}
          onClick={() =>
            void send(
              {kind: e.kind, title: e.title, body: e.body, ...(e.kind.startsWith('custom_') ? {audience: e.audience} : {})},
              e.isNew ? 'Termo criado. Ele já aparece no app para ser assinado.' : 'Versão {v} publicada. Novos aceites usam este texto; os anteriores continuam com o texto assinado.',
            )
          }
        >
          {busy ? 'Publicando…' : e.isNew ? 'Criar termo' : 'Publicar nova versão'}
        </button>
      </div>
    </div>
  );
  const row = (t: T, name: string, sub: string, canArchive: boolean) =>
    editing?.kind === t.kind ? (
      <div key={t.kind}>{editor(editing)}</div>
    ) : (
      <div key={t.kind} className="ct-row">
        <div>
          <b>{name}</b>
          <small>{sub}</small>
        </div>
        <div className="ct-actions">
          <button
            type="button"
            onClick={() => {
              setNotice('');
              setEditing({kind: t.kind, title: t.title, body: t.body, audience: audienceOf(t.kind), isNew: false});
            }}
          >
            Editar texto
          </button>
          {canArchive && (
            <button
              type="button"
              disabled={busy}
              onClick={() =>
                window.confirm('Tirar "' + t.title + '" do app? Quem já assinou continua com o documento válido.') &&
                void send({action: 'archive', kind: t.kind}, 'Termo retirado do app. Os aceites já feitos continuam válidos.')
              }
            >
              Retirar do app
            </button>
          )}
        </div>
      </div>
    );
  return (
    <section className="pd-card ct" aria-label="Termos de consentimento">
      <div className="ct-head">
        <div>
          <p className="section-over">LGPD E IMAGEM</p>
          <h2>Termos de consentimento</h2>
          <p>
            Os membros assinam pelo aplicativo: adultos em Meu perfil; responsáveis em Kids, para cada criança. Cada assinatura gera um PDF com código de
            verificação.
          </p>
        </div>
        <button
          type="button"
          className="program-primary"
          disabled={!!editing}
          onClick={() => {
            setNotice('');
            setEditing({kind: newConsentKind(), title: '', body: '', audience: 'adult', isNew: true});
          }}
        >
          ＋ Novo termo
        </button>
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
      {editing?.isNew && editor(editing)}
      {!items && !error && <p>Consultando…</p>}
      {!!items && (
        <>
          <h3 className="ct-sub">Termos da igreja</h3>
          {!own.length && !editing?.isNew && <p className="ct-empty">Nenhum termo criado ainda. Use “Novo termo” para retiros, passeios, viagens, uso de dados em eventos…</p>}
          {own.map((t) => row(t, t.title, consentAudienceLabel[audienceOf(t.kind)] + ' · versão ' + t.version, true))}
          <h3 className="ct-sub">Termos padrão</h3>
          {fixed.map((t) => row(t, consentFixedNames[t.kind] || t.title, (t.custom ? `Versão ${t.version} da igreja` : 'Texto padrão da Vinha') + ' · ' + t.title, false))}
        </>
      )}
    </section>
  );
}
