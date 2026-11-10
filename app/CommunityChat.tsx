'use client';
import {useCallback, useEffect, useMemo, useRef, useState} from 'react';
import {settingsUrl} from './lib/settings-navigation';
import {createSupabaseBrowserClient, supabaseConfigured} from './lib/supabase/client';
import FieldError from './FieldError';
import {ApiError, readApiError} from '../shared/contract/errors';
import {
  chatEvent,
  chatLimits,
  chatMuteOptions,
  chatReasonLabels,
  chatReasons,
  chatSignal,
  chatTopic,
  mergeChatMessages,
  type ChatMessage,
  type ChatReport,
  type ChatRoom,
  type ChatSettings,
  type ChatThread,
} from '../shared/contract/chat';
import './programming.css';
import './community-chat.css';

async function call<T>(query: Record<string, string> | null, body?: unknown): Promise<T> {
  const r = await fetch(
    settingsUrl('/api/community-chat' + (query ? '?' + new URLSearchParams(query) : '')),
    body ? {method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify(body)} : {cache: 'no-store'},
  );
  const d = await r.json().catch(() => ({}));
  if (!r.ok) throw new ApiError(readApiError(d), r.status);
  return d as T;
}
const time = (v: string) => new Date(v).toLocaleString('pt-BR', {day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit'});
const tabs = [
  ['conversas', 'Conversas'],
  ['denuncias', 'Denúncias'],
  ['canais', 'Canais'],
  ['ajustes', 'Regras do chat'],
] as const;
type Tab = (typeof tabs)[number][0];

/** Community chat: moderation and conversation for the church team, in real time. */
export default function CommunityChat({unit}: {unit: string}) {
  const [tab, setTab] = useState<Tab>('conversas'),
    [rooms, setRooms] = useState<ChatRoom[] | null>(null),
    [error, setError] = useState(''),
    [reports, setReports] = useState<ChatReport[] | null>(null);
  const loadRooms = useCallback(
    () =>
      call<{rooms: ChatRoom[]}>({action: 'rooms'})
        .then((d) => {
          setRooms(d.rooms);
          setError('');
        })
        .catch((e) => setError((e as Error).message)),
    [],
  );
  const loadReports = useCallback(
    () =>
      call<{reports: ChatReport[]}>({action: 'reports'})
        .then((d) => setReports(d.reports))
        .catch(() => setReports([])),
    [],
  );
  useEffect(() => {
    void loadRooms();
    void loadReports();
  }, [loadRooms, loadReports]);
  return (
    <section className="program-page">
      <div className="program-heading">
        <div>
          <p className="section-over">COMUNICAÇÃO · CHAT</p>
          <h1>Chat da comunidade</h1>
          <p>
            Canais da igreja e conversas diretas entre adultos, com moderação. Menores de 18 anos não participam. Mensagens denunciadas por{' '}
            {chatLimits.reportsToHide} pessoas ficam ocultas até a revisão.
          </p>
        </div>
      </div>
      <nav className="program-tabs" aria-label="Seções do chat">
        {tabs.map(([id, label]) => (
          <button key={id} type="button" aria-current={tab === id ? 'page' : undefined} onClick={() => setTab(id)}>
            {label}
            {id === 'denuncias' && reports?.length ? <span className="chat-count">{reports.length}</span> : null}
          </button>
        ))}
      </nav>
      {error && (
        <p className="program-error" role="status">
          {error}
        </p>
      )}
      {tab === 'conversas' && <Conversations rooms={rooms} reload={loadRooms} />}
      {tab === 'denuncias' && <Reports reports={reports} reload={loadReports} />}
      {tab === 'canais' && <Channels unit={unit} rooms={rooms} reload={loadRooms} />}
      {tab === 'ajustes' && <Settings />}
    </section>
  );
}

function Conversations({rooms, reload}: {rooms: ChatRoom[] | null; reload: () => void}) {
  const [room, setRoom] = useState(''),
    [search, setSearch] = useState(''),
    [people, setPeople] = useState<{id: string; name: string; unit: string | null}[]>([]),
    [notice, setNotice] = useState('');
  async function find() {
    setNotice('');
    try {
      setPeople((await call<{people: typeof people}>(null, {action: 'people', data: {search}})).people);
    } catch (e) {
      setNotice((e as Error).message);
    }
  }
  async function direct(person: string) {
    try {
      const d = await call<{room: string}>(null, {action: 'direct', data: {person}});
      setPeople([]);
      setSearch('');
      reload();
      setRoom(d.room);
    } catch (e) {
      setNotice((e as Error).message);
    }
  }
  if (!rooms) return <p className="program-empty">Carregando conversas…</p>;
  const current = rooms.find((r) => r.id === room) || rooms[0];
  return (
    <div className="chat-layout">
      <aside className="program-card chat-rooms" aria-label="Conversas">
        <ul>
          {rooms.map((r) => (
            <li key={r.id}>
              <button type="button" aria-pressed={r.id === current?.id} onClick={() => setRoom(r.id)}>
                <span>
                  {r.kind === 'channel' ? '# ' : ''}
                  {r.name}
                </span>
                {r.unread > 0 && <span className="chat-count">{r.unread > 99 ? '99+' : r.unread}</span>}
                <small>{r.kind === 'direct' ? 'Conversa direta' : r.audience === 'staff' ? 'Só equipe' : r.posting === 'moderators' ? 'Mural' : 'Canal'}</small>
              </button>
            </li>
          ))}
          {!rooms.length && <li className="chat-hint">Nenhum canal ainda. Crie o primeiro em Canais.</li>}
        </ul>
        <form
          className="chat-find"
          onSubmit={(e) => {
            e.preventDefault();
            void find();
          }}
        >
          <label>
            Conversar com um adulto da igreja
            <input value={search} maxLength={60} placeholder="Nome" onChange={(e) => setSearch(e.target.value)} />
          </label>
          <button type="submit" disabled={search.trim().length < 2}>
            Buscar
          </button>
        </form>
        {notice && <p className="chat-hint">{notice}</p>}
        {people.length > 0 && (
          <ul>
            {people.map((p) => (
              <li key={p.id}>
                <button type="button" onClick={() => void direct(p.id)}>
                  <span>{p.name}</span>
                  <small>{p.unit || ''}</small>
                </button>
              </li>
            ))}
          </ul>
        )}
      </aside>
      {current ? <Thread key={current.id} room={current} onRead={reload} /> : <div className="program-card program-empty">Escolha uma conversa.</div>}
    </div>
  );
}

function Thread({room, onRead}: {room: ChatRoom; onRead: () => void}) {
  const [thread, setThread] = useState<ChatThread | null>(null),
    [messages, setMessages] = useState<ChatMessage[]>([]),
    [body, setBody] = useState(''),
    [notice, setNotice] = useState(''),
    [fields, setFields] = useState<Record<string, string>>({}),
    [busy, setBusy] = useState(false),
    [live, setLive] = useState(false),
    [older, setOlder] = useState(true);
  const list = useRef<HTMLOListElement>(null),
    client = useRef<string>('');
  const apply = useCallback(
    (t: ChatThread) => {
      setThread(t);
      setMessages((m) => mergeChatMessages(m, t.messages));
      if (t.messages.length < 50) setOlder(false);
      onRead();
    },
    [onRead],
  );
  const load = useCallback(() => call<ChatThread>({action: 'messages', room: room.id}).then(apply), [room.id, apply]);
  useEffect(() => {
    call<ChatThread>({action: 'messages', room: room.id})
      .then(apply)
      .catch((e) => setNotice((e as Error).message));
  }, [room.id, apply]);
  // Realtime: the signal carries only ids; content is read again through the API, with the same rules.
  const supabase = useMemo(() => (supabaseConfigured ? createSupabaseBrowserClient() : null), []);
  useEffect(() => {
    if (!supabase) return;
    let gone = false;
    const channel = supabase.channel(chatTopic(room.id), {config: {private: true}});
    void supabase.realtime.setAuth().then(() => {
      if (gone) return;
      channel
        .on('broadcast', {event: chatEvent}, (msg) => {
          const s = chatSignal(msg);
          if (!s || s.room !== room.id) return;
          call<ChatMessage>({action: 'message', room: room.id, id: s.id})
            .then((m) => setMessages((list) => mergeChatMessages(list, [m])))
            .catch(() => undefined);
        })
        .subscribe((status) => setLive(status === 'SUBSCRIBED'));
    });
    return () => {
      gone = true;
      void supabase.removeChannel(channel);
    };
  }, [supabase, room.id]);
  // Without realtime (blocked network, expired session), refresh every 20 seconds.
  useEffect(() => {
    if (live) return;
    const t = setInterval(() => void load().catch(() => undefined), 20000);
    return () => clearInterval(t);
  }, [live, load]);
  const last = messages[messages.length - 1]?.id;
  useEffect(() => {
    list.current?.lastElementChild?.scrollIntoView({block: 'end'});
  }, [last]);
  async function more() {
    const first = messages[0];
    if (!first) return;
    const t = await call<ChatThread>({action: 'messages', room: room.id, before: first.createdAt});
    setMessages((m) => mergeChatMessages(m, t.messages));
    if (t.messages.length < 50) setOlder(false);
  }
  async function send() {
    if (!body.trim()) return;
    setBusy(true);
    setFields({});
    setNotice('');
    client.current ||= crypto.randomUUID();
    try {
      const d = await call<{message: ChatMessage}>(null, {action: 'send', data: {room: room.id, body, client: client.current}});
      setMessages((m) => mergeChatMessages(m, [d.message]));
      setBody('');
      client.current = '';
    } catch (e) {
      setNotice((e as Error).message);
      if (e instanceof ApiError) setFields(e.fields);
    } finally {
      setBusy(false);
    }
  }
  async function act(action: string, data: Record<string, unknown>, done: string) {
    setNotice('');
    try {
      const d = await call<{message?: ChatMessage}>(null, {action, data: {room: room.id, ...data}});
      if (d.message) setMessages((m) => mergeChatMessages(m, [d.message!]));
      else await load();
      setNotice(done);
    } catch (e) {
      setNotice((e as Error).message);
    }
  }
  const moderator = thread?.moderator;
  return (
    <article className="program-card chat-thread">
      <div className="program-card-title">
        <div>
          <h2>
            {room.kind === 'channel' ? '# ' : ''}
            {room.name}
          </h2>
          {room.description && <small>{room.description}</small>}
        </div>
        <span className={live ? 'chat-live' : 'chat-offline'}>{live ? 'Ao vivo' : 'Atualiza a cada 20 s'}</span>
      </div>
      <ol className="chat-messages" ref={list} aria-live="polite">
        {older && messages.length >= 50 && (
          <li className="chat-more">
            <button type="button" onClick={() => void more().catch(() => undefined)}>
              Mensagens anteriores
            </button>
          </li>
        )}
        {messages.map((m) => (
          <li key={m.id} className={'chat-message' + (m.mine ? ' mine' : '') + (m.state !== 'visible' ? ' ' + m.state : '')}>
            <div className="chat-meta">
              <strong>{m.mine ? 'Você' : m.sender}</strong> <time dateTime={m.createdAt}>{time(m.createdAt)}</time>
              {m.reports ? <span className="chat-flag">{m.reports} denúncia(s)</span> : null}
            </div>
            {m.state === 'deleted' ? (
              <p className="chat-removed">Mensagem apagada por quem enviou.</p>
            ) : m.state === 'hidden' && !m.body ? (
              <p className="chat-removed">Mensagem oculta pela moderação.</p>
            ) : (
              <p>
                {m.state === 'hidden' && <em className="chat-flag">{m.hiddenReason === 'reports' ? 'Oculta por denúncias · ' : 'Oculta · '}</em>}
                {m.body}
              </p>
            )}
            {m.state !== 'deleted' && (
              <div className="chat-tools">
                {m.mine && (
                  <button type="button" onClick={() => void act('delete', {id: m.id}, 'Mensagem apagada.')}>
                    Apagar
                  </button>
                )}
                {moderator && m.state === 'visible' && !m.mine && (
                  <button type="button" onClick={() => void act('hide', {id: m.id}, 'Mensagem ocultada.')}>
                    Ocultar
                  </button>
                )}
                {moderator && m.state === 'hidden' && (
                  <button type="button" onClick={() => void act('unhide', {id: m.id}, 'Mensagem visível de novo.')}>
                    Mostrar
                  </button>
                )}
                {moderator && !m.mine && m.senderId && (
                  <select
                    aria-label={'Silenciar ' + m.sender}
                    value=""
                    onChange={(e) =>
                      e.target.value &&
                      void act(
                        'mute',
                        {user: m.senderId, minutes: Number(e.target.value)},
                        Number(e.target.value) ? m.sender + ' silenciado(a).' : m.sender + ' liberado(a).',
                      )
                    }
                  >
                    <option value="">Silenciar…</option>
                    {chatMuteOptions.map((o) => (
                      <option key={o.minutes} value={String(o.minutes)}>
                        {o.label}
                      </option>
                    ))}
                  </select>
                )}
                {!m.mine && !moderator && (
                  <select
                    aria-label="Denunciar mensagem"
                    value=""
                    onChange={(e) => e.target.value && void act('report', {id: m.id, reason: e.target.value}, 'Denúncia enviada à moderação.')}
                  >
                    <option value="">Denunciar…</option>
                    {chatReasons.map((r) => (
                      <option key={r} value={r}>
                        {chatReasonLabels[r]}
                      </option>
                    ))}
                  </select>
                )}
              </div>
            )}
          </li>
        ))}
        {thread && !messages.length && <li className="chat-hint">Nenhuma mensagem ainda.</li>}
      </ol>
      {notice && (
        <p className={Object.keys(fields).length ? 'program-error' : 'program-notice'} role="status">
          {notice}
        </p>
      )}
      {thread && !thread.canPost ? (
        <p className="chat-hint chat-composer">
          {thread.mutedUntil ? 'Você está sem enviar mensagens até ' + time(thread.mutedUntil) + '.' : 'Neste canal só a moderação envia mensagens.'}
        </p>
      ) : (
        <form
          className="chat-composer"
          onSubmit={(e) => {
            e.preventDefault();
            void send();
          }}
        >
          <label>
            <span className="sr-only">Mensagem</span>
            <textarea
              value={body}
              rows={2}
              maxLength={chatLimits.body}
              placeholder="Escreva uma mensagem"
              onChange={(e) => setBody(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === 'Enter' && !e.shiftKey) {
                  e.preventDefault();
                  void send();
                }
              }}
            />
            <FieldError fields={fields} name="body" />
          </label>
          <button type="submit" className="program-primary" disabled={busy || !body.trim()}>
            Enviar
          </button>
        </form>
      )}
    </article>
  );
}

function Reports({reports, reload}: {reports: ChatReport[] | null; reload: () => void}) {
  const [notice, setNotice] = useState('');
  async function act(action: 'hide' | 'resolve', r: ChatReport) {
    try {
      await call(null, {action, data: {room: r.message.room, id: r.message.id}});
      setNotice(action === 'hide' ? 'Mensagem ocultada e denúncias encerradas.' : 'Mensagem mantida e denúncias encerradas.');
      reload();
    } catch (e) {
      setNotice((e as Error).message);
    }
  }
  if (!reports) return <p className="program-empty">Carregando denúncias…</p>;
  return (
    <article className="program-card">
      <div className="program-card-title">
        <h2>Denúncias abertas</h2>
        <span>{reports.length} mensagem(ns)</span>
      </div>
      {notice && (
        <p className="program-notice" role="status">
          {notice}
        </p>
      )}
      {!reports.length ? (
        <div className="program-empty">
          <h3>Nenhuma denúncia aberta</h3>
          <p>Quando alguém denunciar uma mensagem, ela aparece aqui para revisão.</p>
        </div>
      ) : (
        <ul className="chat-reports">
          {reports.map((r) => (
            <li key={r.message.id}>
              <div className="chat-meta">
                <strong>{r.message.sender}</strong> em <b>{r.roomName ? '# ' + r.roomName : 'conversa'}</b> · <time>{time(r.message.createdAt)}</time>
              </div>
              <p>{r.message.body || '(mensagem apagada)'}</p>
              <small>
                {r.count} denúncia(s): {r.reasons.map((x) => chatReasonLabels[x as keyof typeof chatReasonLabels] || x).join(', ')}
                {r.message.state === 'hidden' ? ' · oculta' : ''}
              </small>
              <div className="program-actions">
                <button type="button" className="program-primary" onClick={() => void act('hide', r)}>
                  Ocultar mensagem
                </button>
                <button type="button" onClick={() => void act('resolve', r)}>
                  Manter mensagem
                </button>
              </div>
            </li>
          ))}
        </ul>
      )}
    </article>
  );
}

const emptyRoom = {name: '', description: '', audience: 'members' as const, posting: 'all' as const};
function Channels({unit, rooms, reload}: {unit: string; rooms: ChatRoom[] | null; reload: () => void}) {
  const [form, setForm] = useState<{
      id?: string;
      version?: number;
      name: string;
      description: string;
      audience: 'members' | 'staff';
      posting: 'all' | 'moderators';
    }>(emptyRoom),
    [fields, setFields] = useState<Record<string, string>>({}),
    [notice, setNotice] = useState(''),
    [busy, setBusy] = useState(false);
  const channels = (rooms || []).filter((r) => r.kind === 'channel' && r.unit === unit);
  async function save() {
    setBusy(true);
    setFields({});
    setNotice('');
    try {
      await call(null, {action: 'room_save', data: {...form, unit}});
      setNotice(form.id ? 'Canal atualizado.' : 'Canal criado.');
      setForm(emptyRoom);
      reload();
    } catch (e) {
      setNotice((e as Error).message);
      if (e instanceof ApiError) setFields(e.fields);
    } finally {
      setBusy(false);
    }
  }
  async function archive(id: string) {
    try {
      await call(null, {action: 'room_archive', data: {id}});
      setNotice('Canal arquivado. As mensagens ficam guardadas e o canal sai das conversas.');
      reload();
    } catch (e) {
      setNotice((e as Error).message);
    }
  }
  return (
    <div className="chat-layout">
      <article className="program-card">
        <div className="program-card-title">
          <h2>Canais desta igreja</h2>
          <span>{channels.length}</span>
        </div>
        {!channels.length ? (
          <div className="program-empty">
            <h3>Nenhum canal ainda</h3>
            <p>Crie um canal geral para a igreja, um mural de avisos ou um canal só para a equipe.</p>
          </div>
        ) : (
          <ul className="chat-reports">
            {channels.map((r) => (
              <li key={r.id}>
                <strong># {r.name}</strong>
                {r.description && <p>{r.description}</p>}
                <small>
                  {r.audience === 'staff' ? 'Só equipe' : 'Todos os adultos da igreja'} · {r.posting === 'moderators' ? 'Só a moderação envia' : 'Todos enviam'}
                </small>
                <div className="program-actions">
                  <button
                    type="button"
                    onClick={() => setForm({id: r.id, version: r.version, name: r.name, description: r.description, audience: r.audience, posting: r.posting})}
                  >
                    Editar
                  </button>
                  <button type="button" onClick={() => void archive(r.id)}>
                    Arquivar
                  </button>
                </div>
              </li>
            ))}
          </ul>
        )}
      </article>
      <article className="program-card">
        <div className="program-card-title">
          <h2>{form.id ? 'Editar canal' : 'Novo canal'}</h2>
        </div>
        <form
          className="program-form"
          onSubmit={(e) => {
            e.preventDefault();
            void save();
          }}
        >
          <fieldset disabled={busy}>
            <label>
              Nome
              <input value={form.name} maxLength={chatLimits.name} onChange={(e) => setForm({...form, name: e.target.value})} />
              <FieldError fields={fields} name="name" />
            </label>
            <label>
              Descrição
              <input value={form.description} maxLength={chatLimits.description} onChange={(e) => setForm({...form, description: e.target.value})} />
            </label>
            <label>
              Quem participa
              <select value={form.audience} onChange={(e) => setForm({...form, audience: e.target.value as 'members' | 'staff'})}>
                <option value="members">Todos os adultos da igreja</option>
                <option value="staff">Só a equipe (liderança, secretaria e administração)</option>
              </select>
            </label>
            <label>
              Quem envia mensagens
              <select value={form.posting} onChange={(e) => setForm({...form, posting: e.target.value as 'all' | 'moderators'})}>
                <option value="all">Todos que participam</option>
                <option value="moderators">Só a moderação (mural de avisos)</option>
              </select>
            </label>
            {notice && (
              <p className={Object.keys(fields).length ? 'program-error' : 'program-notice'} role="status">
                {notice}
              </p>
            )}
            <div className="program-form-footer">
              {form.id && (
                <button type="button" onClick={() => setForm(emptyRoom)}>
                  Cancelar
                </button>
              )}
              <button type="submit" className="program-primary">
                {form.id ? 'Salvar canal' : 'Criar canal'}
              </button>
            </div>
          </fieldset>
        </form>
      </article>
    </div>
  );
}

function Settings() {
  const [s, setS] = useState<ChatSettings | null>(null),
    [words, setWords] = useState(''),
    [notice, setNotice] = useState(''),
    [error, setError] = useState('');
  useEffect(() => {
    call<ChatSettings>({action: 'settings'})
      .then((d) => {
        setS(d);
        setWords(d.blockedWords.join('\n'));
      })
      .catch((e) => setError((e as Error).message));
  }, []);
  async function save(enabled: boolean) {
    if (!s) return;
    setNotice('');
    try {
      const blockedWords = [
        ...new Set(
          words
            .split(/[\n,]/)
            .map((w) => w.trim())
            .filter(Boolean),
        ),
      ];
      const d = await call<ChatSettings>(null, {action: 'settings', data: {enabled, blockedWords, version: s.version}});
      setS(d);
      setWords(d.blockedWords.join('\n'));
      setNotice('Regras do chat salvas.');
    } catch (e) {
      setNotice((e as Error).message);
    }
  }
  if (!s) return <p className={error ? 'program-error' : 'program-empty'}>{error || 'Carregando regras…'}</p>;
  return (
    <article className="program-card">
      <div className="program-card-title">
        <h2>Regras do chat</h2>
        <span>{s.enabled ? 'Chat ligado' : 'Chat desligado'}</span>
      </div>
      <div className="program-form">
        <p>
          Desligar o chat fecha canais e conversas diretas para todos os membros do ministério. As mensagens ficam guardadas. Limite de {chatLimits.burst}{' '}
          mensagens a cada {chatLimits.burstSeconds} segundos por pessoa.
        </p>
        <label>
          Palavras bloqueadas (uma por linha)
          <textarea className="chat-words" rows={6} value={words} onChange={(e) => setWords(e.target.value)} />
        </label>
        {notice && (
          <p className="program-notice" role="status">
            {notice}
          </p>
        )}
        <div className="program-form-footer">
          <button type="button" onClick={() => void save(!s.enabled)}>
            {s.enabled ? 'Desligar chat' : 'Ligar chat'}
          </button>
          <button type="button" className="program-primary" onClick={() => void save(s.enabled)}>
            Salvar palavras
          </button>
        </div>
      </div>
    </article>
  );
}
