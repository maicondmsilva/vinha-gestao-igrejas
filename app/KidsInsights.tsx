'use client';
import {useEffect, useState} from 'react';
import {settingsUrl} from './lib/settings-navigation';
import KidsChildPhoto from './KidsChildPhoto';

type Birthday = {profileId: string; name: string; date: string; age: number; in: number};
type Absent = {profileId: string; name: string; last: string; visits: number; guardians: string | null};
const when = (n: number) => (n === 0 ? 'Hoje' : n === 1 ? 'Amanhã' : 'Em ' + n + ' dias');
const br = (iso: string) => iso.split('-').reverse().join('/');

function useInsight<T>(unit: string, kind: 'birthdays' | 'absent', refresh: number) {
  const [items, setItems] = useState<T[] | null>(null),
    [error, setError] = useState('');
  useEffect(() => {
    const c = new AbortController();
    setError('');
    fetch(settingsUrl('/api/kids/insights?' + new URLSearchParams({unit, kind})), {cache: 'no-store', signal: c.signal})
      .then(async (r) => {
        const d = (await r.json().catch(() => ({}))) as {items?: T[]; error?: string};
        if (!r.ok || !Array.isArray(d.items)) throw Error(d.error || 'Não foi possível consultar.');
        setItems(d.items);
      })
      .catch((e) => !c.signal.aborted && setError(e.message));
    return () => c.abort();
  }, [unit, kind, refresh]);
  return {items, error};
}

/** Visão geral: aniversariantes dos próximos 7 dias, para a equipe celebrar na sala. */
export function KidsBirthdays({unit, refresh = 0}: {unit: string; refresh?: number}) {
  const {items} = useInsight<Birthday>(unit, 'birthdays', refresh);
  if (!items?.length) return null;
  return (
    <section className="ko-card ko-insight">
      <div className="ko-card-title">
        <div>
          <h2>🎂 Aniversariantes da semana</h2>
          <p>Uma lembrança para a equipe celebrar com a criança na sala.</p>
        </div>
      </div>
      <ul className="ko-people">
        {items.map((b) => (
          <li key={b.profileId}>
            <KidsChildPhoto unit={unit} profile={b.profileId} name={b.name} size={40} />
            <div>
              <b>{b.name}</b>
              <small>
                {b.date} · faz {b.age} {b.age === 1 ? 'ano' : 'anos'}
              </small>
            </div>
            <span className={'ko-badge' + (b.in === 0 ? ' present' : '')}>{when(b.in)}</span>
          </li>
        ))}
      </ul>
    </section>
  );
}

/** Relatórios › Ausências: crianças que vinham e não vêm há 4 semanas, para a coordenação acompanhar a família. */
export function KidsAbsent({unit, refresh = 0}: {unit: string; refresh?: number}) {
  const {items, error} = useInsight<Absent>(unit, 'absent', refresh);
  return (
    <section className="ko-card ko-insight">
      <div className="ko-card-title">
        <div>
          <h2>Crianças ausentes</h2>
          <p>Vieram ao menos duas vezes nos últimos 6 meses e não vêm há mais de 4 semanas. Um contato com a família mostra cuidado.</p>
        </div>
      </div>
      {error && (
        <p className="ko-error" role="alert">
          {error}
        </p>
      )}
      {!items && !error && <p className="ko-loading">Consultando…</p>}
      {items && !items.length && <p className="ko-empty">Nenhuma criança ausente. Todas as famílias frequentes vieram nas últimas 4 semanas.</p>}
      {!!items?.length && (
        <ul className="ko-people">
          {items.map((a) => (
            <li key={a.profileId}>
              <KidsChildPhoto unit={unit} profile={a.profileId} name={a.name} size={40} />
              <div>
                <b>{a.name}</b>
                <small>
                  Última vez em {br(a.last)} · {a.visits} {a.visits === 1 ? 'presença' : 'presenças'} em 6 meses
                  {a.guardians ? ' · Responsáveis: ' + a.guardians : ''}
                </small>
              </div>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
