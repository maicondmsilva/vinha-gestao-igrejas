'use client';
import {useCallback, useEffect, useState} from 'react';
import {settingsUrl} from './lib/settings-navigation';
import {ApiError, readApiError} from '../shared/contract/errors';
import {kidsStationOnline, type KidsStationList} from '../shared/contract/kids';
import {formatInZone} from '../shared/timezone';

const platformLabel: Record<string, string> = {android: 'Android', ios: 'iPhone / iPad', web: 'Navegador', other: 'Outro aparelho'};

/** Reception stations: tablets and phones running Vinha Equipe in station mode for this church. */
export default function KidsStations({unit}: {unit: string}) {
  const [data, setData] = useState<KidsStationList | null>(null),
    [error, setError] = useState(''),
    [notice, setNotice] = useState(''),
    [busy, setBusy] = useState('');
  const url = settingsUrl('/api/kids-station?' + new URLSearchParams({unit}));
  const load = useCallback(async () => {
    const r = await fetch(url, {cache: 'no-store'});
    const d = await r.json().catch(() => ({}));
    if (!r.ok) throw new ApiError(readApiError(d), r.status);
    return d as KidsStationList;
  }, [url]);
  useEffect(() => {
    let live = true;
    load()
      .then((d) => live && setData(d))
      .catch((e) => live && setError((e as Error).message));
    return () => {
      live = false;
    };
  }, [load]);
  async function revoke(id: string, name: string) {
    setBusy(id);
    setNotice('');
    try {
      const r = await fetch(url, {method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({action: 'revoke', id})});
      const d = await r.json().catch(() => ({}));
      if (!r.ok) throw new ApiError(readApiError(d), r.status);
      setData(d as KidsStationList);
      setNotice(`${name} foi desativada. O login daquele aparelho foi encerrado.`);
    } catch (e) {
      setNotice((e as Error).message);
    } finally {
      setBusy('');
    }
  }
  if (!data)
    return (
      <section className="ko-card">
        <p className={error ? 'ko-error' : 'ko-empty'} role="status">
          {error || 'Carregando estações…'}
        </p>
      </section>
    );
  const active = data.items.filter((s) => !s.revokedAt);
  return (
    <section className="ko-card">
      <div className="ko-card-title">
        <div>
          <h2>Estações de recepção</h2>
          <p>
            Tablets e celulares com o Vinha Equipe em modo estação. A coordenação registra a estação no próprio aparelho. Se ele for perdido ou trocado,
            desative aqui: o login daquele aparelho é encerrado na hora.
          </p>
        </div>
      </div>
      {notice && (
        <p className="ko-notice" role="status">
          {notice}
        </p>
      )}
      {!data.items.length ? (
        <div className="ko-empty">
          <h3>Nenhuma estação registrada</h3>
          <p>No Vinha Equipe, entre com a conta da coordenação e escolha “Usar como estação do Kids”.</p>
        </div>
      ) : (
        <div>
          {data.items.map((s) => {
            const online = kidsStationOnline(s);
            return (
              <article key={s.id} className="ko-list-row">
                <div>
                  <strong>
                    {s.name}
                    {s.mine ? ' (este aparelho)' : ''}
                  </strong>
                  <br />
                  <small>
                    {platformLabel[s.platform] || s.platform} · registrada por {s.user} em {formatInZone(s.createdAt, data.timezone, {dateStyle: 'short'})}
                  </small>
                  <br />
                  <small>
                    {s.revokedAt
                      ? `Desativada em ${formatInZone(s.revokedAt, data.timezone)}`
                      : online
                        ? 'Em uso agora'
                        : `Visto por último em ${formatInZone(s.lastSeenAt, data.timezone)}`}
                  </small>
                </div>
                {!s.revokedAt && (
                  <button type="button" disabled={!!busy} onClick={() => void revoke(s.id, s.name)}>
                    {busy === s.id ? 'Desativando…' : 'Desativar'}
                  </button>
                )}
              </article>
            );
          })}
        </div>
      )}
      <p className="ko-eyebrow">
        {active.length} {active.length === 1 ? 'estação ativa' : 'estações ativas'} · limite de 50 por igreja. Retiradas sempre exigem internet e conferência do
        adulto autorizado.
      </p>
    </section>
  );
}
