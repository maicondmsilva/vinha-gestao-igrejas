'use client';
import {useEffect, useState} from 'react';
import {settingsUrl} from './lib/settings-navigation';
import './programming.css';
import './publishing.css';

type Row = {id: string; title: string; recipients: number; delivered: number; opened: number; source: string; at: string};
type Notice = {id: string; title: string; kind: string; reads: number; clicks: number};
type Metrics = {days: number; push: {campaigns: number; recipients: number; delivered: number; opened: number}; campaigns: Row[]; notices: Notice[]};
const pct = (part: number, whole: number) => (whole ? Math.round((100 * part) / whole) + '%' : '—');
const sourceLabel: Record<string, string> = {manual: 'Campanha', live: 'Início de live', birthday: 'Aniversários'};

/** Reach of the church's communication: push delivered and opened, notices read, banners tapped. */
export default function CommunicationMetrics({unit}: {unit: string}) {
  const [days, setDays] = useState(30),
    [data, setData] = useState<Metrics | null>(null),
    [error, setError] = useState('');
  useEffect(() => {
    let alive = true;
    fetch(settingsUrl('/api/communication/metrics?' + new URLSearchParams({unit, days: String(days)})))
      .then(async (r) => {
        const d = (await r.json()) as Metrics & {error?: string};
        if (!r.ok) throw Error(d.error || 'Métricas indisponíveis.');
        if (alive) {
          setData(d);
          setError('');
        }
      })
      .catch((e) => alive && setError((e as Error).message));
    return () => {
      alive = false;
    };
  }, [unit, days]);
  const p = data?.push;
  return (
    <div className="content program-page publishing-page">
      <div className="program-breadcrumb">
        Comunicação <span>/</span> Métricas de alcance
      </div>
      <div className="program-heading">
        <div>
          <p className="section-over">Alcance da comunicação</p>
          <h1>Métricas de alcance</h1>
          <p>Quantas pessoas receberam, abriram e leram o que a igreja publicou.</p>
        </div>
        <div className="program-actions">
          <label className="publishing-period">
            Período
            <select value={days} onChange={(e) => setDays(Number(e.target.value))}>
              <option value={7}>7 dias</option>
              <option value={30}>30 dias</option>
              <option value={90}>90 dias</option>
            </select>
          </label>
        </div>
      </div>
      {error && (
        <p className="program-error" role="alert">
          {error}
        </p>
      )}
      {!data ? (
        !error && (
          <div className="program-empty" role="status">
            Carregando métricas…
          </div>
        )
      ) : (
        <>
          <div className="metric-tiles">
            <div>
              <span>Pushes enviados</span>
              <b>{p!.campaigns}</b>
              <small>campanhas no período</small>
            </div>
            <div>
              <span>Entregues</span>
              <b>{p!.delivered}</b>
              <small>de {p!.recipients} aparelhos ({pct(p!.delivered, p!.recipients)})</small>
            </div>
            <div>
              <span>Aberturas</span>
              <b>{p!.opened}</b>
              <small>{pct(p!.opened, p!.delivered)} dos entregues</small>
            </div>
          </div>
          <section className="program-card">
          <div className="program-card-title">
            <h2>Campanhas recentes</h2>
            <span>Últimos {data.days} dias</span>
          </div>
          {!data.campaigns.length ? (
            <div className="program-empty">
              <p>Nenhum push enviado nos últimos {data.days} dias.</p>
            </div>
          ) : (
            <div className="program-table-wrap">
              <table className="program-table">
                <thead>
                  <tr>
                    <th>Campanha</th>
                    <th>Tipo</th>
                    <th>Entregues</th>
                    <th>Abertura</th>
                  </tr>
                </thead>
                <tbody>
                  {data.campaigns.map((c) => (
                    <tr key={c.id}>
                      <td>
                        <strong>{c.title}</strong>
                        <small>{new Date(c.at).toLocaleString('pt-BR', {dateStyle: 'short', timeStyle: 'short'})}</small>
                      </td>
                      <td data-label="Tipo">{sourceLabel[c.source] || c.source}</td>
                      <td data-label="Entregues">
                        {c.delivered} de {c.recipients}
                      </td>
                      <td data-label="Abertura">{pct(c.opened, c.delivered)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
          </section>
          <section className="program-card">
          <div className="program-card-title">
            <h2>Avisos e banners</h2>
            <span>Publicados no período</span>
          </div>
          {!data.notices.length ? (
            <div className="program-empty">
              <p>Nenhum aviso ou banner publicado no período.</p>
            </div>
          ) : (
            <div className="program-table-wrap">
              <table className="program-table">
                <thead>
                  <tr>
                    <th>Conteúdo</th>
                    <th>Leituras no app</th>
                    <th>Toques</th>
                  </tr>
                </thead>
                <tbody>
                  {data.notices.map((n) => (
                    <tr key={n.id}>
                      <td>
                        <strong>{n.title}</strong>
                        <small>{n.kind === 'banner' ? 'Banner' : 'Aviso'}</small>
                      </td>
                      <td data-label="Leituras no app">{n.reads}</td>
                      <td data-label="Toques">{n.clicks}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
          </section>
          <p className="publishing-help">
            Leituras contam quem abriu o aviso na caixa de entrada do app. Toques contam cada pessoa uma vez. Aberturas de push dependem do app atualizado.
          </p>
        </>
      )}
    </div>
  );
}
