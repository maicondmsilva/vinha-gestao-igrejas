'use client';
import {useEffect, useMemo, useState, type FormEvent} from 'react';
import {ProgrammingModal as Modal, ProgrammingPager as Pager} from './ProgrammingTools';
import {settingsUrl} from './lib/settings-navigation';
import FieldError, {invalidProps} from './FieldError';
import {ApiError, fieldErrors, readApiError} from '../shared/contract/errors';
import {pushCampaignSchema} from '../shared/contract/push';
import './programming.css';
import './publishing.css';

type Audience = {
  roles?: string[];
  cells?: string[];
  groups?: string[];
  ageMin?: number;
  ageMax?: number;
  gender?: string;
  journey?: string[];
  tags?: string[];
  baptized?: boolean;
  event?: string;
};
type Link = {screen: string; id?: string};
type Stats = {recipients: number; delivered: number; failed: number; pending: number; opened: number};
type Campaign = {
  id: string;
  unit: string;
  title: string;
  body: string;
  link: Link;
  audience: Audience;
  targets: string[];
  source: string;
  status: 'draft' | 'scheduled' | 'sending' | 'sent' | 'cancelled';
  sendAt: string | null;
  recurrence: 'none' | 'daily' | 'weekly' | 'monthly';
  recurrenceUntil: string | null;
  nextRunAt: string | null;
  runs: number;
  version: number;
  createdAt: string;
  author: string;
  stats: Stats;
};
type Options = {
  units: {id: string; name: string}[];
  cells: {id: string; name: string; unit: string}[];
  groups: {id: string; name: string; kind: string; unit: string}[];
  events: {id: string; title: string; startsAt: string}[];
  journey: string[];
  tags: string[];
  genders: string[];
};
type Page = {total: number; page: number; size: number; items: Campaign[]};

const statusLabel: Record<Campaign['status'], string> = {
  draft: 'Rascunho',
  scheduled: 'Agendada',
  sending: 'Enviando',
  sent: 'Enviada',
  cancelled: 'Cancelada',
};
const recurrenceLabel: Record<Campaign['recurrence'], string> = {none: 'Uma vez', daily: 'Todo dia', weekly: 'Toda semana', monthly: 'Todo mês'};
const screens: [string, string][] = [
  ['inbox', 'Caixa de entrada do app'],
  ['agenda', 'Agenda'],
  ['event', 'Um evento específico'],
  ['giving', 'Contribuições'],
  ['services', 'Serviços'],
];
const roles: [string, string][] = [
  ['member', 'Membros'],
  ['leader', 'Líderes'],
  ['secretary', 'Secretaria'],
  ['pastor', 'Pastores'],
  ['admin', 'Administração'],
];
const newRequest = () => crypto.randomUUID();
const localInput = (iso: string | null) => {
  if (!iso) return '';
  const d = new Date(iso);
  return new Date(d.getTime() - d.getTimezoneOffset() * 60000).toISOString().slice(0, 16);
};
const when = (iso: string | null) => (iso ? new Date(iso).toLocaleString('pt-BR', {dateStyle: 'short', timeStyle: 'short'}) : '—');

async function api<T = {ok?: boolean}>(body: unknown): Promise<T> {
  const r = await fetch(settingsUrl('/api/push/campaigns'), {method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify(body)});
  const d = (await r.json().catch(() => ({}))) as T & {error?: string};
  if (!r.ok) throw new ApiError(readApiError(d, 'Sem confirmação.'), r.status);
  return d;
}

export default function PushCampaigns({unit}: {unit: string}) {
  const [data, setData] = useState<Page | null>(null),
    [options, setOptions] = useState<Options | null>(null),
    [status, setStatus] = useState(''),
    [page, setPage] = useState(1),
    [revision, setRevision] = useState(0),
    [loading, setLoading] = useState(true),
    [error, setError] = useState(''),
    [notice, setNotice] = useState(''),
    [editor, setEditor] = useState<Campaign | null | false>(false),
    [detail, setDetail] = useState<Campaign | null>(null),
    [automations, setAutomations] = useState(false);
  useEffect(() => {
    let alive = true;
    const q = new URLSearchParams({unit, page: String(page), size: '20', ...(status ? {status} : {})});
    fetch(settingsUrl('/api/push/campaigns?' + q))
      .then(async (r) => {
        const d = (await r.json()) as Page & {error?: string};
        if (!r.ok) throw Error(d.error || 'Não foi possível carregar.');
        if (alive) {
          setData(d);
          setError('');
        }
      })
      .catch((e) => alive && setError((e as Error).message))
      .finally(() => alive && setLoading(false));
    return () => {
      alive = false;
    };
  }, [unit, page, status, revision]);
  useEffect(() => {
    fetch(settingsUrl('/api/push/campaigns?' + new URLSearchParams({unit, options: '1'})))
      .then((r) => (r.ok ? (r.json() as Promise<Options>) : null))
      .then((d) => {
        if (d) setOptions(d);
      })
      .catch(() => undefined);
  }, [unit]);
  const refresh = () => (setLoading(true), setRevision((n) => n + 1));
  async function cancel(c: Campaign) {
    if (!confirm('Cancelar esta campanha? Mensagens ainda na fila não serão enviadas.')) return;
    try {
      await api({unit, action: 'cancel', id: c.id, version: c.version, data: {}});
      setNotice('Campanha cancelada.');
      setDetail(null);
      refresh();
    } catch (e) {
      setError((e as Error).message);
    }
  }
  return (
    <div className="content program-page publishing-page">
      <div className="program-breadcrumb">
        Comunicação <span>/</span> Push para o app
      </div>
      <div className="program-heading">
        <div>
          <p className="section-over">Notificações no celular</p>
          <h1>Campanhas de push</h1>
          <p>Escreva a mensagem, escolha quem recebe e quando. O envio começa em até um minuto, inclusive para várias igrejas.</p>
        </div>
        <div className="program-actions">
          <button type="button" disabled={loading} onClick={refresh}>
            ↻ Atualizar
          </button>
          <button type="button" onClick={() => setAutomations(true)}>
            ⚙ Automações
          </button>
          <button type="button" className="program-primary" disabled={!options} onClick={() => setEditor(null)}>
            ＋ Nova campanha
          </button>
        </div>
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
      <div className="program-filters publishing-filters-compact">
        <label>
          Situação
          <select value={status} onChange={(e) => (setPage(1), setLoading(true), setStatus(e.target.value))}>
            <option value="">Todas</option>
            {Object.entries(statusLabel).map(([k, v]) => (
              <option key={k} value={k}>
                {v}
              </option>
            ))}
          </select>
        </label>
      </div>
      <section className="program-card" aria-busy={loading}>
      <div className="program-card-title">
        <h2>Campanhas</h2>
        {data && <span>{data.total} {data.total === 1 ? 'campanha' : 'campanhas'}</span>}
      </div>
      {loading && !data ? (
        <div className="program-empty" role="status">
          Carregando campanhas…
        </div>
      ) : !data?.items.length ? (
        <div className="program-empty">
          <h3>{status ? 'Nenhuma campanha nesta situação' : 'Nenhuma campanha ainda'}</h3>
          <p>Crie a primeira e veja quantas pessoas ela alcança antes de enviar.</p>
        </div>
      ) : (
        <div className="program-table-wrap">
          <table className="program-table">
            <thead>
              <tr>
                <th>Campanha</th>
                <th>Situação</th>
                <th>Quando</th>
                <th>Alcance</th>
                <th>Aberturas</th>
                <th>Ações</th>
              </tr>
            </thead>
            <tbody>
              {data.items.map((c) => (
                <tr key={c.id}>
                  <td>
                    <strong>{c.title}</strong>
                    <small>
                      {c.body.slice(0, 80)}
                      {c.body.length > 80 ? '…' : ''}
                    </small>
                  </td>
                  <td data-label="Situação">
                    <span className={'program-badge push-' + c.status}>{statusLabel[c.status]}</span>
                  </td>
                  <td className="publishing-date" data-label="Quando">
                    <span>
                      {c.status === 'scheduled' ? when(c.nextRunAt) : when(c.sendAt)}
                      {c.recurrence !== 'none' && <small>{recurrenceLabel[c.recurrence]}</small>}
                    </span>
                  </td>
                  <td className="publishing-date" data-label="Alcance">{c.stats.recipients ? `${c.stats.delivered} de ${c.stats.recipients}` : '—'}</td>
                  <td className="publishing-date" data-label="Aberturas">{c.stats.delivered ? `${c.stats.opened} (${Math.round((100 * c.stats.opened) / c.stats.delivered)}%)` : '—'}</td>
                  <td>
                    <div className="publishing-row-actions">
                      <button type="button" onClick={() => setDetail(c)}>
                        Detalhes
                      </button>
                      {['draft', 'scheduled'].includes(c.status) && c.runs === 0 && (
                        <button type="button" onClick={() => setEditor(c)}>
                          Editar
                        </button>
                      )}
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      {data && data.total > data.size && <Pager page={data.page} total={data.total} size={data.size} change={(p) => (setLoading(true), setPage(p))} disabled={loading} />}
      </section>
      {editor !== false && options && (
        <CampaignEditor
          unit={unit}
          options={options}
          campaign={editor}
          close={() => setEditor(false)}
          saved={(message) => (setEditor(false), setNotice(message), refresh())}
        />
      )}
      {automations && <Automations unit={unit} close={() => setAutomations(false)} saved={(m) => (setAutomations(false), setNotice(m))} />}
      {detail && (
        <Modal title={detail.title} close={() => setDetail(null)}>
          <div className="program-detail">
            <p>{detail.body}</p>
            <dl className="publishing-facts">
              <div>
                <dt>Situação</dt>
                <dd>
                  <span className={'program-badge push-' + detail.status}>{statusLabel[detail.status]}</span>
                </dd>
              </div>
              <div>
                <dt>Repetição</dt>
                <dd>{recurrenceLabel[detail.recurrence]}</dd>
              </div>
              {detail.status === 'scheduled' && (
                <div>
                  <dt>Próximo envio</dt>
                  <dd>{when(detail.nextRunAt)}</dd>
                </div>
              )}
              <div>
                <dt>Destinatários</dt>
                <dd>{detail.stats.recipients}</dd>
              </div>
              <div>
                <dt>Entregues</dt>
                <dd>{detail.stats.delivered}</dd>
              </div>
              <div>
                <dt>Na fila</dt>
                <dd>{detail.stats.pending}</dd>
              </div>
              <div>
                <dt>Falhas</dt>
                <dd>{detail.stats.failed}</dd>
              </div>
              <div>
                <dt>Aberturas</dt>
                <dd>{detail.stats.opened}</dd>
              </div>
            </dl>
            <p>
              <small>
                Criada por {detail.author} em {when(detail.createdAt)}. Falhas incluem aparelhos que desinstalaram o app; eles deixam de receber automaticamente.
              </small>
            </p>
            {!['sent', 'cancelled'].includes(detail.status) && (
              <footer className="program-form-footer">
                <button type="button" className="publishing-quiet" onClick={() => void cancel(detail)}>
                  Cancelar campanha
                </button>
              </footer>
            )}
          </div>
        </Modal>
      )}
    </div>
  );
}

function CampaignEditor({unit, options, campaign, close, saved}: {unit: string; options: Options; campaign: Campaign | null; close: () => void; saved: (m: string) => void}) {
  const [title, setTitle] = useState(campaign?.title || ''),
    [body, setBody] = useState(campaign?.body || ''),
    [link, setLink] = useState<Link>(campaign?.link || {screen: 'inbox'}),
    [targets, setTargets] = useState<string[]>(campaign?.targets || (options.units.some((u) => u.id === unit) ? [unit] : [])),
    [audience, setAudience] = useState<Audience>(campaign?.audience || {}),
    [mode, setMode] = useState<'now' | 'schedule' | 'draft'>(campaign?.status === 'draft' ? 'draft' : campaign ? 'schedule' : 'now'),
    [sendAt, setSendAt] = useState(localInput(campaign?.sendAt || null)),
    [recurrence, setRecurrence] = useState<Campaign['recurrence']>(campaign?.recurrence || 'none'),
    [until, setUntil] = useState(localInput(campaign?.recurrenceUntil || null)),
    [reach, setReach] = useState<{devices: number; people: number} | null>(null),
    [busy, setBusy] = useState(false),
    [error, setError] = useState(''),
    [fields, setFields] = useState<Record<string, string>>({}),
    [request] = useState(newRequest);
  const visibleCells = useMemo(() => options.cells.filter((c) => targets.includes(c.unit)), [options.cells, targets]),
    visibleGroups = useMemo(() => options.groups.filter((g) => targets.includes(g.unit)), [options.groups, targets]);
  const toggle = (list: string[] | undefined, value: string) => {
    const next = (list || []).includes(value) ? (list || []).filter((v) => v !== value) : [...(list || []), value];
    return next.length ? next : undefined;
  };
  const setFilter = <K extends keyof Audience>(key: K, value: Audience[K] | undefined) =>
    setAudience((a) => {
      const next = {...a};
      if (value === undefined || value === '' || (Array.isArray(value) && !value.length)) delete next[key];
      else next[key] = value;
      return next;
    });
  // Reach preview follows the audience as it is edited.
  useEffect(() => {
    if (!targets.length) return;
    const timer = window.setTimeout(() => {
      api<{devices: number; people: number}>({unit, action: 'preview', data: {targets, audience}})
        .then((d) => setReach(d))
        .catch(() => setReach(null));
    }, 400);
    return () => window.clearTimeout(timer);
  }, [unit, targets, audience]);
  async function submit(e: FormEvent) {
    e.preventDefault();
    if (busy) return;
    setBusy(true);
    setError('');
    try {
      const data = {
        title: title.trim(),
        body: body.trim(),
        link: link.screen === 'event' ? link : {screen: link.screen},
        targets,
        audience,
        mode,
        sendAt: mode === 'schedule' && Number.isFinite(Date.parse(sendAt)) ? new Date(sendAt).toISOString() : '',
        recurrence,
        recurrenceUntil: recurrence !== 'none' && Number.isFinite(Date.parse(until)) ? new Date(until).toISOString() : '',
        ...(campaign ? {} : {request}),
      };
      // Same rules as the API and Vinha Equipe: point at the input before the round trip.
      const check = pushCampaignSchema.safeParse(data);
      if (!check.success) {
        const f = fieldErrors(check.error);
        setFields(f);
        setError(Object.values(f)[0] || 'Revise os campos destacados.');
        return;
      }
      setFields({});
      await api(campaign ? {unit, action: 'edit', id: campaign.id, version: campaign.version, data} : {unit, action: 'create', data});
      saved(mode === 'now' ? 'Campanha na fila de envio. Os primeiros avisos chegam em até um minuto.' : mode === 'schedule' ? 'Campanha agendada.' : 'Rascunho salvo.');
    } catch (x) {
      setError((x as Error).message);
      setFields(x instanceof ApiError ? x.fields : {});
    } finally {
      setBusy(false);
    }
  }
  return (
    <Modal title={campaign ? 'Editar campanha' : 'Nova campanha de push'} close={close} busy={busy}>
      <form className="program-form" onSubmit={submit}>
        <div className="publishing-editor-grid">
          <label>
            Título ({title.length}/65)
            <input required minLength={2} maxLength={65} value={title} onChange={(e) => setTitle(e.target.value)} placeholder="Culto de domingo" {...invalidProps(fields, 'title')} />
            <FieldError fields={fields} name="title" />
          </label>
          <label>
            Mensagem ({body.length}/240)
            <textarea required minLength={2} maxLength={240} rows={3} value={body} onChange={(e) => setBody(e.target.value)} placeholder="Hoje às 19h. Traga sua família!" {...invalidProps(fields, 'body')} />
            <FieldError fields={fields} name="body" />
          </label>
          <div className="push-preview" aria-label="Prévia da notificação">
            <b>{title || 'Título da notificação'}</b>
            <span>{body || 'O texto aparece assim na tela do celular.'}</span>
          </div>
          <label>
            Ao tocar, abrir
            <select value={link.screen} onChange={(e) => setLink({screen: e.target.value})}>
              {screens.map(([k, v]) => (
                <option key={k} value={k}>
                  {v}
                </option>
              ))}
            </select>
          </label>
          {link.screen === 'event' && (
            <label>
              Evento
              <select required value={link.id || ''} onChange={(e) => setLink({screen: 'event', id: e.target.value})} {...invalidProps(fields, 'link.id')}>
                <option value="">Escolha…</option>
                {options.events.map((ev) => (
                  <option key={ev.id} value={ev.id}>
                    {ev.title} · {when(ev.startsAt)}
                  </option>
                ))}
              </select>
              <FieldError fields={fields} name="link.id" />
            </label>
          )}
        </div>

        <fieldset>
          <legend>Igrejas que recebem</legend>
          <div className="publishing-unit-choices">
            {options.units.map((u) => (
              <label className="program-check" key={u.id}>
                <input type="checkbox" checked={targets.includes(u.id)} onChange={() => setTargets((t) => (t.includes(u.id) ? t.filter((x) => x !== u.id) : [...t, u.id]))} />
                <span>{u.name}</span>
              </label>
            ))}
          </div>
          <FieldError fields={fields} name="targets" />
        </fieldset>

        <fieldset>
          <legend>Quem recebe (opcional; sem filtros, todos com o app)</legend>
          <div className="program-form-grid">
            <label>
              Idade mínima
              <input type="number" min={0} max={120} value={audience.ageMin ?? ''} onChange={(e) => setFilter('ageMin', e.target.value === '' ? undefined : Number(e.target.value))} />
            </label>
            <label>
              Idade máxima
              <input type="number" min={0} max={120} value={audience.ageMax ?? ''} onChange={(e) => setFilter('ageMax', e.target.value === '' ? undefined : Number(e.target.value))} {...invalidProps(fields, 'audience.ageMax')} />
              <FieldError fields={fields} name="audience.ageMax" />
            </label>
            {!!options.genders.length && (
              <label>
                Gênero
                <select value={audience.gender || ''} onChange={(e) => setFilter('gender', e.target.value || undefined)}>
                  <option value="">Todos</option>
                  {options.genders.map((g) => (
                    <option key={g} value={g}>
                      {g}
                    </option>
                  ))}
                </select>
              </label>
            )}
            <label>
              Batismo
              <select value={audience.baptized === undefined ? '' : String(audience.baptized)} onChange={(e) => setFilter('baptized', e.target.value === '' ? undefined : e.target.value === 'true')}>
                <option value="">Todos</option>
                <option value="true">Batizados</option>
                <option value="false">Não batizados</option>
              </select>
            </label>
            {!!options.events.length && (
              <label>
                Inscritos no evento
                <select value={audience.event || ''} onChange={(e) => setFilter('event', e.target.value || undefined)}>
                  <option value="">Qualquer pessoa</option>
                  {options.events.map((ev) => (
                    <option key={ev.id} value={ev.id}>
                      {ev.title}
                    </option>
                  ))}
                </select>
              </label>
            )}
          </div>
          <Chips label="Função no ministério" items={roles.map(([id, name]) => ({id, name}))} selected={audience.roles} toggle={(v) => setFilter('roles', toggle(audience.roles, v))} />
          <Chips label="Células" items={visibleCells} selected={audience.cells} toggle={(v) => setFilter('cells', toggle(audience.cells, v))} />
          <Chips label="Ministérios e departamentos" items={visibleGroups} selected={audience.groups} toggle={(v) => setFilter('groups', toggle(audience.groups, v))} />
          <Chips label="Etapa da jornada" items={options.journey.map((j) => ({id: j, name: j}))} selected={audience.journey} toggle={(v) => setFilter('journey', toggle(audience.journey, v))} />
          <Chips label="Marcadores" items={options.tags.map((t) => ({id: t, name: t}))} selected={audience.tags} toggle={(v) => setFilter('tags', toggle(audience.tags, v))} />
          <p className="publishing-destination-summary" aria-live="polite">
            {!targets.length
              ? 'Escolha ao menos uma igreja.'
              : reach
                ? `Alcance agora: ${reach.people} ${reach.people === 1 ? 'pessoa' : 'pessoas'} em ${reach.devices} ${reach.devices === 1 ? 'aparelho' : 'aparelhos'} com o app.`
                : 'Calculando alcance…'}
          </p>
        </fieldset>

        <fieldset>
          <legend>Quando enviar</legend>
          <div className="program-form-grid">
            <label>
              Envio
              <select value={mode} onChange={(e) => setMode(e.target.value as typeof mode)}>
                <option value="now">Agora</option>
                <option value="schedule">Agendar</option>
                <option value="draft">Salvar como rascunho</option>
              </select>
            </label>
            {mode === 'schedule' && (
              <label>
                Data e hora
                <input type="datetime-local" required value={sendAt} onChange={(e) => setSendAt(e.target.value)} {...invalidProps(fields, 'sendAt')} />
                <FieldError fields={fields} name="sendAt" />
              </label>
            )}
            {mode !== 'draft' && (
              <label>
                Repetir
                <select value={recurrence} onChange={(e) => setRecurrence(e.target.value as Campaign['recurrence'])}>
                  {Object.entries(recurrenceLabel).map(([k, v]) => (
                    <option key={k} value={k}>
                      {v}
                    </option>
                  ))}
                </select>
              </label>
            )}
            {mode !== 'draft' && recurrence !== 'none' && (
              <label>
                Repetir até (opcional)
                <input type="datetime-local" value={until} onChange={(e) => setUntil(e.target.value)} {...invalidProps(fields, 'recurrenceUntil')} />
                <FieldError fields={fields} name="recurrenceUntil" />
              </label>
            )}
          </div>
        </fieldset>
        {error && (
          <p className="program-error" role="alert">
            {error}
          </p>
        )}
        <footer className="program-form-footer">
          <button type="button" onClick={close} disabled={busy}>
            Voltar
          </button>
          <button type="submit" className="program-primary" disabled={busy || !targets.length}>
            {busy ? 'Salvando…' : mode === 'now' ? 'Enviar agora' : mode === 'schedule' ? 'Agendar envio' : 'Salvar rascunho'}
          </button>
        </footer>
      </form>
    </Modal>
  );
}

function Chips({label, items, selected, toggle}: {label: string; items: {id: string; name: string}[]; selected?: string[]; toggle: (id: string) => void}) {
  if (!items.length) return null;
  return (
    <div className="push-chips" role="group" aria-label={label}>
      <span>{label}</span>
      <div>
        {items.map((i) => (
          <button type="button" key={i.id} aria-pressed={!!selected?.includes(i.id)} onClick={() => toggle(i.id)}>
            {i.name}
          </button>
        ))}
      </div>
    </div>
  );
}

type Automation = {birthdays: boolean; birthdayTitle: string; birthdayBody: string; livePush: boolean; version: number; canEdit: boolean};

/** Automatic pushes: birthdays (daily at 9h) and the start of a YouTube live. */
function Automations({unit, close, saved}: {unit: string; close: () => void; saved: (m: string) => void}) {
  const [a, setA] = useState<Automation | null>(null),
    [busy, setBusy] = useState(false),
    [error, setError] = useState('');
  useEffect(() => {
    fetch(settingsUrl('/api/push/automations?' + new URLSearchParams({unit})))
      .then(async (r) => {
        const d = (await r.json()) as Automation & {error?: string};
        if (!r.ok) throw Error(d.error || 'Automações indisponíveis.');
        setA(d);
      })
      .catch((e) => setError((e as Error).message));
  }, [unit]);
  async function submit(e: FormEvent) {
    e.preventDefault();
    if (!a || busy) return;
    setBusy(true);
    setError('');
    try {
      const r = await fetch(settingsUrl('/api/push/automations'), {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({unit, version: a.version, data: {birthdays: a.birthdays, livePush: a.livePush, birthdayTitle: a.birthdayTitle, birthdayBody: a.birthdayBody}}),
      });
      const d = await r.json().catch(() => ({}));
      if (!r.ok) throw Error((d as {error?: string}).error || 'Sem confirmação.');
      saved('Automações salvas.');
    } catch (x) {
      setError((x as Error).message);
    } finally {
      setBusy(false);
    }
  }
  return (
    <Modal title="Automações de push" close={close} busy={busy}>
      {!a ? (
        <p className={error ? 'program-error' : 'program-empty'}>{error || 'Carregando…'}</p>
      ) : (
        <form className="program-form push-automation" onSubmit={submit}>
          <fieldset disabled={!a.canEdit || busy}>
            <label className="program-check">
              <input type="checkbox" checked={a.livePush} onChange={(e) => setA({...a, livePush: e.target.checked})} />
              <span>Avisar quando uma transmissão do YouTube começar (a live muda para &ldquo;ao vivo&rdquo; sozinha)</span>
            </label>
            <label className="program-check">
              <input type="checkbox" checked={a.birthdays} onChange={(e) => setA({...a, birthdays: e.target.checked})} />
              <span>Enviar parabéns no aniversário, todo dia às 9h, para quem tem o app</span>
            </label>
            {a.birthdays && (
              <>
                <label>
                  Título ({a.birthdayTitle.length}/65)
                  <input required minLength={2} maxLength={65} value={a.birthdayTitle} onChange={(e) => setA({...a, birthdayTitle: e.target.value})} />
                </label>
                <label>
                  Mensagem ({a.birthdayBody.length}/240)
                  <textarea required minLength={2} maxLength={240} rows={3} value={a.birthdayBody} onChange={(e) => setA({...a, birthdayBody: e.target.value})} />
                </label>
              </>
            )}
          </fieldset>
          {!a.canEdit && <p className="publishing-help">Somente dono, pastor ou administração altera as automações.</p>}
          {error && (
            <p className="program-error" role="alert">
              {error}
            </p>
          )}
          <footer className="program-form-footer">
            <button type="button" onClick={close} disabled={busy}>
              Voltar
            </button>
            {a.canEdit && (
              <button type="submit" className="program-primary" disabled={busy}>
                {busy ? 'Salvando…' : 'Salvar automações'}
              </button>
            )}
          </footer>
        </form>
      )}
    </Modal>
  );
}
