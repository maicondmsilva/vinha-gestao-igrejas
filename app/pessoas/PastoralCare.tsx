'use client';
// Relatório de atendimento (com sigilo), histórico de atendimento da pessoa, regras do atendente e calendário da semana.
import {useCallback, useEffect, useMemo, useState} from 'react';
import {
  audienceLabel,
  contactKinds,
  emptyDraft,
  privacyHelp,
  privacyLabel,
  reportReferrals,
  reportTopics,
  type Privacy,
  type Report,
  type ReportDraft,
} from '../../shared/pastoral-care';
import './pastoral-care.css';

const tenantQuery = () => {
  const t = typeof window === 'undefined' ? '' : new URLSearchParams(location.search).get('tenant');
  return t ? {tenant: t} : ({} as Record<string, string>);
};
export async function careCall<T>(unit: string, action: string, data: Record<string, unknown>): Promise<T> {
  const r = await fetch('/api/pastoral-care?' + new URLSearchParams(tenantQuery()), {method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({unit, action, data})});
  const d = (await r.json().catch(() => ({}))) as T & {error?: string};
  if (!r.ok) throw Error(d.error || 'Não foi possível concluir.');
  return d;
}
const brDate = (iso: string) => new Date(iso).toLocaleDateString('pt-BR', {day: '2-digit', month: '2-digit', year: 'numeric'});
const brTime = (iso: string) => new Date(iso).toLocaleTimeString('pt-BR', {hour: '2-digit', minute: '2-digit', timeZone: 'America/Sao_Paulo'});
const label = (list: [string, string][], k: string) => list.find(([x]) => x === k)?.[1] || k;

/** Formulário do relatório: depois de um atendimento (appointment) ou contato de integração (person). */
export function ReportForm({
  unit,
  appointment,
  person,
  personName,
  report,
  close,
  onDone,
}: {
  unit: string;
  appointment?: string;
  person?: string;
  personName: string;
  report?: Report;
  close: () => void;
  onDone: (msg: string) => void;
}) {
  const followup = !appointment && !report?.appointment;
  const [d, setD] = useState<ReportDraft>(() =>
    report
      ? {
          summary: report.summary || '',
          topics: report.topics || [],
          prayer: report.prayer || '',
          referrals: report.referrals || [],
          nextStep: report.nextStep || '',
          privacy: report.privacy,
          contact: report.contact || 'ligacao',
        }
      : {...emptyDraft},
  );
  const [busy, setBusy] = useState(false),
    [error, setError] = useState('');
  useEffect(() => {
    const esc = (e: KeyboardEvent) => e.key === 'Escape' && !busy && close();
    addEventListener('keydown', esc);
    return () => removeEventListener('keydown', esc);
  }, [busy, close]);
  const toggle = (k: 'topics' | 'referrals', v: string) => setD({...d, [k]: d[k].includes(v) ? d[k].filter((x) => x !== v) : [...d[k], v]});
  async function save() {
    setBusy(true);
    setError('');
    try {
      await careCall(unit, 'save', {
        ...(report ? {id: report.id} : appointment ? {appointment} : {person, contact: d.contact}),
        summary: d.summary.trim(),
        topics: d.topics,
        prayer: d.prayer.trim(),
        referrals: d.referrals,
        nextStep: d.nextStep,
        privacy: d.privacy,
      });
      onDone(followup ? 'Contato registrado no histórico de ' + personName.split(' ')[0] + '.' : 'Relatório salvo no histórico de atendimento.');
      close();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Não foi possível salvar.');
    } finally {
      setBusy(false);
    }
  }
  return (
    <div className="pc-overlay" role="dialog" aria-modal="true" aria-label="Relatório de atendimento" onMouseDown={(e) => e.target === e.currentTarget && !busy && close()}>
      <div className="pc-modal">
        <header className="pc-modal-head">
          <div>
            <p>{followup ? 'INTEGRAÇÃO VISITANTE' : 'RELATÓRIO DE ATENDIMENTO'}</p>
            <h3>{personName}</h3>
          </div>
          <button type="button" className="pc-close" aria-label="Fechar" onClick={close} disabled={busy}>
            ×
          </button>
        </header>
        {followup && (
          <div className="pc-field">
            <span>Como foi o contato</span>
            <div className="pc-chips">
              {contactKinds.map(([k, l]) => (
                <button key={k} type="button" aria-pressed={d.contact === k} onClick={() => setD({...d, contact: k})}>
                  {l}
                </button>
              ))}
            </div>
          </div>
        )}
        <label className="pc-field">
          <span>Resumo</span>
          <textarea rows={6} maxLength={8000} value={d.summary} autoFocus placeholder="O que foi conversado e combinado." onChange={(e) => setD({...d, summary: e.target.value})} />
        </label>
        <div className="pc-field">
          <span>Assuntos</span>
          <div className="pc-chips">
            {reportTopics.map(([k, l]) => (
              <button key={k} type="button" aria-pressed={d.topics.includes(k)} onClick={() => toggle('topics', k)}>
                {l}
              </button>
            ))}
          </div>
        </div>
        <div className="pc-grid">
          <label className="pc-field">
            <span>Pedidos de oração (opcional)</span>
            <textarea rows={3} maxLength={2000} value={d.prayer} onChange={(e) => setD({...d, prayer: e.target.value})} />
          </label>
          <div className="pc-field">
            <span>Encaminhamentos</span>
            <div className="pc-chips">
              {reportReferrals.map(([k, l]) => (
                <button key={k} type="button" aria-pressed={d.referrals.includes(k)} onClick={() => toggle('referrals', k)}>
                  {l}
                </button>
              ))}
            </div>
            <label className="pc-inline">
              Próximo contato ou retorno
              <input type="date" value={d.nextStep} onChange={(e) => setD({...d, nextStep: e.target.value})} />
            </label>
          </div>
        </div>
        <fieldset className="pc-privacy">
          <legend>Quem pode ler</legend>
          {(['team', 'restricted', 'secret'] as Privacy[]).map((p) => (
            <label key={p} className={d.privacy === p ? 'on' : ''}>
              <input type="radio" name="privacy" checked={d.privacy === p} onChange={() => setD({...d, privacy: p})} />
              <b>{privacyLabel[p]}</b>
              <small>{privacyHelp[p]}</small>
            </label>
          ))}
        </fieldset>
        <p className="pc-note">O membro nunca vê o relatório. Toda leitura fica registrada. Depois de 7 dias o texto trava e só aceita complemento.</p>
        {error && (
          <p className="pc-error" role="alert">
            {error}
          </p>
        )}
        <div className="pc-actions">
          <button type="button" onClick={close} disabled={busy}>
            Cancelar
          </button>
          <button type="button" className="pc-primary" disabled={busy || d.summary.trim().length < 3} onClick={() => void save()}>
            {busy ? 'Salvando…' : report ? 'Salvar alterações' : 'Salvar relatório'}
          </button>
        </div>
      </div>
    </div>
  );
}

/** Ficha da pessoa › Histórico de atendimento: o conteúdo só aparece para quem tem a permissão do nível de sigilo. */
export function PastoralHistory({person, unit, personName}: {person: string; unit: string; personName: string}) {
  const [items, setItems] = useState<Report[] | null>(null),
    [hidden, setHidden] = useState(false),
    [error, setError] = useState(''),
    [editing, setEditing] = useState<Report | 'new' | null>(null),
    [notice, setNotice] = useState(''),
    [adding, setAdding] = useState(''),
    [reads, setReads] = useState<Record<string, {at: string; name: string}[]>>({});
  const load = useCallback(() => {
    if (!/^[0-9a-f-]{36}$/i.test(unit)) return setHidden(true);
    fetch('/api/pastoral-care?' + new URLSearchParams({unit, person, ...tenantQuery()}), {cache: 'no-store'})
      .then(async (r) => {
        const d = (await r.json()) as {items?: Report[]; error?: string};
        if (r.status === 403) return setHidden(true);
        if (!r.ok) throw Error(d.error || 'Indisponível.');
        setItems(d.items || []);
      })
      .catch((e) => setError(e.message));
  }, [person, unit]);
  useEffect(load, [load]);
  if (hidden) return <p className="pc-muted">O histórico de atendimento só aparece para quem tem permissão em Usuários e permissões.</p>;
  if (!items) return <p className="pc-muted">{error || 'Carregando…'}</p>;
  async function addendum(r: Report) {
    try {
      await careCall(unit, 'addendum', {id: r.id, text: adding.trim()});
      setAdding('');
      setNotice('Complemento salvo.');
      load();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Não foi possível salvar.');
    }
  }
  async function showReads(r: Report) {
    const d = await careCall<{items: {at: string; name: string}[]}>(unit, 'reads', {id: r.id}).catch(() => ({items: []}));
    setReads({...reads, [r.id]: d.items});
  }
  return (
    <div className="pc-history">
      {notice && <p className="pc-ok">{notice}</p>}
      <div className="pc-history-head">
        <span>{items.length ? items.length + (items.length === 1 ? ' registro' : ' registros') : 'Nenhum atendimento registrado.'}</span>
        <button type="button" className="pc-link" onClick={() => setEditing('new')}>
          ＋ Registrar contato
        </button>
      </div>
      <ol className="pc-timeline">
        {items.map((r) => (
          <li key={r.id} className={'p-' + r.privacy}>
            <div className="pc-dot" aria-hidden="true" />
            <div className="pc-entry">
              <header>
                <b>
                  {r.kind === 'atendimento' ? 'Atendimento' : 'Integração · ' + label(contactKinds, r.contact || 'outro')}
                  {r.appointment ? ' · ' + brTime(r.appointment.startsAt) : ''}
                </b>
                <span className={'pc-tag t-' + r.privacy}>{privacyLabel[r.privacy]}</span>
              </header>
              <small>
                {brDate(r.at)} · {r.author}
              </small>
              {r.readable ? (
                <>
                  <p className="pc-summary">{r.summary}</p>
                  {!!r.topics?.length && <p className="pc-meta">Assuntos: {r.topics.map((t) => label(reportTopics, t)).join(', ')}</p>}
                  {!!r.referrals?.length && <p className="pc-meta">Encaminhado: {r.referrals.map((t) => label(reportReferrals, t)).join(', ')}</p>}
                  {r.prayer && <p className="pc-meta">Oração: {r.prayer}</p>}
                  {r.nextStep && <p className="pc-meta">Próximo contato: {r.nextStep.split('-').reverse().join('/')}</p>}
                  {r.addenda?.map((a, i) => (
                    <p key={i} className="pc-addendum">
                      <b>Complemento {brDate(a.at)}:</b> {a.text}
                    </p>
                  ))}
                  {r.mine && (
                    <div className="pc-entry-actions">
                      {!r.locked && (
                        <button type="button" className="pc-link" onClick={() => setEditing(r)}>
                          Editar
                        </button>
                      )}
                      {r.locked && (
                        <span className="pc-inline-add">
                          <input value={adding} maxLength={2000} placeholder="Complementar…" onChange={(e) => setAdding(e.target.value)} />
                          <button type="button" className="pc-link" disabled={adding.trim().length < 3} onClick={() => void addendum(r)}>
                            Salvar
                          </button>
                        </span>
                      )}
                      <button type="button" className="pc-link" onClick={() => void showReads(r)}>
                        Quem leu
                      </button>
                    </div>
                  )}
                  {reads[r.id] && (
                    <p className="pc-meta">{reads[r.id]!.length ? reads[r.id]!.map((x) => x.name + ' (' + brDate(x.at) + ')').join(' · ') : 'Ninguém além de você leu.'}</p>
                  )}
                </>
              ) : (
                <p className="pc-locked">🔒 Conteúdo protegido pelo nível “{privacyLabel[r.privacy]}”.</p>
              )}
            </div>
          </li>
        ))}
      </ol>
      {editing && (
        <ReportForm
          unit={unit}
          person={person}
          personName={personName}
          report={editing === 'new' ? undefined : editing}
          close={() => setEditing(null)}
          onDone={(m) => (setNotice(m), load())}
        />
      )}
    </div>
  );
}

type Rules = {audience: string; minHours: number; maxOpen: number; cancelHours: number; maxPerDay: number | null; buffer: number};
/** Regras do atendente: quem pode pedir, antecedência, limites e intervalo. */
export function AttendantRules({unit, attendant}: {unit: string; attendant: string}) {
  const [r, setR] = useState<Rules | null>(null),
    [msg, setMsg] = useState(''),
    [busy, setBusy] = useState(false);
  useEffect(() => {
    fetch('/api/pastoral-care?' + new URLSearchParams({unit, attendant, ...tenantQuery()}), {cache: 'no-store'})
      .then((x) => (x.ok ? (x.json() as Promise<Rules>) : null))
      .then((d) => d && setR(d))
      .catch(() => undefined);
  }, [unit, attendant]);
  if (!r) return null;
  async function save() {
    setBusy(true);
    setMsg('');
    try {
      await careCall(unit, 'rules', {attendant, rules: {...r, maxPerDay: r!.maxPerDay ? String(r!.maxPerDay) : ''}});
      setMsg('Regras salvas.');
    } catch (e) {
      setMsg(e instanceof Error ? e.message : 'Não foi possível salvar.');
    } finally {
      setBusy(false);
    }
  }
  const num = (k: keyof Rules, l: string, min: number, max: number, help?: string) => (
    <label className="pc-field">
      <span>{l}</span>
      <input type="number" min={min} max={max} value={r[k] ?? ''} onChange={(e) => setR({...r, [k]: e.target.value === '' ? null : Number(e.target.value)})} />
      {help && <small>{help}</small>}
    </label>
  );
  return (
    <div className="pc-rules">
      <h4>Regras de agendamento</h4>
      <label className="pc-field">
        <span>Quem pode pedir pelo app</span>
        <select value={r.audience} onChange={(e) => setR({...r, audience: e.target.value})}>
          {Object.entries(audienceLabel).map(([k, l]) => (
            <option key={k} value={k}>
              {l}
            </option>
          ))}
        </select>
        <small>O atendente sempre pode marcar com qualquer pessoa que tenha acesso.</small>
      </label>
      <div className="pc-grid">
        {num('minHours', 'Antecedência mínima (horas)', 1, 168)}
        {num('cancelHours', 'Cancelamento até (horas antes)', 0, 72)}
        {num('maxOpen', 'Pedidos em aberto por membro', 1, 10)}
        {num('maxPerDay', 'Máximo de atendimentos por dia', 1, 20, 'Vazio: sem limite.')}
        <label className="pc-field">
          <span>Intervalo entre atendimentos</span>
          <select value={r.buffer} onChange={(e) => setR({...r, buffer: Number(e.target.value)})}>
            {[0, 5, 10, 15, 30].map((m) => (
              <option key={m} value={m}>
                {m ? m + ' min' : 'Sem intervalo'}
              </option>
            ))}
          </select>
        </label>
      </div>
      <div className="pc-actions">
        {msg && <span className="pc-muted">{msg}</span>}
        <button type="button" className="pc-primary" disabled={busy} onClick={() => void save()}>
          {busy ? 'Salvando…' : 'Salvar regras'}
        </button>
      </div>
    </div>
  );
}

type CalItem = {id: string; startsAt: string; endsAt: string; person: string; attendant: string; status: string; origin: string; memberAck: boolean; kind: string; reported?: boolean};
const tone = (i: CalItem) =>
  i.status === 'requested'
    ? 'request'
    : i.status === 'confirmed' && i.origin === 'staff' && !i.memberAck && Date.parse(i.startsAt) > Date.now()
      ? 'invite'
      : (i.status === 'confirmed' || i.status === 'done') && Date.parse(i.startsAt) < Date.now() && !i.reported
        ? 'report'
        : i.status === 'done'
          ? 'done'
          : i.status === 'confirmed'
            ? 'ok'
            : 'off';
export const calendarLegend: [string, string][] = [
  ['ok', 'Confirmado'],
  ['invite', 'Aguardando aceite'],
  ['request', 'Pedido para decidir'],
  ['report', 'Relatório pendente'],
  ['done', 'Realizado'],
];

/** Calendário da semana (segunda a domingo) com cores por situação. */
export function WeekCalendar({items, onOpen}: {items: CalItem[]; onOpen: (id: string) => void}) {
  const [offset, setOffset] = useState(0);
  const days = useMemo(() => {
    const t = new Date();
    const monday = new Date(t.getFullYear(), t.getMonth(), t.getDate() - ((t.getDay() + 6) % 7) + offset * 7);
    return Array.from({length: 7}, (_, i) => new Date(monday.getFullYear(), monday.getMonth(), monday.getDate() + i));
  }, [offset]);
  const key = (d: Date) => d.toLocaleDateString('sv-SE');
  const byDay = new Map<string, CalItem[]>();
  for (const i of items.filter((x) => !['cancelled', 'declined'].includes(x.status))) {
    const k = new Date(i.startsAt).toLocaleDateString('sv-SE', {timeZone: 'America/Sao_Paulo'});
    byDay.set(k, [...(byDay.get(k) || []), i].sort((a, b) => a.startsAt.localeCompare(b.startsAt)));
  }
  const today = key(new Date());
  return (
    <div className="pc-cal">
      <div className="pc-cal-head">
        <button type="button" onClick={() => setOffset(offset - 1)} aria-label="Semana anterior">
          ‹
        </button>
        <b>
          {days[0]!.toLocaleDateString('pt-BR', {day: '2-digit', month: 'short'})} – {days[6]!.toLocaleDateString('pt-BR', {day: '2-digit', month: 'short', year: 'numeric'})}
        </b>
        <button type="button" onClick={() => setOffset(offset + 1)} aria-label="Próxima semana">
          ›
        </button>
        {offset !== 0 && (
          <button type="button" className="pc-link" onClick={() => setOffset(0)}>
            Hoje
          </button>
        )}
      </div>
      <div className="pc-legend">
        {calendarLegend.map(([k, l]) => (
          <span key={k}>
            <i className={'c-' + k} />
            {l}
          </span>
        ))}
      </div>
      <div className="pc-week">
        {days.map((d) => {
          const k = key(d),
            list = byDay.get(k) || [];
          return (
            <section key={k} className={'pc-col' + (k === today ? ' today' : '')}>
              <header>
                <small>{d.toLocaleDateString('pt-BR', {weekday: 'short'})}</small>
                <b>{d.getDate()}</b>
              </header>
              {list.map((i) => (
                <button key={i.id} type="button" className={'pc-ev c-' + tone(i)} onClick={() => onOpen(i.id)}>
                  <b>{brTime(i.startsAt)}</b>
                  <span>{i.person}</span>
                  <small>{i.attendant}</small>
                </button>
              ))}
              {!list.length && <span className="pc-free">—</span>}
            </section>
          );
        })}
      </div>
    </div>
  );
}
