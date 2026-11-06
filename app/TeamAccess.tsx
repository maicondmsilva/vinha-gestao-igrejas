'use client';
import {useEffect, useState} from 'react';
import {settingsUrl} from './lib/settings-navigation';
import FieldError from './FieldError';
import {ApiError, readApiError} from '../shared/contract/errors';
import {staffRoleLabel, staffScopeLabel, staffScopes, type StaffAccessList, type StaffScope} from '../shared/contract/staff';
import {churchTimezones, defaultTimezone} from '../shared/timezone';
import './programming.css';

async function call<T>(body?: unknown): Promise<T> {
  const r = await fetch(
    settingsUrl('/api/staff-access' + (body ? '' : '?action=list')),
    body ? {method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify(body)} : {cache: 'no-store'},
  );
  const d = await r.json().catch(() => ({}));
  if (!r.ok) throw new ApiError(readApiError(d), r.status);
  return d as T;
}

/** Fine-grained access for secretaries and leaders, and the time zone of each church. */
export default function TeamAccess() {
  const [data, setData] = useState<StaffAccessList | null>(null),
    [error, setError] = useState(''),
    [notice, setNotice] = useState(''),
    [fields, setFields] = useState<Record<string, string>>({}),
    [busy, setBusy] = useState('');
  useEffect(() => {
    call<StaffAccessList>()
      .then(setData)
      .catch((e) => setError((e as Error).message));
  }, []);
  async function save(key: string, body: unknown, done: string) {
    setBusy(key);
    setNotice('');
    setFields({});
    try {
      setData(await call<StaffAccessList>(body));
      setNotice(done);
    } catch (e) {
      setNotice((e as Error).message);
      if (e instanceof ApiError) setFields(e.fields);
    } finally {
      setBusy('');
    }
  }
  if (!data)
    return (
      <section className="program-page">
        <p className={error ? 'program-error' : 'program-empty'} role="status">
          {error || 'Carregando equipe…'}
        </p>
      </section>
    );
  const unitName = (id: string) => data.units.find((u) => u.id === id)?.name || 'Igreja';
  const zoneLabel = (tz: string) => churchTimezones.find(([z]) => z === tz)?.[1] || tz;
  return (
    <section className="program-page">
      <div className="program-heading">
        <div>
          <p className="section-over">COMUNICAÇÃO · EQUIPE</p>
          <h1>Equipe e fuso horário</h1>
          <p>
            Libere agenda, entrada, publicações e push para a secretaria e a liderança, por igreja. Responsáveis, administração e pastores já têm acesso
            completo.
          </p>
        </div>
      </div>
      {notice && (
        <p className={Object.keys(fields).length ? 'program-error' : 'program-notice'} role="status">
          {notice}
        </p>
      )}

      <article className="program-card">
        <div className="program-card-title">
          <h2>Fuso horário</h2>
          <span>Datas e horários de eventos, agendamentos de push e aniversários seguem o fuso de cada igreja.</span>
        </div>
        <div className="program-form">
          <label>
            Padrão do ministério
            <select
              value={data.timezone}
              disabled={!!busy}
              onChange={(e) => void save('tz:org', {action: 'timezone', data: {timezone: e.target.value}}, 'Fuso do ministério salvo.')}
            >
              {churchTimezones.map(([z, label]) => (
                <option key={z} value={z}>
                  {label}
                </option>
              ))}
            </select>
            <FieldError fields={fields} name="timezone" />
          </label>
          <div className="program-form-grid">
            {data.units.map((u) => (
              <label key={u.id}>
                {u.name}
                <select
                  value={u.ownTimezone || ''}
                  disabled={!!busy}
                  onChange={(e) => void save('tz:' + u.id, {action: 'timezone', data: {unit: u.id, timezone: e.target.value}}, 'Fuso de ' + u.name + ' salvo.')}
                >
                  <option value="">Igual ao ministério ({zoneLabel(data.timezone || defaultTimezone)})</option>
                  {churchTimezones.map(([z, label]) => (
                    <option key={z} value={z}>
                      {label}
                    </option>
                  ))}
                </select>
              </label>
            ))}
          </div>
        </div>
      </article>

      <article className="program-card" style={{marginTop: 22}}>
        <div className="program-card-title">
          <h2>Permissões da equipe</h2>
          <span>{data.team.length} pessoas de secretaria e liderança</span>
        </div>
        {!data.team.length ? (
          <div className="program-empty">
            <h3>Ninguém de secretaria ou liderança ainda</h3>
            <p>Defina o perfil em Usuários e permissões e dê acesso à igreja. Depois, libere aqui o que cada pessoa pode fazer.</p>
          </div>
        ) : (
          <div className="program-table-wrap">
            <table className="program-table">
              <thead>
                <tr>
                  <th>Pessoa</th>
                  <th>Igreja</th>
                  {staffScopes.map((s) => (
                    <th key={s}>{staffScopeLabel[s]}</th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {data.team.flatMap((m) =>
                  (m.units.length ? m.units : ['']).map((unit, i) => (
                    <tr key={m.user + unit}>
                      <td>
                        {i === 0 && (
                          <>
                            <strong>{m.name}</strong>
                            <small>
                              {staffRoleLabel[m.role] || m.role} · {m.email}
                            </small>
                          </>
                        )}
                      </td>
                      <td>{unit ? unitName(unit) : <small>Sem acesso a igrejas. Ajuste em Usuários e permissões.</small>}</td>
                      {staffScopes.map((s) => {
                        const current = (m.grants[unit] || []) as StaffScope[],
                          on = current.includes(s);
                        return (
                          <td key={s}>
                            {unit && (
                              <input
                                type="checkbox"
                                aria-label={`${staffScopeLabel[s]} para ${m.name} em ${unitName(unit)}`}
                                checked={on}
                                disabled={!!busy}
                                onChange={() =>
                                  void save(
                                    m.user + unit,
                                    {action: 'grant', data: {user: m.user, unit, scopes: on ? current.filter((x) => x !== s) : [...current, s]}},
                                    `${on ? 'Retirado' : 'Liberado'}: ${staffScopeLabel[s]} para ${m.name}.`,
                                  )
                                }
                              />
                            )}
                          </td>
                        );
                      })}
                    </tr>
                  )),
                )}
              </tbody>
            </table>
          </div>
        )}
        <p className="program-list-tools">Cada mudança vale na hora, no painel e no Vinha Equipe, e fica registrada na auditoria.</p>
      </article>
    </section>
  );
}
