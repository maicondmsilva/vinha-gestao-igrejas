'use client';
import {useEffect, useRef, useState, type FormEvent, type ReactNode} from 'react';
import {formatInZone} from '../shared/timezone';
import {conflictLabels, presenceStatus, responseStatus, serviceStatus} from '../shared/scale-operations';
type Slot = {
  team_id: string;
  role_id: string;
  ordinal: number;
  member_id: string | null;
  teamName: string;
  roleName: string;
  name: string;
  conflicts: string[];
  canAssign: boolean;
  canPublish: boolean;
  hasAccount: boolean;
};
type Invite = {
  id: string;
  version: number;
  role_id: string;
  ordinal: number;
  response: string;
  active: boolean;
  presence: string;
  name: string;
  role: string;
  team: string;
  deadline: string;
  ended_reason: string;
  replied_at: string;
  reply_reason: string;
};
type Suggestion = {id: string; name: string; conflicts: string[]; recent: number};
type Request = {id: string; invite_id: string; version: number; state: string; suggested_member: string | null; suggested_name: string; note: string};
type View = {
  service: {id: string; title: string; status: string; version: number; timezone: string; arrival_at: string; ends_at: string};
  token: string;
  affected: number;
  confirmed: number;
  canPublish: boolean;
  slots: Slot[];
  invites: Invite[];
  requests: Request[];
};
function endpoint(unit: string, action: string, data: Record<string, string> = {}) {
  const p = new URLSearchParams({unit, action, ...data});
  const tenant = new URLSearchParams(location.search).get('tenant');
  if (tenant) p.set('tenant', tenant);
  return '/api/scales-operations?' + p;
}
async function read<T>(unit: string, action: string, data: Record<string, string>, signal?: AbortSignal) {
  const r = await fetch(endpoint(unit, action, data), {signal, cache: 'no-store'}),
    v = (await r.json()) as T & {error?: string};
  if (!r.ok) throw Error(v.error || 'Não foi possível consultar.');
  return v;
}
async function write(unit: string, action: string, data: Record<string, unknown>) {
  const r = await fetch(endpoint(unit, action), {method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({unit, action, data})}),
    v = (await r.json()) as {error?: string; ok?: boolean};
  if (!r.ok || !v.ok) throw Error(v.error || 'Resultado não confirmado. Atualize a consulta.');
  return v;
}
function OperationDialog({title, children, close, busy}: {title: string; children: ReactNode; close: () => void; busy: boolean}) {
  const ref = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    const before = document.activeElement as HTMLElement;
    ref.current?.showModal();
    return () => before?.focus();
  }, []);
  return (
    <dialog
      ref={ref}
      className="sp-modal"
      aria-label={title}
      onCancel={(e) => {
        e.preventDefault();
        if (!busy) close();
      }}
    >
      <header>
        <h2>{title}</h2>
        <button type="button" aria-label="Fechar operação" disabled={busy} onClick={close}>
          ×
        </button>
      </header>
      {children}
    </dialog>
  );
}
export default function ScalesOperations({unitId, serviceId, onChanged}: {unitId: string; serviceId: string; onChanged: () => void}) {
  const [data, setData] = useState<View | null>(null),
    [scope, setScope] = useState('current'),
    [revision, setRevision] = useState(0),
    [error, setError] = useState(''),
    [notice, setNotice] = useState(''),
    [busy, setBusy] = useState(false),
    [form, setForm] = useState<{action: string; invite?: Invite; slot?: Slot; request?: Request} | null>(null),
    [reason, setReason] = useState(''),
    [override, setOverride] = useState(false),
    [candidate, setCandidate] = useState(''),
    [query, setQuery] = useState(''),
    [candidates, setCandidates] = useState<Suggestion[]>([]),
    [candidatePage, setCandidatePage] = useState(1),
    [response, setResponse] = useState('accepted'),
    [presence, setPresence] = useState('present');
  const request = useRef('');
  useEffect(() => {
    const c = new AbortController();
    setData(null);
    setError('');
    read<View>(unitId, 'view', {service: serviceId, scope}, c.signal)
      .then(setData)
      .catch((e) => {
        if (!c.signal.aborted) setError(e.message);
      });
    return () => c.abort();
  }, [unitId, serviceId, scope, revision]);
  function open(action: string, invite?: Invite, slot?: Slot, req?: Request) {
    request.current = crypto.randomUUID();
    setForm({action, invite, slot, request: req});
    setReason('');
    setOverride(false);
    setCandidate(req?.suggested_member || '');
    setQuery('');
    setCandidates([]);
    setCandidatePage(1);
    setError('');
    setNotice('');
  }
  async function find(page = 1) {
    if (!data || !form) return;
    setBusy(true);
    try {
      const r = await read<{items: Suggestion[]}>(unitId, 'suggest', {
        service: serviceId,
        role: form.invite?.role_id || form.slot!.role_id,
        ordinal: String(form.invite?.ordinal || form.slot!.ordinal),
        search: query,
        page: String(page),
      });
      setCandidates(r.items);
      setCandidatePage(page);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  async function submit(e: FormEvent) {
    e.preventDefault();
    if (!data || !form || busy) return;
    setBusy(true);
    setError('');
    try {
      await write(unitId, form.action, {
        service: serviceId,
        scope,
        token: data.token,
        request: request.current,
        id: form.request?.id || form.invite?.id,
        version: form.request?.version || form.invite?.version || data.service.version,
        role: form.slot?.role_id,
        ordinal: form.slot?.ordinal,
        reason,
        override,
        member: candidate || undefined,
        response: form.action === 'reply' ? response : undefined,
        presence: form.action === 'presence' ? presence : undefined,
        decision: form.action === 'decision' ? 'approve' : undefined,
      });
      setForm(null);
      setNotice(
        form.action === 'publish'
          ? 'Escala publicada. Convites disponíveis na conta dos integrantes; isto não comprova entrega de e-mail ou push.'
          : form.action === 'revise'
            ? 'Revisão aberta em rascunho. Respostas anteriores preservadas; a próxima publicação gerará novos convites.'
            : form.action === 'replace' || form.action === 'decision' || form.action === 'fill'
              ? 'Atribuição atualizada. O novo convite aguarda a resposta da pessoa.'
              : 'Operação registrada no histórico.',
      );
      setRevision((n) => n + 1);
      onChanged();
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  async function reject(c: Request) {
    if (!data || reason.trim().length < 5) {
      setError('Informe ao menos 5 caracteres para recusar a solicitação.');
      return;
    }
    setBusy(true);
    try {
      await write(unitId, 'decision', {service: serviceId, id: c.id, version: c.version, decision: 'reject', reason, request: request.current});
      setForm(null);
      setRevision((n) => n + 1);
      onChanged();
      setNotice('Solicitação recusada e decisão registrada.');
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  if (!data)
    return (
      <section className="so-panel">
        {error ? (
          <p role="alert" className="sp-error">
            {error}
          </p>
        ) : (
          <p role="status">Consultando convites e conflitos…</p>
        )}
        <button type="button" className="secondary" onClick={() => setRevision((n) => n + 1)}>
          Atualizar operação
        </button>
      </section>
    );
  const labels: Record<string, string> = {
    publish: 'Publicar escala',
    revise: 'Preparar revisão',
    cancel: 'Cancelar escala publicada',
    close: 'Encerrar serviço',
    reply: 'Registrar resposta pela liderança',
    presence: 'Registrar presença',
    replace: 'Substituir integrante',
    decision: 'Decidir pedido de substituição',
    fill: 'Preencher vaga',
  };
  const target = form?.invite?.name || form?.slot?.roleName || data.service.title;
  return (
    <section className="so-panel" aria-label="Convites e operação">
      <header className="sp-heading">
        <div>
          <h3>Convites e operação</h3>
          <p>{serviceStatus[data.service.status]} · presença é independente da confirmação.</p>
        </div>
        <button type="button" className="secondary" disabled={busy} onClick={() => setRevision((n) => n + 1)}>
          Atualizar operação
        </button>
      </header>
      {notice && (
        <p role="status" className="sp-notice">
          {notice}
        </p>
      )}
      {error && !form && (
        <p role="alert" className="sp-error">
          {error}
        </p>
      )}
      {data.canPublish && (
        <>
          <label>
            Ocorrências desta operação
            <select disabled={busy || !!form} value={scope} onChange={(e) => setScope(e.target.value)}>
              <option value="current">Somente esta ocorrência</option>
              <option value="following">Esta e as próximas</option>
              <option value="all">Toda a série</option>
            </select>
          </label>
          <p>
            {data.affected} ocorrência(s) na seleção · {data.confirmed} confirmação(ões) que serão preservadas no histórico em caso de revisão ou cancelamento.
          </p>
          <div className="sp-actions">
            {data.service.status === 'draft' && (
              <button type="button" disabled={busy} onClick={() => open('publish')}>
                Publicar escala
              </button>
            )}
            {data.service.status === 'published' && (
              <>
                <button type="button" className="secondary" disabled={busy} onClick={() => open('revise')}>
                  Preparar revisão
                </button>
                <button type="button" className="secondary" disabled={busy} onClick={() => open('cancel')}>
                  Cancelar escala publicada
                </button>
                <button
                  type="button"
                  className="secondary"
                  disabled={busy || new Date(data.service.ends_at).getTime() > Date.now()}
                  onClick={() => open('close')}
                >
                  Encerrar serviço
                </button>
              </>
            )}
          </div>
        </>
      )}
      <h3>Vagas e conflitos atuais</h3>
      <p>As sugestões consideram função habilitada, disponibilidade e serviços nos últimos 30 dias. Nenhuma pessoa é confirmada automaticamente.</p>
      <div className="so-rows">
        {data.slots.map((p) => (
          <article key={p.role_id + ':' + p.ordinal}>
            <div>
              <strong>
                {p.teamName} · {p.roleName}
              </strong>
              <p>
                Vaga {p.ordinal} · {p.name || 'Em aberto'}
                {p.member_id && !p.hasAccount ? ' · sem conta para responder no aplicativo' : ''}
              </p>
              {p.conflicts.length > 0 && <p className="so-warning">{p.conflicts.map((c) => conflictLabels[c] || c).join(' · ')}</p>}
            </div>
            {!p.member_id && data.service.status === 'published' && p.canAssign && p.canPublish && (
              <button type="button" className="secondary" disabled={busy} onClick={() => open('fill', undefined, p)}>
                Preencher vaga
              </button>
            )}
          </article>
        ))}
      </div>
      <h3>Respostas e presença</h3>
      {!data.invites.length && <p>Nenhum convite criado. A publicação gera os convites individuais.</p>}
      <div className="so-rows">
        {data.invites.map((i) => {
          const p = data.slots.find((p) => p.role_id === i.role_id && p.ordinal === i.ordinal);
          return (
            <article key={i.id}>
              <div>
                <strong>{i.name}</strong>
                <p>
                  {i.team} · {i.role}
                </p>
                <p>
                  {responseStatus[i.response]} · Presença: {presenceStatus[i.presence]}
                  {!i.active
                    ? ' · Convite anterior: ' + ({revision: 'revisão', replaced: 'substituído', cancelled: 'cancelamento'}[i.ended_reason] || 'encerrado')
                    : ''}
                </p>
                <small>
                  Prazo: {formatInZone(i.deadline, data.service.timezone)}
                  {i.reply_reason ? ' · Resposta registrada pela liderança' : ''}
                </small>
              </div>
              {i.active && p?.canAssign && (
                <div className="sp-actions">
                  {data.service.status === 'published' && (
                    <>
                      <button type="button" className="secondary" disabled={busy} onClick={() => open('reply', i)}>
                        Registrar resposta de {i.name}
                      </button>
                      {p.canPublish && (
                        <button type="button" className="secondary" disabled={busy} onClick={() => open('replace', i)}>
                          Substituir {i.name}
                        </button>
                      )}
                    </>
                  )}
                  <button type="button" className="secondary" disabled={busy} onClick={() => open('presence', i)}>
                    Presença de {i.name}
                  </button>
                </div>
              )}
            </article>
          );
        })}
      </div>
      <h3>Pedidos de substituição</h3>
      {!data.requests.length && <p>Nenhuma solicitação nesta escala.</p>}
      {data.requests.map((c) => {
        const i = data.invites.find((i) => i.id === c.invite_id),
          p = data.slots.find((p) => p.role_id === i?.role_id && p.ordinal === i?.ordinal);
        return (
          <article key={c.id} className="so-request">
            <strong>
              {i?.name || 'Integrante'} · {{pending: 'Aguardando decisão', approved: 'Aprovado', rejected: 'Recusado', cancelled: 'Cancelado'}[c.state]}
            </strong>
            <p>{c.note || 'Sem observação adicional.'}</p>
            {c.suggested_name && <p>Sugestão: {c.suggested_name}</p>}
            {c.state === 'pending' && p?.canAssign && p?.canPublish && (
              <button type="button" className="secondary" disabled={busy} onClick={() => open('decision', i, undefined, c)}>
                Analisar substituição
              </button>
            )}
          </article>
        );
      })}
      {form && (
        <OperationDialog title={labels[form.action]} busy={busy} close={() => setForm(null)}>
          <form className="so-command" onSubmit={submit}>
            <h3>
              {labels[form.action]} · {target}
            </h3>
            {['publish', 'revise', 'cancel', 'close'].includes(form.action) && (
              <p>
                Ação em {data.affected} ocorrência(s).{' '}
                {form.action === 'revise'
                  ? 'Convites atuais serão encerrados, sem apagar respostas. Depois da edição, publique a escala para solicitar novas respostas.'
                  : form.action === 'close'
                    ? 'Respostas pendentes não serão convertidas em ausência.'
                    : 'Confira as vagas e os horários antes de confirmar.'}
              </p>
            )}
            {form.action === 'reply' && (
              <label>
                Resposta informada pela pessoa
                <select
                  value={response}
                  onChange={(e) => {
                    setResponse(e.target.value);
                    request.current = crypto.randomUUID();
                  }}
                >
                  <option value="accepted">Confirmou</option>
                  <option value="declined">Recusou</option>
                </select>
              </label>
            )}
            {form.action === 'presence' && (
              <label>
                Presença verificada
                <select
                  value={presence}
                  onChange={(e) => {
                    setPresence(e.target.value);
                    request.current = crypto.randomUUID();
                  }}
                >
                  <option value="present">Presente</option>
                  <option value="absent">Ausente</option>
                  <option value="unset">Remover registro de presença</option>
                </select>
              </label>
            )}
            {['replace', 'decision', 'fill'].includes(form.action) && (
              <>
                <label>
                  Buscar pessoa habilitada
                  <input
                    value={query}
                    maxLength={100}
                    onChange={(e) => {
                      setQuery(e.target.value);
                      setCandidatePage(1);
                    }}
                  />
                </label>
                <button type="button" className="secondary" disabled={busy} onClick={() => void find()}>
                  Buscar sugestões
                </button>
                <label>
                  Novo integrante
                  <select
                    required
                    value={candidate}
                    onChange={(e) => {
                      setCandidate(e.target.value);
                      request.current = crypto.randomUUID();
                    }}
                  >
                    <option value="">Selecione uma pessoa</option>
                    {candidate && !candidates.some((c) => c.id === candidate) && (
                      <option value={candidate}>{form.request?.suggested_name || 'Pessoa sugerida'}</option>
                    )}
                    {candidates.map((c) => (
                      <option key={c.id} value={c.id}>
                        {c.name} · {c.recent} serviço(s) recente(s){c.conflicts.length ? ' · possui conflito' : ' · disponível'}
                      </option>
                    ))}
                  </select>
                </label>
                <div className="sp-pager">
                  <button type="button" className="secondary" disabled={busy || candidatePage === 1} onClick={() => void find(candidatePage - 1)}>
                    Sugestões anteriores
                  </button>
                  <button type="button" className="secondary" disabled={busy || candidates.length < 20} onClick={() => void find(candidatePage + 1)}>
                    Mais sugestões
                  </button>
                </div>
              </>
            )}
            <label>
              Justificativa{['publish', 'close', 'fill', 'presence'].includes(form.action) ? ' (quando necessária)' : ''}
              <textarea
                maxLength={1000}
                required={['reply', 'revise', 'cancel', 'replace', 'decision'].includes(form.action) || override}
                minLength={['reply', 'revise', 'cancel', 'replace', 'decision'].includes(form.action) || override ? 10 : undefined}
                value={reason}
                onChange={(e) => {
                  setReason(e.target.value);
                  request.current = crypto.randomUUID();
                }}
                placeholder={form.action === 'presence' ? 'Para correções, explique o motivo.' : 'Informe o motivo desta decisão.'}
              />
            </label>
            {data.canPublish && ['publish', 'replace', 'decision', 'fill'].includes(form.action) && (
              <label className="so-check">
                <input
                  type="checkbox"
                  checked={override}
                  onChange={(e) => {
                    setOverride(e.target.checked);
                    request.current = crypto.randomUUID();
                  }}
                />
                <span>Autorizar exceção de horário ou disponibilidade com justificativa. Habilitação da função continua obrigatória.</span>
              </label>
            )}
            {error && (
              <p role="alert" className="sp-error">
                {error}
              </p>
            )}
            <footer className="sp-actions">
              <button type="button" className="secondary" disabled={busy} onClick={() => setForm(null)}>
                Voltar
              </button>
              {form.action === 'decision' && form.request && (
                <button type="button" className="secondary" disabled={busy} onClick={() => void reject(form.request!)}>
                  Recusar solicitação
                </button>
              )}
              <button disabled={busy}>{busy ? 'Registrando…' : form.action === 'decision' ? 'Aprovar substituição' : labels[form.action]}</button>
            </footer>
          </form>
        </OperationDialog>
      )}
    </section>
  );
}
export function ScalesRules({unitId}: {unitId: string}) {
  type Settings = {
    team: {id: string; name: string; travel: number; version: number};
    roles: {id: string; name: string; parallel_allowed: boolean; version: number}[];
    members: {id: string; name: string; version: number; role_id: string; qualifications: string[]}[];
    total: number;
  };
  const [teams, setTeams] = useState<{id: string; name: string}[]>([]),
    [team, setTeam] = useState(''),
    [teamPage, setTeamPage] = useState(1),
    [more, setMore] = useState(false),
    [data, setData] = useState<Settings | null>(null),
    [page, setPage] = useState(1),
    [search, setSearch] = useState(''),
    [member, setMember] = useState(''),
    [revision, setRevision] = useState(0),
    [busy, setBusy] = useState(false),
    [error, setError] = useState(''),
    [notice, setNotice] = useState('');
  const retry = useRef({key: '', request: ''});
  useEffect(() => {
    const c = new AbortController();
    const p = new URLSearchParams({unit: unitId, action: 'list', page: String(teamPage)});
    const tenant = new URLSearchParams(location.search).get('tenant');
    if (tenant) p.set('tenant', tenant);
    fetch('/api/scales-foundation?' + p, {signal: c.signal})
      .then(async (r) => {
        const v = (await r.json()) as {teams: {id: string; name: string; canManage: boolean}[]; total: number; error?: string};
        if (!r.ok) throw Error(v.error || 'Não foi possível carregar as equipes.');
        setTeams(v.teams.filter((t) => t.canManage));
        setMore(teamPage * 20 < v.total);
      })
      .catch((e) => {
        if (!c.signal.aborted) setError(e.message);
      });
    return () => c.abort();
  }, [unitId, teamPage, revision]);
  useEffect(() => {
    setData(null);
    if (!team) return;
    const c = new AbortController();
    read<Settings>(unitId, 'settings', {team, search, page: String(page)}, c.signal)
      .then(setData)
      .catch((e) => {
        if (!c.signal.aborted) setError(e.message);
      });
    return () => c.abort();
  }, [unitId, team, page, search, revision]);
  async function change(action: string, payload: Record<string, unknown>) {
    if (busy) return;
    setBusy(true);
    setError('');
    setNotice('');
    const key = JSON.stringify([team, action, payload]);
    if (retry.current.key !== key) retry.current = {key, request: crypto.randomUUID()};
    try {
      await write(unitId, action, {team, ...payload, request: retry.current.request});
      retry.current = {key: '', request: ''};
      setRevision((n) => n + 1);
      setNotice('Configuração salva. Os conflitos serão recalculados nas escalas.');
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  const selected = data?.members.find((m) => m.id === member);
  return (
    <details className="so-panel so-rules">
      <summary>Habilitações, funções simultâneas e deslocamento</summary>
      <p>A função principal habilita o integrante. Adicione outras funções somente após a conferência pela liderança.</p>
      {notice && <p role="status">{notice}</p>}
      {error && (
        <p role="alert" className="sp-error">
          {error}
        </p>
      )}
      <label>
        Equipe para configurar
        <select
          value={team}
          onChange={(e) => {
            setTeam(e.target.value);
            setPage(1);
          }}
        >
          <option value="">Selecione uma equipe</option>
          {teams.map((t) => (
            <option key={t.id} value={t.id}>
              {t.name}
            </option>
          ))}
        </select>
      </label>
      <div className="sp-pager">
        <button type="button" disabled={teamPage === 1} onClick={() => setTeamPage((n) => n - 1)}>
          Equipes anteriores
        </button>
        <button type="button" disabled={!more} onClick={() => setTeamPage((n) => n + 1)}>
          Mais equipes
        </button>
        <button type="button" className="secondary" disabled={busy} onClick={() => setRevision((n) => n + 1)}>
          Atualizar equipes
        </button>
      </div>
      {data && (
        <>
          <form
            onSubmit={(e) => {
              e.preventDefault();
              void change('policy', {travel: Number(new FormData(e.currentTarget).get('travel')), version: data.team.version});
            }}
          >
            <label>
              Intervalo de deslocamento (minutos)
              <input key={data.team.version} name="travel" type="number" min={0} max={240} required defaultValue={data.team.travel} />
            </label>
            <button disabled={busy}>Salvar intervalo</button>
          </form>
          <h3>Funções que podem coexistir no mesmo serviço</h3>
          <p>
            A dupla atribuição só é permitida quando todas as funções envolvidas estiverem habilitadas abaixo. Em serviços diferentes, a verificação de horários
            continua obrigatória.
          </p>
          {data.roles.map((r) => (
            <label key={r.id} className="so-check">
              <input
                type="checkbox"
                disabled={busy}
                checked={r.parallel_allowed}
                onChange={(e) => void change('policy', {role: r.id, parallel: e.target.checked, version: r.version})}
              />
              <span>{r.name}</span>
            </label>
          ))}
          <label>
            Buscar integrante
            <input
              maxLength={100}
              value={search}
              onChange={(e) => {
                setSearch(e.target.value);
                setPage(1);
              }}
            />
          </label>
          <label>
            Integrante
            <select value={member} onChange={(e) => setMember(e.target.value)}>
              <option value="">Selecione um integrante</option>
              {data.members.map((m) => (
                <option key={m.id} value={m.id}>
                  {m.name}
                </option>
              ))}
            </select>
          </label>
          {selected && (
            <fieldset disabled={busy}>
              <legend>Funções habilitadas para {selected.name}</legend>
              {data.roles.map((r) => (
                <label key={r.id} className="so-check">
                  <input
                    type="checkbox"
                    checked={selected.role_id === r.id || selected.qualifications.includes(r.id)}
                    disabled={selected.role_id === r.id}
                    onChange={(e) => void change('qualify', {member: selected.id, role: r.id, active: e.target.checked, version: selected.version})}
                  />
                  <span>
                    {r.name}
                    {selected.role_id === r.id ? ' · principal' : ''}
                  </span>
                </label>
              ))}
            </fieldset>
          )}
          <div className="sp-pager">
            <span>
              {data.total} integrante(s) · página {page}
            </span>
            <button type="button" disabled={page === 1 || busy} onClick={() => setPage((n) => n - 1)}>
              Integrantes anteriores
            </button>
            <button type="button" disabled={page * 20 >= data.total || busy} onClick={() => setPage((n) => n + 1)}>
              Mais integrantes
            </button>
          </div>
        </>
      )}
    </details>
  );
}
