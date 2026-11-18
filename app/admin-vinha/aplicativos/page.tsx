'use client';
import {useCallback, useEffect, useMemo, useState} from 'react';
import AppIdentity from './AppIdentity';
import './apps.css';

type Status = 'contracted' | 'configuring' | 'testing' | 'store_review' | 'published' | 'paused';
type App = {
  organizationId: string;
  ministry: string;
  registrationCode: string | null;
  appName: string;
  primaryColor: string;
  accentColor: string;
  theme: 'light' | 'dark';
  contracted: boolean;
  configured: boolean;
  profile: string | null;
  displayName: string;
  status: Status;
  androidApplicationId: string | null;
  iosBundleId: string | null;
  notes: string;
  lastBuildAt: string | null;
  lastUpdateAt: string | null;
  version: number;
  updatedAt: string | null;
  pushReady: boolean;
};
type Draft = {displayName: string; status: Status; theme: 'light' | 'dark'; androidApplicationId: string; iosBundleId: string; notes: string};

/** Etapas da liberação do app de um ministério, na ordem em que acontecem. */
const appSteps: {key: Status; label: string; hint: string}[] = [
  {key: 'contracted', label: 'Contratado', hint: 'Ministério contratou o aplicativo.'},
  {key: 'configuring', label: 'Configurando', hint: 'Nome, tema e identidade definidos com o ministério.'},
  {key: 'testing', label: 'Em teste', hint: 'APK de teste entregue ao ministério.'},
  {key: 'store_review', label: 'Na loja', hint: 'Enviado para análise da Google Play / App Store.'},
  {key: 'published', label: 'Publicado', hint: 'Disponível para os membros nas lojas.'},
];
const statusLabel: Record<Status, string> = {
  contracted: 'Contratado',
  configuring: 'Configurando',
  testing: 'Em teste',
  store_review: 'Na loja',
  published: 'Publicado',
  paused: 'Pausado',
};
const date = (v: string | null) => (v ? new Date(v).toLocaleDateString('pt-BR', {day: '2-digit', month: 'short', year: 'numeric'}) : '—');
const toDraft = (a: App): Draft => ({
  displayName: a.displayName || '',
  status: a.configured ? a.status : 'configuring',
  theme: a.theme === 'light' ? 'light' : 'dark',
  androidApplicationId: a.androidApplicationId || '',
  iosBundleId: a.iosBundleId || '',
  notes: a.notes || '',
});

export default function CentralApps() {
  const [apps, setApps] = useState<App[]>([]),
    [canEdit, setCanEdit] = useState(false),
    [loading, setLoading] = useState(true),
    [selectedId, setSelectedId] = useState(''),
    [draft, setDraft] = useState<Draft | null>(null),
    [filter, setFilter] = useState<'all' | Status>('all'),
    [search, setSearch] = useState(''),
    [saving, setSaving] = useState(false),
    [notice, setNotice] = useState<{kind: 'ok' | 'error'; text: string} | null>(null);

  const load = useCallback(async (keep?: string) => {
    setLoading(true);
    try {
      const r = await fetch('/api/platform/apps', {cache: 'no-store'});
      const d = (await r.json().catch(() => ({}))) as {apps?: App[]; canEdit?: boolean; error?: string};
      if (!r.ok) throw new Error(d.error || 'Não foi possível carregar os aplicativos.');
      const list = d.apps || [];
      setApps(list);
      setCanEdit(Boolean(d.canEdit));
      const next = list.find((a) => a.organizationId === keep) || list[0];
      setSelectedId(next?.organizationId || '');
      setDraft(next ? toDraft(next) : null);
    } catch (e) {
      setNotice({kind: 'error', text: e instanceof Error ? e.message : 'Não foi possível carregar os aplicativos.'});
    } finally {
      setLoading(false);
    }
  }, []);
  useEffect(() => {
    const t = window.setTimeout(() => void load(), 0);
    return () => window.clearTimeout(t);
  }, [load]);

  const selected = apps.find((a) => a.organizationId === selectedId) || null;
  const counts = useMemo(() => {
    const c: Record<string, number> = {};
    for (const a of apps) {
      const s = a.configured ? a.status : 'contracted';
      c[s] = (c[s] || 0) + 1;
    }
    return c;
  }, [apps]);
  const visible = apps.filter((a) => {
    const s = a.configured ? a.status : 'contracted';
    if (filter !== 'all' && s !== filter) return false;
    const q = search.trim().toLowerCase();
    return (
      !q ||
      [a.ministry, a.displayName, a.profile, a.registrationCode].some((v) =>
        String(v || '')
          .toLowerCase()
          .includes(q),
      )
    );
  });

  function pick(a: App) {
    setSelectedId(a.organizationId);
    setDraft(toDraft(a));
    setNotice(null);
  }
  async function save(extra: Record<string, unknown> = {}, message = 'Aplicativo salvo.') {
    if (!selected || !draft) return;
    setSaving(true);
    setNotice(null);
    try {
      const r = await fetch('/api/platform/apps', {
        method: 'PATCH',
        headers: {'content-type': 'application/json'},
        body: JSON.stringify({organizationId: selected.organizationId, data: {version: selected.version, ...draft, ...extra}}),
      });
      const d = (await r.json().catch(() => ({}))) as {error?: string};
      if (!r.ok) throw new Error(d.error || 'Não foi possível salvar.');
      setNotice({kind: 'ok', text: message});
      await load(selected.organizationId);
    } catch (e) {
      setNotice({kind: 'error', text: e instanceof Error ? e.message : 'Não foi possível salvar.'});
    } finally {
      setSaving(false);
    }
  }

  const stepIndex = draft ? appSteps.findIndex((s) => s.key === draft.status) : -1;
  const checklist =
    selected && draft
      ? [
          {ok: selected.contracted, label: 'Aplicativo contratado no plano do ministério'},
          {ok: draft.displayName.trim().length >= 2, label: 'Nome no celular definido (até 30 letras)'},
          {ok: Boolean(selected.primaryColor), label: 'Logo e cores definidos pela Vinha (Identidade, abaixo)'},
          {ok: true, label: `Tema ${draft.theme === 'light' ? 'claro' : 'escuro'} combinado com o ministério`},
          {ok: selected.pushReady, label: 'Notificações (push) configuradas'},
          {ok: Boolean(draft.androidApplicationId || draft.iosBundleId), label: 'Identificador de loja (Android ou iOS)'},
        ]
      : [];
  const dirty = Boolean(selected && draft && JSON.stringify(toDraft(selected)) !== JSON.stringify(draft));

  return (
    <main className="apps-page">
      <header className="apps-head">
        <div>
          <small>APLICATIVOS</small>
          <h1>Apps dos ministérios</h1>
          <p>
            Libere, personalize e acompanhe o aplicativo de cada ministério. O código é o mesmo para todos: cada atualização chega a todos os apps mantendo
            nome, cores, logo e tema de cada um.
          </p>
        </div>
      </header>

      <div className="apps-kpis">
        <button type="button" className={filter === 'all' ? 'on' : ''} onClick={() => setFilter('all')}>
          <small>Todos</small>
          <b>{apps.length}</b>
        </button>
        {[...appSteps, {key: 'paused' as Status, label: 'Pausado', hint: ''}].map((s) => (
          <button type="button" key={s.key} className={filter === s.key ? 'on' : ''} onClick={() => setFilter(s.key)}>
            <small>{s.label}</small>
            <b>{counts[s.key] || 0}</b>
          </button>
        ))}
      </div>

      {notice && (
        <div className={'apps-notice ' + notice.kind} role={notice.kind === 'error' ? 'alert' : 'status'}>
          {notice.text}
        </div>
      )}

      <div className="apps-grid">
        <section className="apps-list" aria-label="Ministérios com aplicativo">
          <label className="apps-search">
            <span aria-hidden>⌕</span>
            <input value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Buscar ministério, perfil ou código" />
          </label>
          {loading && apps.length === 0 ? (
            <p className="apps-empty">Carregando aplicativos…</p>
          ) : visible.length === 0 ? (
            <p className="apps-empty">
              Nenhum ministério nesta etapa. Para liberar um app, marque “Aplicativo personalizado” na ficha do cliente em Ministérios.
            </p>
          ) : (
            visible.map((a) => (
              <button type="button" key={a.organizationId} className={'apps-item' + (a.organizationId === selectedId ? ' on' : '')} onClick={() => pick(a)}>
                <i style={{background: a.primaryColor}}>{(a.displayName || a.ministry).slice(0, 2).toUpperCase()}</i>
                <span>
                  <b>{a.displayName || a.ministry}</b>
                  <small>
                    {a.ministry}
                    {a.profile ? ` · perfil ${a.profile}` : ''}
                  </small>
                </span>
                <em className={'apps-status s-' + (a.configured ? a.status : 'contracted')}>{a.configured ? statusLabel[a.status] : 'A liberar'}</em>
              </button>
            ))
          )}
        </section>

        {selected && draft ? (
          <section className="apps-editor">
            <div className="apps-editor-head">
              <div>
                <small>{selected.registrationCode ? `CÓDIGO ${selected.registrationCode}` : 'MINISTÉRIO'}</small>
                <h2>{selected.ministry}</h2>
                <p>
                  Perfil do app: <code>{selected.profile || 'gerado ao liberar'}</code> · Última versão gerada: {date(selected.lastBuildAt)} · Última
                  atualização enviada: {date(selected.lastUpdateAt)}
                </p>
              </div>
              {!canEdit && <span className="apps-readonly">Somente consulta</span>}
            </div>

            <ol className="apps-steps" aria-label="Etapas da liberação">
              {appSteps.map((s, i) => (
                <li
                  key={s.key}
                  className={(draft.status === 'paused' ? '' : i < stepIndex ? 'done' : i === stepIndex ? 'now' : '') || undefined}
                  title={s.hint}
                >
                  <span>{i < stepIndex && draft.status !== 'paused' ? '✓' : i + 1}</span>
                  {s.label}
                </li>
              ))}
            </ol>

            {!selected.configured ? (
              <div className="apps-release">
                <div>
                  <b>Este ministério contratou o aplicativo.</b>
                  <p>
                    Ao liberar, a Vinha cria o perfil do app com o nome e o tema abaixo. Depois é só gerar o APK de teste pelo robô “Aplicativos dos
                    ministérios”.
                  </p>
                </div>
              </div>
            ) : null}

            <div className="apps-form">
              <div className="apps-fields">
                <label>
                  Nome no celular
                  <input maxLength={30} disabled={!canEdit} value={draft.displayName} onChange={(e) => setDraft({...draft, displayName: e.target.value})} />
                  <small>{draft.displayName.length}/30 · aparece embaixo do ícone</small>
                </label>
                <fieldset disabled={!canEdit}>
                  <legend>Tema do aplicativo</legend>
                  <div className="apps-theme">
                    {(['light', 'dark'] as const).map((t) => (
                      <label key={t} className={draft.theme === t ? 'on' : ''}>
                        <input type="radio" name="theme" checked={draft.theme === t} onChange={() => setDraft({...draft, theme: t})} />
                        <span className={'swatch ' + t} />
                        {t === 'light' ? 'Claro' : 'Escuro'}
                      </label>
                    ))}
                  </div>
                  <small>Escolhido com o ministério. Vale para todos os membros na próxima abertura do app.</small>
                </fieldset>
                {selected.configured && (
                  <label>
                    Etapa
                    <select disabled={!canEdit} value={draft.status} onChange={(e) => setDraft({...draft, status: e.target.value as Status})}>
                      {[...appSteps.slice(1), {key: 'paused' as Status, label: 'Pausado'}].map((s) => (
                        <option key={s.key} value={s.key}>
                          {s.label}
                        </option>
                      ))}
                    </select>
                  </label>
                )}
                <div className="apps-two">
                  <label>
                    Identificador Android
                    <input
                      disabled={!canEdit}
                      placeholder="br.com.ministerio.app"
                      value={draft.androidApplicationId}
                      onChange={(e) => setDraft({...draft, androidApplicationId: e.target.value.trim()})}
                    />
                  </label>
                  <label>
                    Identificador iOS
                    <input
                      disabled={!canEdit}
                      placeholder="br.com.ministerio.app"
                      value={draft.iosBundleId}
                      onChange={(e) => setDraft({...draft, iosBundleId: e.target.value.trim()})}
                    />
                  </label>
                </div>
                <label>
                  Anotações da equipe
                  <textarea
                    disabled={!canEdit}
                    rows={3}
                    maxLength={2000}
                    value={draft.notes}
                    onChange={(e) => setDraft({...draft, notes: e.target.value})}
                    placeholder="Contas das lojas, contato do ministério, combinados…"
                  />
                </label>
              </div>

              <div className="apps-preview" role="img" aria-label="Prévia do aplicativo">
                <div
                  className={'appx-phone ' + draft.theme}
                  style={{['--brand' as string]: selected.primaryColor, ['--accent' as string]: selected.accentColor}}
                >
                  <div className="appx-top">
                    <i>{(draft.displayName || selected.ministry).slice(0, 1).toUpperCase()}</i>
                    <b>{draft.displayName || selected.ministry}</b>
                  </div>
                  <div className="appx-hero">
                    <small>Próximo culto</small>
                    <b>Domingo · 19h</b>
                  </div>
                  <div className="appx-cards">
                    <span>Agenda</span>
                    <span>Células</span>
                    <span>Kids</span>
                    <span>Ofertas</span>
                  </div>
                  <div className="appx-tab">
                    <span className="on">Início</span>
                    <span>Agenda</span>
                    <span>Perfil</span>
                  </div>
                </div>
                <div className="appx-icon">
                  <i style={{background: selected.primaryColor}}>{(draft.displayName || selected.ministry).slice(0, 1).toUpperCase()}</i>
                  <small>{draft.displayName || selected.ministry}</small>
                </div>
              </div>
            </div>

            <div className="apps-check">
              <h3>Checklist de liberação</h3>
              <ul>
                {checklist.map((c) => (
                  <li key={c.label} className={c.ok ? 'ok' : ''}>
                    <span aria-hidden>{c.ok ? '✓' : '•'}</span>
                    {c.label}
                  </li>
                ))}
              </ul>
            </div>

            {canEdit && (
              <footer className="apps-actions">
                {selected.configured && (
                  <>
                    <button type="button" disabled={saving} onClick={() => void save({built: true}, 'Registrado: nova versão gerada.')}>
                      Registrar versão gerada
                    </button>
                    <button type="button" disabled={saving} onClick={() => void save({updated: true}, 'Registrado: atualização enviada.')}>
                      Registrar atualização enviada
                    </button>
                  </>
                )}
                <button
                  type="button"
                  className="primary"
                  disabled={saving || (selected.configured && !dirty)}
                  onClick={() => void save({}, selected.configured ? 'Aplicativo salvo.' : 'Aplicativo liberado. Gere o APK de teste pelo robô.')}
                >
                  {saving ? 'Salvando…' : selected.configured ? 'Salvar alterações' : 'Liberar aplicativo'}
                </button>
              </footer>
            )}

            <AppIdentity organizationId={selected.organizationId} onChanged={() => void load(selected.organizationId)} />
          </section>
        ) : (
          !loading && <section className="apps-editor apps-empty">Selecione um ministério para ver o aplicativo.</section>
        )}
      </div>

      <section className="apps-how">
        <h2>Como liberar e atualizar</h2>
        <ol>
          <li>
            <b>Contratação.</b> Marque “Aplicativo personalizado” na ficha do cliente (Ministérios). Ele aparece aqui como “A liberar”.
          </li>
          <li>
            <b>Personalização.</b> Somente a equipe da Vinha personaliza o app: nome no celular, tema, nome dentro do app, cores, logo, abertura (foto ou vídeo)
            e ícone, na seção Identidade. Depois clique em “Liberar aplicativo”.
          </li>
          <li>
            <b>APK de teste.</b> No GitHub, em Actions › “Aplicativos dos ministérios”, rode <i>gerar-teste</i> informando o perfil. Envie o link ao ministério
            e mude a etapa para “Em teste”.
          </li>
          <li>
            <b>Lojas.</b> Informe os identificadores Android/iOS, rode <i>gerar-loja</i> e marque “Na loja”. Após a aprovação, marque “Publicado”.
          </li>
          <li>
            <b>Atualizações.</b> Rode <i>atualizar</i> sem perfil: a mesma melhoria vai para todos os apps, cada um no seu canal, sem passar pela loja e sem
            perder a personalização.
          </li>
        </ol>
      </section>
    </main>
  );
}
