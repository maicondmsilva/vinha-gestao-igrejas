'use client';
import {useCallback, useEffect, useState} from 'react';
import {settingsUrl} from './lib/settings-navigation';
import {
  blankSessionForm,
  describeSession,
  durationOptions,
  sessionFormFrom,
  sessionFormProblem,
  sessionPayload,
  weekdayShort,
  type KidsReportRow,
  type KidsSetup,
  type SessionForm,
  occupancy,
} from '../shared/kids-setup';

const uuid = () => crypto.randomUUID();
const dateMask = (v: string) =>
  v
    .replace(/\D/g, '')
    .slice(0, 8)
    .replace(/^(\d{2})(\d)/, '$1/$2')
    .replace(/^(\d{2}\/\d{2})(\d)/, '$1/$2');

/** Kids › Configurar › Sessões: uma sessão = nome, repetir (não repete ou dias da semana), horário e salas com turma e responsáveis. */
export default function KidsSetupPanel({unit}: {unit: string}) {
  const [data, setData] = useState<KidsSetup | null>(null),
    [form, setForm] = useState<SessionForm | null>(null),
    [busy, setBusy] = useState(false),
    [error, setError] = useState(''),
    [notice, setNotice] = useState(''),
    [report, setReport] = useState<KidsReportRow[] | null>(null);
  const url = useCallback((extra: Record<string, string> = {}) => settingsUrl('/api/kids/setup?' + new URLSearchParams({unit, ...extra})), [unit]);
  const load = useCallback(async () => {
    const r = await fetch(url(), {cache: 'no-store'});
    const d = (await r.json().catch(() => ({}))) as {error?: string};
    if (!r.ok) setError(d.error || 'Não foi possível carregar.');
    else setData(d as KidsSetup);
  }, [url]);
  useEffect(() => {
    void load();
  }, [load]);
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
  async function save() {
    if (!form || !data) return;
    const p = sessionFormProblem(form);
    if (p) return setError(p);
    const payload = sessionPayload(form, (id) => data.rooms.find((r) => r.id === id)?.capacity || 10);
    if (await act('series_save', payload, 'Sessão salva.')) {
      await act(
        'series_options',
        {id: form.id, autoOpen: true},
        form.repeat === 'once' ? 'Sessão salva.' : 'Sessão salva. As próximas datas são criadas sozinhas.',
      );
      setForm(null);
    }
  }
  async function loadReport() {
    const r = await fetch(url({report: '1'}), {cache: 'no-store'}).catch(() => null);
    const d = (r?.ok ? await r.json().catch(() => ({})) : {}) as {items?: KidsReportRow[]};
    setReport(d.items || []);
  }
  if (!data) return <section className="ko-card">{error ? <p className="ko-error">{error}</p> : <p className="ko-empty">Carregando…</p>}</section>;
  const roomName = (id: string) => data.rooms.find((r) => r.id === id)?.name || 'Sala';
  const className = (id: string) => data.classes.find((c) => c.id === id)?.name || 'Turma';
  const staffName = (id: string) => data.team.find((t) => t.id === id)?.name.split(' ')[0] || '';
  return (
    <>
      {error && <p className="ko-error">{error}</p>}
      {notice && <p className="ko-notice">{notice}</p>}
      {form ? (
        <SessionEditor
          data={data}
          form={form}
          setForm={setForm}
          busy={busy}
          url={url}
          act={act}
          onSave={() => void save()}
          onDelete={() =>
            void act('series_delete', {id: form.id}, 'Sessão excluída. As datas que já aconteceram continuam no histórico.').then((ok) => ok && setForm(null))
          }
        />
      ) : (
        <section className="ko-card">
          <div className="ko-card-title">
            <div>
              <h2>Sessões</h2>
              <p>Cada sessão tem dia, horário, salas e quem cuida de cada sala. Se repetir, as próximas datas são criadas sozinhas.</p>
            </div>
            <button type="button" className="ko-primary" onClick={() => setForm(blankSessionForm(uuid()))}>
              + Nova sessão
            </button>
          </div>
          {!data.series.length && <p className="ko-empty">Nenhuma sessão ainda. Crie antes as salas e turmas e depois a primeira sessão.</p>}
          <div className="ks-grid">
            {data.series.map((s) => {
              const f = sessionFormFrom(s);
              return (
                <button type="button" key={s.id} className={'ks-session' + (s.active ? '' : ' paused')} onClick={() => setForm(f)}>
                  <span className="ks-when">{describeSession(f)}</span>
                  <strong>{s.name}</strong>
                  <span className="ks-next">
                    {s.active ? (s.next.length ? 'Próxima: ' + s.next[0]!.split('-').reverse().slice(0, 2).join('/') : 'Sem próximas datas') : 'Pausada'}
                  </span>
                  <ul>
                    {s.rooms.map((r) => (
                      <li key={r.roomId}>
                        <b>{roomName(r.roomId)}</b> · {className(r.classId)}
                        <small>
                          {r.staff?.length ? r.staff.map(staffName).filter(Boolean).join(', ') : s.autoTeam ? 'equipe automática' : 'sem responsável'}
                        </small>
                      </li>
                    ))}
                  </ul>
                  <span className="ks-edit">Editar ›</span>
                </button>
              );
            })}
          </div>
        </section>
      )}
      <section className="ko-card">
        <div className="ko-card-title">
          <h2>Relatório das sessões</h2>
          <button type="button" disabled={busy} onClick={() => void loadReport()}>
            {report ? 'Atualizar' : 'Ver relatório'}
          </button>
        </div>
        {report &&
          (!report.length ? (
            <p className="ko-empty">Ainda não há sessões realizadas.</p>
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

function SessionEditor({
  data,
  form: f,
  setForm,
  busy,
  url,
  act,
  onSave,
  onDelete,
}: {
  data: KidsSetup;
  form: SessionForm;
  setForm: (f: SessionForm | null | ((c: SessionForm | null) => SessionForm | null)) => void;
  busy: boolean;
  url: (extra?: Record<string, string>) => string;
  act: (action: string, payload: object, ok: string) => Promise<boolean>;
  onSave: () => void;
  onDelete: () => void;
}) {
  const set = (x: Partial<SessionForm>) => setForm({...f, ...x});
  const rooms = data.rooms.filter((r) => r.active),
    classes = data.classes.filter((c) => c.active);
  const setRoom = (roomId: string, x: Partial<SessionForm['rooms'][number]>) =>
    setForm((c) => (c ? {...c, rooms: c.rooms.map((r) => (r.roomId === roomId ? {...r, ...x} : r))} : c));
  return (
    <section className="ko-card ks-editor">
      <div className="ko-card-title">
        <h2>{f.version ? 'Editar sessão' : 'Nova sessão'}</h2>
        <button type="button" onClick={() => setForm(null)}>
          Fechar
        </button>
      </div>
      <div className="ks-step">
        <span>1</span>
        <div>
          <label>
            Nome da sessão
            <input value={f.name} maxLength={100} placeholder="Ex.: Kids domingo manhã" onChange={(e) => set({name: e.target.value})} />
          </label>
        </div>
      </div>
      <div className="ks-step">
        <span>2</span>
        <div>
          <p className="ks-label">Quando</p>
          <div className="ks-chips">
            <button type="button" aria-pressed={f.repeat === 'once'} onClick={() => set({repeat: 'once'})}>
              Não repete
            </button>
            <button type="button" aria-pressed={f.repeat === 'weekly'} onClick={() => set({repeat: 'weekly'})}>
              Toda semana
            </button>
            {f.repeat === 'legacy' && (
              <button type="button" aria-pressed disabled>
                Mensal (como estava)
              </button>
            )}
          </div>
          {f.repeat === 'once' && (
            <label>
              Data
              <input inputMode="numeric" value={f.date} maxLength={10} placeholder="dd/mm/aaaa" onChange={(e) => set({date: dateMask(e.target.value)})} />
            </label>
          )}
          {f.repeat === 'weekly' && (
            <div className="ks-chips" role="group" aria-label="Dias da semana">
              {weekdayShort.map((d, i) => (
                <button
                  type="button"
                  key={d}
                  aria-pressed={f.weekdays.includes(i)}
                  onClick={() => set({weekdays: f.weekdays.includes(i) ? f.weekdays.filter((x) => x !== i) : [...f.weekdays, i]})}
                >
                  {d}
                </button>
              ))}
            </div>
          )}
          <div className="ks-row">
            <label>
              Começa às
              <input type="time" value={f.start} onChange={(e) => set({start: e.target.value})} />
            </label>
            <label>
              Duração
              <select value={f.duration} onChange={(e) => set({duration: Number(e.target.value)})}>
                {durationOptions.map(([m, l]) => (
                  <option key={m} value={m}>
                    {l}
                  </option>
                ))}
              </select>
            </label>
          </div>
        </div>
      </div>
      <div className="ks-step">
        <span>3</span>
        <div>
          <p className="ks-label">Salas, turma e responsáveis</p>
          {!rooms.length || !classes.length ? (
            <p className="ko-warning">Crie antes uma sala e uma turma em Configurar › Salas e turmas.</p>
          ) : (
            <div className="ks-rooms">
              {rooms.map((r) => {
                const sel = f.rooms.find((x) => x.roomId === r.id);
                return (
                  <div key={r.id} className={'ks-room' + (sel ? ' on' : '')}>
                    <label className="ko-check">
                      <input
                        type="checkbox"
                        checked={!!sel}
                        onChange={() =>
                          set({rooms: sel ? f.rooms.filter((x) => x.roomId !== r.id) : [...f.rooms, {roomId: r.id, classId: classes[0]!.id, staff: []}]})
                        }
                      />
                      <span>
                        <b>{r.name}</b> · {r.capacity} vagas
                      </span>
                    </label>
                    {sel && (
                      <>
                        <label>
                          Turma
                          <select value={sel.classId} onChange={(e) => setRoom(r.id, {classId: e.target.value})}>
                            {classes.map((c) => (
                              <option key={c.id} value={c.id}>
                                {c.name}
                              </option>
                            ))}
                          </select>
                        </label>
                        <StaffPicker data={data} staff={sel.staff} onChange={(s) => setRoom(r.id, {staff: s})} url={url} act={act} />
                      </>
                    )}
                  </div>
                );
              })}
            </div>
          )}
        </div>
      </div>
      <label className="ko-check">
        <input type="checkbox" checked={f.active} onChange={(e) => set({active: e.target.checked})} />
        <span>Sessão ativa (desmarque para pausar sem apagar)</span>
      </label>
      <div className="ko-actions">
        <button type="button" className="ko-primary" disabled={busy} onClick={onSave}>
          {busy ? 'Salvando…' : 'Salvar sessão'}
        </button>
        {!!f.version && (
          <button
            type="button"
            disabled={busy}
            onClick={() => window.confirm('Excluir esta sessão? As datas que já aconteceram continuam no histórico.') && onDelete()}
          >
            Excluir sessão
          </button>
        )}
        <button type="button" onClick={() => setForm(null)}>
          Cancelar
        </button>
      </div>
    </section>
  );
}

function StaffPicker({
  data,
  staff,
  onChange,
  url,
  act,
}: {
  data: KidsSetup;
  staff: string[];
  onChange: (s: string[]) => void;
  url: (extra?: Record<string, string>) => string;
  act: (action: string, payload: object, ok: string) => Promise<boolean>;
}) {
  const [q, setQ] = useState(''),
    [found, setFound] = useState<{id: string; name: string}[]>([]);
  useEffect(() => {
    if (q.trim().length < 2) return setFound([]);
    const t = setTimeout(() => {
      void fetch(url({q: q.trim()}), {cache: 'no-store'})
        .then((r) => (r.ok ? r.json() : {items: []}))
        .then((x) => setFound(((x as {items?: {id: string; name: string}[]}).items || []).filter((p) => !data.team.some((y) => y.personId === p.id))));
    }, 300);
    return () => clearTimeout(t);
  }, [q, data.team, url]);
  return (
    <div className="ks-staff">
      <p className="ks-label">Responsáveis da sala</p>
      <div className="ks-chips">
        {data.team
          .filter((t) => t.active)
          .map((t) => (
            <button
              type="button"
              key={t.id}
              aria-pressed={staff.includes(t.id)}
              onClick={() => onChange(staff.includes(t.id) ? staff.filter((x) => x !== t.id) : [...staff, t.id])}
            >
              {t.name.split(' ').slice(0, 2).join(' ')}
            </button>
          ))}
      </div>
      <input value={q} maxLength={80} placeholder="Incluir pessoa: buscar pelo nome" onChange={(e) => setQ(e.target.value)} />
      {found.map((p) => (
        <button
          type="button"
          key={p.id}
          className="ks-add"
          onClick={() => {
            const id = uuid();
            void act(
              'team_save',
              {id, personId: p.id, role: 'teacher', classId: '', canCare: true, active: true},
              p.name.split(' ')[0] + ' incluído na equipe do Kids.',
            ).then((ok) => {
              if (ok) {
                onChange([...staff, id]);
                setQ('');
              }
            });
          }}
        >
          + {p.name}
        </button>
      ))}
      {q.trim().length >= 2 && !found.length && <small>Só aparecem adultos com conta ativa no app da igreja.</small>}
    </div>
  );
}
