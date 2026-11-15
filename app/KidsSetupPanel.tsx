'use client';
import {useCallback, useEffect, useState} from 'react';
import {settingsUrl} from './lib/settings-navigation';
import {
  describeSeries,
  kidsRuleLabels,
  kidsTeamRoles,
  openBeforeOptions,
  seriesProblem,
  weekdayShort,
  type KidsSeries,
  type KidsSetup,
  type KidsTeamRole,
  type KidsReportRow,
  occupancy,
  rotationLetter,
} from '../shared/kids-setup';

const uuid = () => crypto.randomUUID();
const blank = (): KidsSeries => ({
  id: uuid(),
  name: '',
  rule: 'weekly',
  weekdays: [0],
  monthDay: 1,
  monthWeek: 1,
  startsTime: '09:00',
  durationMinutes: 120,
  validFrom: new Date().toISOString().slice(0, 10),
  validUntil: null,
  openBeforeHours: 24,
  rooms: [],
  autoTeam: true,
  active: true,
  version: 0,
  next: [],
});
const br = (d: string) => d.split('-').reverse().join('/');

/** Kids › Equipe fixa e repetições: equipe sem sessão ativa e sessões que se repetem e se criam sozinhas. */
export default function KidsSetupPanel({unit}: {unit: string}) {
  const [data, setData] = useState<KidsSetup | null>(null),
    [edit, setEdit] = useState<KidsSeries | null>(null),
    [q, setQ] = useState(''),
    [found, setFound] = useState<{id: string; name: string}[]>([]),
    [role, setRole] = useState<KidsTeamRole>('teacher'),
    [classId, setClassId] = useState(''),
    [busy, setBusy] = useState(false),
    [error, setError] = useState(''),
    [notice, setNotice] = useState('');
  const url = (extra: Record<string, string> = {}) => settingsUrl('/api/kids/setup?' + new URLSearchParams({unit, ...extra}));
  const load = useCallback(async () => {
    const r = await fetch(url(), {cache: 'no-store'});
    const d = (await r.json().catch(() => ({}))) as {error?: string};
    if (!r.ok) setError(d.error || 'Não foi possível carregar.');
    else setData(d as KidsSetup);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [unit]);
  useEffect(() => {
    void load();
  }, [load]);
  useEffect(() => {
    if (q.trim().length < 2) return setFound([]);
    const t = setTimeout(() => {
      void fetch(url({q: q.trim()}), {cache: 'no-store'})
        .then((r) => (r.ok ? r.json() : {items: []}))
        .then((x) => setFound(((x as {items?: {id: string; name: string}[]}).items || []).filter((p) => !data?.team.some((y) => y.personId === p.id))));
    }, 300);
    return () => clearTimeout(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [q, data]);
  async function act(action: string, payload: object, ok: string) {
    setBusy(true);
    setError('');
    setNotice('');
    const r = await fetch(url(), {method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({action, data: payload})}).catch(
      () => null,
    );
    const d = (r ? await r.json().catch(() => ({})) : {}) as {error?: string};
    setBusy(false);
    if (!r?.ok) {
      setError(d.error || 'Sem conexão.');
      return false;
    }
    setNotice(ok);
    await load();
    return true;
  }
  const [report, setReport] = useState<KidsReportRow[] | null>(null);
  async function loadReport() {
    const r = await fetch(url({report: '1'}), {cache: 'no-store'}).catch(() => null);
    const d = (r?.ok ? await r.json().catch(() => ({})) : {}) as {items?: KidsReportRow[]};
    setReport(d.items || []);
  }
  async function saveSeries() {
    if (!edit) return;
    const p = seriesProblem(edit);
    if (p) return setError(p);
    const {next: _n, ...payload} = edit;
    if (
      await act(
        'series_save',
        {...payload, monthDay: edit.monthDay ?? '', monthWeek: edit.monthWeek ?? '', validUntil: edit.validUntil || ''},
        'Repetição salva. As sessões são criadas sozinhas na antecedência escolhida.',
      )
    ) {
      await act(
        'series_options',
        {id: edit.id, rotationGroups: edit.rotationGroups || 1, autoOpen: !!edit.autoOpen},
        'Repetição salva. As sessões são criadas sozinhas na antecedência escolhida.',
      );
      setEdit(null);
    }
  }
  if (!data) return <section className="ko-card">{error ? <p className="ko-error">{error}</p> : <p className="ko-empty">Carregando…</p>}</section>;
  const className = (id: string | null) => data.classes.find((c) => c.id === id)?.name || 'qualquer turma';
  return (
    <>
      {error && <p className="ko-error">{error}</p>}
      {notice && <p className="ko-notice">{notice}</p>}
      <section className="ko-card">
        <div className="ko-card-title">
          <div>
            <h2>Equipe fixa do Kids</h2>
            <p>Monte a equipe sem precisar de sessão. Nas sessões que se repetem, cada pessoa entra escalada na turma dela.</p>
          </div>
        </div>
        {!data.team.length && <p className="ko-empty">Ninguém na equipe ainda.</p>}
        {data.team.map((t) => (
          <article key={t.id} className="ko-list-row">
            <div>
              <strong>{t.name}</strong>
              <br />
              <small>
                {kidsTeamRoles.find(([k]) => k === t.role)?.[1]}
                {['teacher', 'assistant'].includes(t.role) ? ' · ' + className(t.classId) : ''}
                {t.active ? '' : ' · afastado'}
                {t.unavailable?.length ? ' · indisponível: ' + t.unavailable.map((d) => br(d).slice(0, 5)).join(', ') : ''}
              </small>
            </div>
            <div className="ko-actions">
              <select
                aria-label={'Revezamento de ' + t.name}
                value={t.rotation || ''}
                disabled={busy}
                onChange={(e) =>
                  void act(
                    'team_save',
                    {id: t.id, version: t.version, role: t.role, classId: t.classId || '', canCare: t.canCare, active: t.active, rotation: e.target.value},
                    'Revezamento atualizado.',
                  )
                }
              >
                <option value="">Serve sempre</option>
                {[1, 2, 3].map((n) => (
                  <option key={n} value={n}>
                    Equipe {rotationLetter(n)}
                  </option>
                ))}
              </select>
              <button
                type="button"
                disabled={busy}
                onClick={() =>
                  void act(
                    'team_save',
                    {id: t.id, version: t.version, role: t.role, classId: t.classId || '', canCare: t.canCare, active: !t.active},
                    t.active ? 'Afastado da equipe.' : 'Voltou para a equipe.',
                  )
                }
              >
                {t.active ? 'Afastar' : 'Reativar'}
              </button>
              <button
                type="button"
                disabled={busy}
                onClick={() => confirm(`Remover ${t.name} da equipe fixa?`) && void act('team_remove', {id: t.id}, 'Removido da equipe.')}
              >
                Remover
              </button>
            </div>
          </article>
        ))}
        <div className="ko-form-grid" style={{marginTop: 16}}>
          <label>
            Função
            <select value={role} onChange={(e) => setRole(e.target.value as KidsTeamRole)}>
              {kidsTeamRoles.map(([k, l]) => (
                <option key={k} value={k}>
                  {l}
                </option>
              ))}
            </select>
          </label>
          {['teacher', 'assistant'].includes(role) && (
            <label>
              Turma preferida
              <select value={classId} onChange={(e) => setClassId(e.target.value)}>
                <option value="">Qualquer turma</option>
                {data.classes
                  .filter((c) => c.active)
                  .map((c) => (
                    <option key={c.id} value={c.id}>
                      {c.name}
                    </option>
                  ))}
              </select>
            </label>
          )}
          <label>
            Adicionar pessoa
            <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Nome (adulto com conta no app)" maxLength={80} />
          </label>
        </div>
        <div className="ko-actions" style={{marginTop: 8}}>
          {found.map((p) => (
            <button
              key={p.id}
              type="button"
              disabled={busy}
              onClick={() =>
                void act(
                  'team_save',
                  {
                    id: uuid(),
                    personId: p.id,
                    role,
                    classId: ['teacher', 'assistant'].includes(role) ? classId : '',
                    canCare: role === 'teacher',
                    active: true,
                  },
                  p.name + ' entrou na equipe.',
                ).then((ok) => ok && setQ(''))
              }
            >
              + {p.name}
            </button>
          ))}
        </div>
      </section>

      <section className="ko-card">
        <div className="ko-card-title">
          <div>
            <h2>Sessões que se repetem</h2>
            <p>
              Todo dia, em dias da semana ou todo mês. A sessão é criada sozinha, com salas e equipe, e as famílias já podem reservar a vaga pelo app na
              antecedência escolhida.
            </p>
          </div>
          {!edit && (
            <button type="button" className="ko-primary" onClick={() => setEdit(blank())}>
              + Nova repetição
            </button>
          )}
        </div>
        {data.series.map((s) => (
          <article key={s.id} className="ko-list-row">
            <div>
              <strong>{s.name}</strong>
              {!s.active && <span className="ko-badge"> pausada</span>}
              <br />
              <small>
                {describeSeries(s)} · {s.durationMinutes} min · {s.rooms.length} sala(s) · reservas{' '}
                {openBeforeOptions.find(([h]) => h === s.openBeforeHours)?.[1] || s.openBeforeHours + ' h antes'}
              </small>
              <br />
              <small>Próximas: {s.next.map(br).join(', ') || '—'}</small>
            </div>
            <div className="ko-actions">
              {s.next[0] && (
                <button
                  type="button"
                  disabled={busy}
                  title="Não criar a sessão nesta data"
                  onClick={() => void act('series_skip', {id: s.id, date: s.next[0]}, 'Data ' + br(s.next[0]!) + ' pulada.')}
                >
                  Pular {br(s.next[0]).slice(0, 5)}
                </button>
              )}
              <button type="button" onClick={() => setEdit({...s, weekdays: [...s.weekdays]})}>
                Editar
              </button>
            </div>
          </article>
        ))}
        {edit && (
          <div className="ko-form-grid" style={{marginTop: 16}}>
            <label>
              Nome
              <input value={edit.name} maxLength={100} onChange={(e) => setEdit({...edit, name: e.target.value})} placeholder="Kids domingo manhã" />
            </label>
            <label>
              Repete
              <select
                value={edit.rule}
                onChange={(e) =>
                  setEdit({
                    ...edit,
                    rule: e.target.value as KidsSeries['rule'],
                    weekdays: e.target.value === 'monthly_week' ? edit.weekdays.slice(0, 1) : edit.weekdays,
                  })
                }
              >
                {kidsRuleLabels.map(([k, l]) => (
                  <option key={k} value={k}>
                    {l}
                  </option>
                ))}
              </select>
            </label>
            {(edit.rule === 'weekly' || edit.rule === 'monthly_week') && (
              <fieldset className="ko-choices-row">
                <legend>Dia da semana</legend>
                {weekdayShort.map((d, i) => (
                  <label key={d} className="ko-check">
                    <input
                      type={edit.rule === 'monthly_week' ? 'radio' : 'checkbox'}
                      name="weekday"
                      checked={edit.weekdays.includes(i)}
                      onChange={() =>
                        setEdit({
                          ...edit,
                          weekdays:
                            edit.rule === 'monthly_week' ? [i] : edit.weekdays.includes(i) ? edit.weekdays.filter((x) => x !== i) : [...edit.weekdays, i],
                        })
                      }
                    />
                    {d}
                  </label>
                ))}
              </fieldset>
            )}
            {edit.rule === 'monthly_week' && (
              <label>
                Semana do mês
                <select value={edit.monthWeek || 1} onChange={(e) => setEdit({...edit, monthWeek: Number(e.target.value)})}>
                  {[1, 2, 3, 4, 5].map((n) => (
                    <option key={n} value={n}>
                      {n}ª semana
                    </option>
                  ))}
                </select>
              </label>
            )}
            {edit.rule === 'monthly_day' && (
              <label>
                Dia do mês
                <input
                  type="number"
                  min={1}
                  max={31}
                  value={edit.monthDay || ''}
                  onChange={(e) => setEdit({...edit, monthDay: Number(e.target.value) || null})}
                />
              </label>
            )}
            <label>
              Início
              <input type="time" value={edit.startsTime} onChange={(e) => setEdit({...edit, startsTime: e.target.value})} />
            </label>
            <label>
              Duração (minutos)
              <input
                type="number"
                min={15}
                max={720}
                value={edit.durationMinutes}
                onChange={(e) => setEdit({...edit, durationMinutes: Number(e.target.value)})}
              />
            </label>
            <label>
              Famílias reservam
              <select value={edit.openBeforeHours} onChange={(e) => setEdit({...edit, openBeforeHours: Number(e.target.value)})}>
                {openBeforeOptions.map(([h, l]) => (
                  <option key={h} value={h}>
                    {l}
                  </option>
                ))}
              </select>
            </label>
            <label>
              Começa em
              <input type="date" value={edit.validFrom} onChange={(e) => setEdit({...edit, validFrom: e.target.value})} />
            </label>
            <label>
              Termina em (opcional)
              <input type="date" value={edit.validUntil || ''} onChange={(e) => setEdit({...edit, validUntil: e.target.value || null})} />
            </label>
            <fieldset className="ko-choices-row" style={{gridColumn: '1/-1'}}>
              <legend>Salas e turmas</legend>
              {data.rooms
                .filter((r) => r.active)
                .flatMap((r) =>
                  data.classes
                    .filter((c) => c.active)
                    .map((c) => {
                      const on = edit.rooms.some((x) => x.roomId === r.id && x.classId === c.id);
                      return (
                        <label key={r.id + c.id} className="ko-check">
                          <input
                            type="checkbox"
                            checked={on}
                            onChange={() =>
                              setEdit({
                                ...edit,
                                rooms: on
                                  ? edit.rooms.filter((x) => !(x.roomId === r.id && x.classId === c.id))
                                  : [...edit.rooms, {roomId: r.id, classId: c.id, capacity: r.capacity, minStaff: 1}],
                              })
                            }
                          />
                          {r.name} · {c.name}
                        </label>
                      );
                    }),
                )}
              {(!data.rooms.length || !data.classes.length) && <small>Crie salas e turmas em “Turmas e salas”.</small>}
            </fieldset>
            <label className="ko-check">
              <input type="checkbox" checked={edit.autoTeam} onChange={(e) => setEdit({...edit, autoTeam: e.target.checked})} />
              Escalar a equipe fixa automaticamente
            </label>
            <label className="ko-check">
              <input type="checkbox" checked={!!edit.autoOpen} onChange={(e) => setEdit({...edit, autoOpen: e.target.checked})} />
              Abrir sozinha 30 min antes, se cada sala tiver a equipe mínima
            </label>
            <label>
              Revezamento da equipe
              <select value={edit.rotationGroups || 1} onChange={(e) => setEdit({...edit, rotationGroups: Number(e.target.value)})}>
                <option value={1}>Sem revezamento</option>
                <option value={2}>2 equipes (A e B)</option>
                <option value={3}>3 equipes (A, B e C)</option>
              </select>
            </label>
            <label className="ko-check">
              <input type="checkbox" checked={edit.active} onChange={(e) => setEdit({...edit, active: e.target.checked})} />
              Repetição ativa
            </label>
            <small>{describeSeries(edit)}</small>
            <div className="ko-actions" style={{gridColumn: '1/-1'}}>
              <button type="button" className="ko-primary" disabled={busy} onClick={() => void saveSeries()}>
                Salvar repetição
              </button>
              {!!edit.version && (
                <button
                  type="button"
                  disabled={busy}
                  onClick={() =>
                    confirm('Apagar esta repetição? As sessões já criadas continuam.') &&
                    void act('series_delete', {id: edit.id}, 'Repetição apagada.').then((ok) => ok && setEdit(null))
                  }
                >
                  Apagar
                </button>
              )}
              <button type="button" onClick={() => setEdit(null)}>
                Cancelar
              </button>
            </div>
          </div>
        )}
      </section>
      <section className="ko-card">
        <div className="ko-card-title">
          <h2>Relatório das repetições</h2>
          <button type="button" disabled={busy} onClick={() => void loadReport()}>
            {report ? 'Atualizar' : 'Ver relatório'}
          </button>
        </div>
        {report &&
          (!report.length ? (
            <p className="ko-empty">Ainda não há sessões das repetições.</p>
          ) : (
            <table className="ko-report">
              <thead>
                <tr>
                  <th>Data</th>
                  <th>Sessão</th>
                  <th>Crianças</th>
                  <th>Reservas</th>
                  <th>Ocupação</th>
                  <th>Equipe confirmada</th>
                </tr>
              </thead>
              <tbody>
                {report.map((r) => (
                  <tr key={r.id}>
                    <td>{new Date(r.startsAt).toLocaleDateString('pt-BR', {day: '2-digit', month: '2-digit', year: '2-digit'})}</td>
                    <td>{r.series}</td>
                    <td>{r.children}</td>
                    <td>{r.reserved}</td>
                    <td>{occupancy(r)}%</td>
                    <td>
                      {r.confirmed}/{r.staff}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          ))}
      </section>
    </>
  );
}
