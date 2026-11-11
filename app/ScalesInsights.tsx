'use client';

import {useEffect, useState} from 'react';
import {formatInZone, panelTimezone, toLocalDay} from '../shared/timezone';
import {scaleMetrics, scaleReportBasis, type ScaleFilters, type ScalePendingResult, type ScaleReport} from '../shared/scale-insights';
import './scales-insights.css';

type Mode = 'report' | 'pending';
type Query = {from: string; to: string; team: string; role: string; search: string};
const pendingLabels = {vacancy: 'Vaga em aberto', declined: 'Convite recusado', replacement: 'Pedido de troca', reply: 'Resposta pendente'};

function endpoint(unit: string, action: string, fields: Record<string, string> = {}) {
  const query = new URLSearchParams({unit, action, ...fields});
  const tenant = new URLSearchParams(location.search).get('tenant');
  if (tenant) query.set('tenant', tenant);
  return '/api/scales-insights?' + query;
}

async function read<T>(url: string, signal: AbortSignal): Promise<T> {
  const response = await fetch(url, {signal, cache: 'no-store'});
  const body = (await response.json()) as {error?: string};
  if (!response.ok) throw new Error(body.error || 'Não foi possível carregar os dados.');
  return body as T;
}

export default function ScalesInsights({unitId, mode, onOpen}: {unitId: string; mode: Mode; onOpen: (id: string) => void}) {
  const [filters, setFilters] = useState<Query>(() => {
    const today = toLocalDay(new Date(), panelTimezone());
    return {from: today.slice(0, 7) + '-01', to: today, team: '', role: '', search: ''};
  });
  const [applied, setApplied] = useState(filters);
  const [choices, setChoices] = useState<ScaleFilters | null>(null);
  const [report, setReport] = useState<ScaleReport | null>(null);
  const [pending, setPending] = useState<ScalePendingResult | null>(null);
  const [page, setPage] = useState(1);
  const [revision, refresh] = useState(0);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [filtersError, setFiltersError] = useState('');
  const [exporting, setExporting] = useState(false);
  const [exportError, setExportError] = useState('');
  const teams = [...new Map((choices?.choices || []).map((row) => [row.team, row.teamName]))];
  const roles = (choices?.choices || []).filter((row) => !filters.team || row.team === filters.team);
  const total = mode === 'report' ? report?.distributionTotal : pending?.total;
  const maxPage = Math.max(1, Math.ceil((total || 0) / 30));

  useEffect(() => {
    const controller = new AbortController();
    setFiltersError('');
    void read<ScaleFilters>(endpoint(unitId, 'filters'), controller.signal)
      .then((value) => {
        if (!controller.signal.aborted) setChoices(value);
      })
      .catch((e) => {
        if (!controller.signal.aborted) setFiltersError(e.message);
      });
    return () => controller.abort();
  }, [unitId, revision]);

  useEffect(() => {
    const controller = new AbortController();
    setLoading(true);
    setError('');
    setExportError('');
    setReport(null);
    setPending(null);
    const url = endpoint(unitId, mode, {...applied, page: String(page)});
    void read<ScaleReport | ScalePendingResult>(url, controller.signal)
      .then((value) => {
        if (controller.signal.aborted) return;
        if (mode === 'report') setReport(value as ScaleReport);
        else setPending(value as ScalePendingResult);
      })
      .catch((e) => {
        if (!controller.signal.aborted) setError(e.message);
      })
      .finally(() => {
        if (!controller.signal.aborted) setLoading(false);
      });
    return () => controller.abort();
  }, [unitId, mode, applied, page, revision]);

  async function download(format: 'pdf' | 'xlsx') {
    setExporting(true);
    setExportError('');
    try {
      const response = await fetch(endpoint(unitId, 'report', {...applied, page: String(page), format}), {cache: 'no-store'});
      if (!response.ok) {
        const body = (await response.json()) as {error?: string};
        throw new Error(body.error || 'Não foi possível exportar o relatório.');
      }
      const url = URL.createObjectURL(await response.blob());
      const link = document.createElement('a');
      link.href = url;
      link.download = `escalas-${applied.from}-${applied.to}.${format}`;
      link.click();
      setTimeout(() => URL.revokeObjectURL(url), 1000);
    } catch (e) {
      setExportError(e instanceof Error ? e.message : 'Não foi possível exportar o relatório.');
    } finally {
      setExporting(false);
    }
  }

  return (
    <section className="sp-insights" aria-label={mode === 'report' ? 'Relatórios de escalas' : 'Pendências e trocas'}>
      <header className="sp-insights-header">
        <div>
          <h2>{mode === 'report' ? 'Relatórios de escalas' : 'Pendências e trocas'}</h2>
          <p>
            {mode === 'report'
              ? 'Acompanhe cobertura, respostas, presença e distribuição de serviços da igreja selecionada.'
              : 'Veja as vagas em aberto, respostas e pedidos de troca na ordem do prazo.'}
          </p>
        </div>
        <button type="button" onClick={() => refresh((n) => n + 1)} disabled={loading}>
          Atualizar
        </button>
      </header>
      <form
        className="sp-insights-filters"
        onSubmit={(event) => {
          event.preventDefault();
          setPage(1);
          setApplied({...filters});
        }}
      >
        {mode === 'report' && (
          <>
            <label>
              Início
              <input type="date" required value={filters.from} onChange={(e) => setFilters({...filters, from: e.target.value})} />
            </label>
            <label>
              Fim
              <input type="date" required min={filters.from} value={filters.to} onChange={(e) => setFilters({...filters, to: e.target.value})} />
            </label>
          </>
        )}
        <label>
          Equipe
          <select value={filters.team} onChange={(e) => setFilters({...filters, team: e.target.value, role: ''})}>
            <option value="">Todas as equipes</option>
            {teams.map(([id, name]) => (
              <option key={id} value={id}>
                {name}
              </option>
            ))}
          </select>
        </label>
        <label>
          Função
          <select value={filters.role} onChange={(e) => setFilters({...filters, role: e.target.value})}>
            <option value="">Todas as funções</option>
            {roles.map((r) => (
              <option key={r.role} value={r.role}>
                {filters.team ? r.roleName : r.teamName + ' · ' + r.roleName}
              </option>
            ))}
          </select>
        </label>
        {mode === 'pending' && (
          <label>
            Buscar
            <input
              type="search"
              maxLength={100}
              value={filters.search}
              onChange={(e) => setFilters({...filters, search: e.target.value})}
              placeholder="Escala, equipe ou pessoa"
            />
          </label>
        )}
        <button type="submit">Aplicar filtros</button>
      </form>
      {filtersError && <p role="alert">{filtersError}</p>}
      {error && <p role="alert">{error}</p>}
      {loading && <p role="status">Consultando Escalas…</p>}
      {pending && (
        <>
          <p>Convites, lembretes e mudanças aparecem na caixa de entrada do membro. E-mail e push de Escalas aguardam configuração e homologação.</p>
          {pending.items.length ? (
            <ul className="sp-insights-pending">
              {pending.items.map((item) => (
                <li key={`${item.service_id}:${item.role_id}:${item.ordinal}`}>
                  <div>
                    <strong>{item.title}</strong>
                    <p>{[item.team, item.role, item.name].filter(Boolean).join(' · ')}</p>
                    <p>
                      {pendingLabels[item.kind]} · {Date.parse(item.due) <= Date.now() ? 'Prazo vencido em ' : 'Prazo até '}
                      {formatInZone(item.due, pending.timezone)}
                    </p>
                  </div>
                  <button type="button" onClick={() => onOpen(item.service_id)}>
                    Abrir escala
                  </button>
                </li>
              ))}
            </ul>
          ) : (
            <p>Nenhuma pendência com os filtros selecionados.</p>
          )}
        </>
      )}
      {report && (
        <>
          <p>
            <strong>{report.unitName}</strong> · {applied.from.split('-').reverse().join('/')} a {applied.to.split('-').reverse().join('/')}
          </p>
          <dl className="sp-insights-metrics">
            {scaleMetrics(report).map(([label, value]) => (
              <div key={label}>
                <dt>{label}</dt>
                <dd>{value}</dd>
              </div>
            ))}
          </dl>
          <p className="sp-insights-basis">{scaleReportBasis}</p>
          <div className="sp-insights-actions">
            <button type="button" disabled={exporting} onClick={() => void download('pdf')}>
              Baixar PDF
            </button>
            <button type="button" disabled={exporting} onClick={() => void download('xlsx')}>
              Baixar planilha
            </button>
          </div>
          <p>Os arquivos incluem o resumo e toda a distribuição das equipes e pessoas no filtro aplicado.</p>
          {exportError && <p role="alert">{exportError}</p>}
          <div className="sp-insights-table" tabIndex={0}>
            <table>
              <caption>Equipes e funções</caption>
              <thead>
                <tr>
                  {['Equipe', 'Função', 'Vagas', 'Preenchidas', 'Convites', 'Confirmações', 'Recusas', 'Pendentes'].map((label) => (
                    <th key={label} scope="col">
                      {label}
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {report.teamRoles.map((r, i) => (
                  <tr key={i}>
                    <td>{r.team}</td>
                    <td>{r.role}</td>
                    <td>{r.required}</td>
                    <td>{r.filled}</td>
                    <td>{r.invites}</td>
                    <td>{r.confirmed}</td>
                    <td>{r.declined}</td>
                    <td>{r.pending}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          {!report.teamRoles.length && <p>Nenhuma escala publicada ou encerrada no período.</p>}
          <div className="sp-insights-table" tabIndex={0}>
            <table>
              <caption>Distribuição por pessoa</caption>
              <thead>
                <tr>
                  {['Pessoa', 'Serviços', 'Atribuições', 'Confirmações'].map((label) => (
                    <th key={label} scope="col">
                      {label}
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {report.distribution.map((r) => (
                  <tr key={r.id}>
                    <td>{r.name}</td>
                    <td>{r.services}</td>
                    <td>{r.assignments}</td>
                    <td>{r.confirmed}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </>
      )}
      {typeof total === 'number' && total > 0 && (
        <div className="sp-insights-actions">
          <button type="button" disabled={page <= 1} onClick={() => setPage(page - 1)}>
            Anterior
          </button>
          <span>
            Página {page} de {maxPage} · {total} {mode === 'report' ? 'pessoa(s)' : 'pendência(s)'}
          </span>
          <button type="button" disabled={page >= maxPage} onClick={() => setPage(page + 1)}>
            Próxima
          </button>
        </div>
      )}
    </section>
  );
}
export function ScaleConnections({unitId, serviceId}: {unitId: string; serviceId: string}) {
  type Connections = {
    timezone: string;
    event: {title: string; status: string; path: string | null; differentTime: boolean} | null;
    kids: {id: string; name: string; starts_at: string; ends_at: string; status: string}[];
  };
  const [data, setData] = useState<Connections | null>(null);
  const [error, setError] = useState('');
  useEffect(() => {
    const controller = new AbortController();
    void read<Connections>(endpoint(unitId, 'connections', {service: serviceId}), controller.signal)
      .then((value) => {
        if (!controller.signal.aborted) setData(value);
      })
      .catch((e) => {
        if (!controller.signal.aborted) setError(e.message);
      });
    return () => controller.abort();
  }, [unitId, serviceId]);
  const panelLink = () => {
    const query = new URLSearchParams(location.search);
    query.set('pagina', 'kids');
    query.set('secao', 'sessions');
    query.set('unidade', unitId);
    return '/painel?' + query;
  };
  if (error) return <p role="alert">{error}</p>;
  if (!data) return <p role="status">Consultando a programação vinculada…</p>;
  return (
    <section className="sp-insights">
      <h3>Evento da Agenda</h3>
      {data.event ? (
        <div>
          <strong>{data.event.title}</strong>
          {data.event.status === 'cancelled' && <p role="status">O evento foi cancelado. Confira a situação desta escala.</p>}
          {data.event.differentTime && data.event.status !== 'cancelled' && (
            <p role="status">Os horários do evento e da escala são diferentes. Confira o planejamento.</p>
          )}
          {data.event.path && (
            <p>
              <a href={data.event.path}>Abrir página do evento</a>
            </p>
          )}
        </div>
      ) : (
        <p>Nenhum evento vinculado a esta escala.</p>
      )}
      <h3>Área Kids · sessões no mesmo horário</h3>
      {data.kids.length ? (
        <>
          <ul className="sp-insights-pending">
            {data.kids.map((session) => (
              <li key={session.id}>
                <div>
                  <strong>{session.name}</strong>
                  <p>
                    {formatInZone(session.starts_at, data.timezone)} a {formatInZone(session.ends_at, data.timezone)}
                  </p>
                </div>
              </li>
            ))}
          </ul>
          <p>
            <a href={panelLink()}>Abrir sessões da Área Kids</a>
          </p>
        </>
      ) : (
        <p>Nenhuma sessão disponível para a sua conta nesse horário.</p>
      )}
    </section>
  );
}
