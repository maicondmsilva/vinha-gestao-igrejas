'use client';
import {useState, type FormEvent} from 'react';
import type {ChurchRpc} from '../shared/member-church';
import {useVolunteerScales, type VolunteerInvite} from '../shared/use-volunteer-scales';
import {availabilityDraft, availabilityPayload, minutesText, type AvailabilityDraft} from '../shared/scale-availability';
import {formatInZone} from '../shared/timezone';
import {presenceStatus, responseStatus, serviceStatus, weekdays} from '../shared/scale-operations';
import './scales-volunteer.css';
export default function MemberVolunteerScales({rpc, org}: {rpc: ChurchRpc; org: string}) {
  const m = useVolunteerScales(rpc, org),
    [tab, setTab] = useState('invites'),
    [form, setForm] = useState<AvailabilityDraft | null>(null),
    [request, setRequest] = useState<VolunteerInvite | null>(null),
    [reason, setReason] = useState(''),
    [search, setSearch] = useState(''),
    [suggestion, setSuggestion] = useState(''),
    [people, setPeople] = useState<{id: string; name: string}[]>([]),
    [error, setError] = useState('');
  const zone = m.page?.timezone || m.availability?.timezone || 'America/Sao_Paulo';
  async function save(e: FormEvent) {
    e.preventDefault();
    if (!form) return;
    setError('');
    try {
      if (await m.command('available.save', availabilityPayload(form))) setForm(null);
    } catch (e) {
      setError((e as Error).message);
    }
  }
  async function find() {
    if (!request) return;
    setError('');
    try {
      setPeople(await m.suggestions(request.id, search));
    } catch (e) {
      setError((e as Error).message);
    }
  }
  return (
    <section className="sv-portal" id="member-scales" aria-label="Minhas escalas">
      <header>
        <h2>Minhas escalas</h2>
        <p>
          Convites do seu cadastro oficial{m.page?.unitName ? ' · ' + m.page.unitName : ''}. A igreja acompanhada para conteúdos não altera estas atribuições.
        </p>
      </header>
      <nav aria-label="Área do voluntário">
        <button type="button" aria-pressed={tab === 'invites'} onClick={() => setTab('invites')}>
          Convites e respostas
        </button>
        <button type="button" aria-pressed={tab === 'availability'} onClick={() => setTab('availability')}>
          Minha disponibilidade
        </button>
        <button type="button" disabled={m.busy || m.loading} onClick={m.refresh}>
          Atualizar escalas
        </button>
      </nav>
      {m.loading && <p role="status">Consultando suas escalas…</p>}
      {m.error && <p role="alert">{m.error}</p>}
      {error && <p role="alert">{error}</p>}
      {m.notice && <p role="status">{m.notice}</p>}
      {tab === 'invites' ? (
        <>
          {m.page && !m.page.items.length && <p>Nenhum convite nesta página. A liderança precisa publicar a escala para o convite aparecer.</p>}
          {m.page?.items.map((i) => (
            <article key={i.id}>
              <h3>{i.title}</h3>
              <p>
                {i.team} · {i.role}
              </p>
              <p>
                {formatInZone(i.starts_at, zone)} até {formatInZone(i.ends_at, zone)}
              </p>
              <p>Chegada: {formatInZone(i.arrival_at, zone)}</p>
              <p>
                <strong>{responseStatus[i.response]}</strong> · Presença: {presenceStatus[i.presence]}
              </p>
              {i.active ? (
                <>
                  <p>
                    {serviceStatus[i.status]} · Responder até {formatInZone(i.deadline, zone)}
                  </p>
                  {i.location && <p>Local: {i.location}</p>}
                  {i.notes && <p className="sv-preserve">Orientações: {i.notes}</p>}
                  {i.recordedByLeader && <p>Resposta registrada pela liderança.</p>}
                  {i.canReply ? (
                    <div className="sv-actions">
                      <button type="button" disabled={m.busy} onClick={() => void m.command('reply', {id: i.id, version: i.version, response: 'accepted'})}>
                        Confirmar participação
                      </button>
                      <button type="button" disabled={m.busy} onClick={() => void m.command('reply', {id: i.id, version: i.version, response: 'declined'})}>
                        Não poderei participar
                      </button>
                    </div>
                  ) : (
                    i.status === 'published' && <p>A resposta pelo aplicativo está indisponível. Procure o responsável pela escala.</p>
                  )}
                  {i.replacement ? (
                    <>
                      <p>Substituição solicitada. Aguarde a decisão da liderança.</p>
                      <button
                        type="button"
                        disabled={m.busy}
                        onClick={() => void m.command('replacement.cancel', {id: i.replacement!.id, version: i.replacement!.version})}
                      >
                        Cancelar pedido de substituição
                      </button>
                    </>
                  ) : (
                    i.status === 'published' &&
                    new Date(i.arrival_at).getTime() > Date.now() && (
                      <button
                        type="button"
                        disabled={m.busy}
                        onClick={() => {
                          setRequest(i);
                          setReason('');
                          setSuggestion('');
                          setSearch('');
                          setPeople([]);
                          setError('');
                        }}
                      >
                        Solicitar substituição
                      </button>
                    )
                  )}
                </>
              ) : (
                <p>
                  Convite anterior:{' '}
                  {{revision: 'escala em revisão', replaced: 'atribuição substituída', cancelled: 'escala cancelada'}[i.ended_reason] || 'encerrado'}. Sua
                  resposta foi preservada; não há acesso às instruções atuais desta atribuição.
                </p>
              )}
            </article>
          ))}
          <footer className="sv-actions">
            <span>
              {m.page?.total || 0} convite(s) · página {m.number}
            </span>
            <button type="button" disabled={m.number === 1 || m.loading || m.busy} onClick={() => m.setNumber((n) => n - 1)}>
              Convites anteriores
            </button>
            <button type="button" disabled={m.loading || m.busy || !m.page || m.number * 20 >= m.page.total} onClick={() => m.setNumber((n) => n + 1)}>
              Mais convites
            </button>
          </footer>
          {request && (
            <form
              onSubmit={async (e) => {
                e.preventDefault();
                if (await m.command('replacement.request', {id: request.id, version: request.version, reason, suggestion: suggestion || null}))
                  setRequest(null);
              }}
            >
              <h3>Solicitar substituição · {request.title}</h3>
              <p>A indicação é opcional. A liderança verifica a habilitação e a disponibilidade antes de aprovar.</p>
              <label>
                Observação ao responsável (opcional)
                <textarea maxLength={500} value={reason} onChange={(e) => setReason(e.target.value)} />
              </label>
              <label>
                Buscar pessoa habilitada da equipe
                <input maxLength={100} value={search} onChange={(e) => setSearch(e.target.value)} />
              </label>
              <button type="button" disabled={m.busy || search.trim().length < 2} onClick={() => void find()}>
                Buscar sugestão
              </button>
              <label>
                Indicação (opcional)
                <select value={suggestion} onChange={(e) => setSuggestion(e.target.value)}>
                  <option value="">Sem indicação</option>
                  {people.map((p) => (
                    <option key={p.id} value={p.id}>
                      {p.name}
                    </option>
                  ))}
                </select>
              </label>
              <div className="sv-actions">
                <button disabled={m.busy}>Enviar pedido de substituição</button>
                <button type="button" disabled={m.busy} onClick={() => setRequest(null)}>
                  Voltar
                </button>
              </div>
            </form>
          )}
        </>
      ) : (
        <>
          <p>
            Sem janelas semanais ativas, sua disponibilidade não é limitada por dia da semana. Os períodos de indisponibilidade continuam sendo respeitados.
            Para atravessar a meia-noite, cadastre uma janela em cada dia; o fim do dia pode ser 24:00.
          </p>
          <p>Os motivos pessoais ficam na sua conta. A equipe recebe somente o aviso de conflito.</p>
          <button
            type="button"
            disabled={m.busy}
            onClick={() => {
              setError('');
              setForm(availabilityDraft(crypto.randomUUID(), zone));
            }}
          >
            Adicionar disponibilidade
          </button>
          {m.availability?.items.map((a) => (
            <article key={a.id}>
              <h3>
                {a.kind === 'weekly' ? 'Disponibilidade semanal' : 'Indisponibilidade por período'} · {a.active ? 'Ativa' : 'Cancelada'}
              </h3>
              <p>
                {a.kind === 'weekly'
                  ? weekdays[a.weekday] + ' · ' + minutesText(a.start_minute) + ' às ' + minutesText(a.end_minute)
                  : formatInZone(a.starts_at, zone) + ' até ' + formatInZone(a.ends_at, zone)}
              </p>
              {a.reason && <p>Motivo particular: {a.reason}</p>}
              <div className="sv-actions">
                <button
                  type="button"
                  disabled={m.busy}
                  onClick={() => {
                    setError('');
                    setForm(availabilityDraft('', zone, a));
                  }}
                >
                  {a.active ? 'Editar disponibilidade' : 'Reativar disponibilidade'}
                </button>
                {a.active && (
                  <button type="button" disabled={m.busy} onClick={() => void m.command('available.save', {id: a.id, version: a.version, active: false})}>
                    Cancelar disponibilidade
                  </button>
                )}
              </div>
            </article>
          ))}
          <footer className="sv-actions">
            <span>
              {m.availability?.total || 0} período(s) · página {m.availabilityPage}
            </span>
            <button type="button" disabled={m.availabilityPage === 1 || m.loading || m.busy} onClick={() => m.setAvailabilityPage((n) => n - 1)}>
              Períodos anteriores
            </button>
            <button
              type="button"
              disabled={m.loading || m.busy || !m.availability || m.availabilityPage * 30 >= m.availability.total}
              onClick={() => m.setAvailabilityPage((n) => n + 1)}
            >
              Mais períodos
            </button>
          </footer>
          {form && (
            <form onSubmit={save}>
              <h3>{form.version ? 'Atualizar disponibilidade' : 'Nova disponibilidade'}</h3>
              <label>
                Tipo
                <select value={form.kind} onChange={(e) => setForm({...form, kind: e.target.value as AvailabilityDraft['kind']})}>
                  <option value="weekly">Janela semanal disponível</option>
                  <option value="unavailable">Período em que não posso participar</option>
                </select>
              </label>
              {form.kind === 'weekly' ? (
                <label>
                  Dia da semana
                  <select value={form.weekday} onChange={(e) => setForm({...form, weekday: Number(e.target.value)})}>
                    {weekdays.map((d, i) => (
                      <option key={d} value={i}>
                        {d}
                      </option>
                    ))}
                  </select>
                </label>
              ) : (
                <>
                  <label>
                    Data inicial
                    <input
                      type="date"
                      required
                      value={form.startDate}
                      onInput={(e) => setForm({...form, startDate: e.currentTarget.value})}
                      onChange={(e) => setForm({...form, startDate: e.target.value})}
                    />
                  </label>
                  <label>
                    Data final
                    <input
                      type="date"
                      required
                      value={form.endDate}
                      onInput={(e) => setForm({...form, endDate: e.currentTarget.value})}
                      onChange={(e) => setForm({...form, endDate: e.target.value})}
                    />
                  </label>
                </>
              )}
              <label>
                Horário inicial
                <input required type="time" value={form.startTime} onChange={(e) => setForm({...form, startTime: e.target.value})} />
              </label>
              <label>
                Horário final
                <input required placeholder="22:00" value={form.endTime} maxLength={5} onChange={(e) => setForm({...form, endTime: e.target.value})} />
              </label>
              <label>
                Motivo particular (opcional)
                <textarea maxLength={500} value={form.reason} onChange={(e) => setForm({...form, reason: e.target.value})} />
              </label>
              <p>Horário da igreja: {zone}. Alterar disponibilidade não cancela uma confirmação existente; avise a liderança ou solicite substituição.</p>
              <div className="sv-actions">
                <button disabled={m.busy}>Salvar disponibilidade</button>
                <button type="button" disabled={m.busy} onClick={() => setForm(null)}>
                  Voltar
                </button>
              </div>
            </form>
          )}
        </>
      )}
    </section>
  );
}
