'use client';
import {useEffect, useState, type FormEvent} from 'react';
import {settingsUrl} from './lib/settings-navigation';

type Group = {id: string; name: string; description: string; color: string; count: number};
type Member = {id: string; name: string; unit: string | null};
type Found = {person: string; name: string; unit: string | null};
const colors = ['#285c45', '#1b4a3b', '#b8862f', '#7a4a8c', '#2f6f9f', '#a8463c', '#4d7a2a', '#5f6f64'];

async function call<T>(path: string, body?: unknown): Promise<T> {
  const r = await fetch(
    settingsUrl(path),
    body ? {method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify(body)} : {cache: 'no-store'},
  );
  const d = (await r.json().catch(() => ({}))) as T & {error?: string};
  if (!r.ok) throw Error(d.error || 'Não foi possível concluir.');
  return d;
}

/** Configurações › Grupos: Pastores, Lideranças, Mídia… Servem para segmentar push e publicações e marcam a pessoa como Equipe. */
export default function PeopleGroupsSettings() {
  const [groups, setGroups] = useState<Group[] | null>(null),
    [edit, setEdit] = useState<Partial<Group> | null>(null),
    [open, setOpen] = useState(''),
    [members, setMembers] = useState<Member[]>([]),
    [q, setQ] = useState(''),
    [found, setFound] = useState<Found[]>([]),
    [error, setError] = useState(''),
    [notice, setNotice] = useState(''),
    [busy, setBusy] = useState(false);
  const load = () =>
    call<{items: Group[]}>('/api/people-groups')
      .then((d) => setGroups(d.items))
      .catch((e) => {
        setGroups([]);
        setError((e as Error).message);
      });
  useEffect(() => {
    void load();
  }, []);
  useEffect(() => {
    setMembers([]);
    if (!open) return;
    void call<{items: Member[]}>('/api/people-groups?' + new URLSearchParams({members: open}))
      .then((d) => setMembers(d.items))
      .catch(() => setMembers([]));
  }, [open]);
  useEffect(() => {
    if (q.trim().length < 2) return setFound([]);
    const t = setTimeout(() => {
      void call<{items: Found[]}>('/api/users/search?q=' + encodeURIComponent(q.trim()))
        .then((d) => setFound(d.items || []))
        .catch(() => setFound([]));
    }, 300);
    return () => clearTimeout(t);
  }, [q]);
  async function act(body: unknown, ok: string, after?: () => void) {
    setBusy(true);
    setError('');
    setNotice('');
    try {
      await call('/api/people-groups', body);
      setNotice(ok);
      after?.();
      await load();
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  function save(e: FormEvent) {
    e.preventDefault();
    if (!edit) return;
    void act(
      {action: 'save', data: {...(edit.id ? {id: edit.id} : {}), name: edit.name || '', description: edit.description || '', color: edit.color || colors[0]}},
      'Grupo salvo.',
      () => setEdit(null),
    );
  }
  const reloadMembers = () => void call<{items: Member[]}>('/api/people-groups?' + new URLSearchParams({members: open})).then((d) => setMembers(d.items));
  const current = groups?.find((g) => g.id === open);
  return (
    <section className="organization-card people-groups">
      <header>
        <div>
          <h2>Grupos</h2>
          <p>
            Crie grupos como Pastores, Lideranças, Mídia ou Recepção. Use em Comunicação para enviar push e publicações só para eles. Quem está num grupo
            aparece como Equipe em Usuários.
          </p>
        </div>
        <button type="button" className="create" disabled={busy} onClick={() => setEdit({color: colors[0]})}>
          + Novo grupo
        </button>
      </header>
      {error && (
        <p className="pg-error" role="alert">
          {error}
        </p>
      )}
      {notice && (
        <p className="pg-notice" role="status">
          {notice}
        </p>
      )}
      {edit && (
        <form className="pg-form" onSubmit={save}>
          <label>
            Nome
            <input
              autoFocus
              required
              minLength={2}
              maxLength={60}
              value={edit.name || ''}
              onChange={(e) => setEdit({...edit, name: e.target.value})}
              placeholder="Ex.: Pastores"
            />
          </label>
          <label>
            Descrição (opcional)
            <input maxLength={240} value={edit.description || ''} onChange={(e) => setEdit({...edit, description: e.target.value})} />
          </label>
          <div className="pg-colors" role="radiogroup" aria-label="Cor">
            {colors.map((c) => (
              <button
                key={c}
                type="button"
                role="radio"
                aria-checked={edit.color === c}
                aria-label={'Cor ' + c}
                style={{background: c}}
                onClick={() => setEdit({...edit, color: c})}
              />
            ))}
          </div>
          <div className="pg-actions">
            <button type="button" onClick={() => setEdit(null)}>
              Cancelar
            </button>
            <button type="submit" className="create" disabled={busy}>
              Salvar grupo
            </button>
          </div>
        </form>
      )}
      {!groups ? (
        <p>Carregando…</p>
      ) : !groups.length ? (
        <p className="pg-empty">Nenhum grupo ainda.</p>
      ) : (
        <div className="pg-list">
          {groups.map((g) => (
            <article key={g.id} className={open === g.id ? 'on' : ''}>
              <button type="button" className="pg-open" onClick={() => setOpen(open === g.id ? '' : g.id)}>
                <i style={{background: g.color}} aria-hidden />
                <b>{g.name}</b>
                <small>
                  {g.count} {g.count === 1 ? 'pessoa' : 'pessoas'}
                  {g.description ? ' · ' + g.description : ''}
                </small>
              </button>
              <button type="button" onClick={() => setEdit(g)}>
                Editar
              </button>
              <button
                type="button"
                onClick={() => {
                  if (confirm(`Apagar o grupo "${g.name}"? As pessoas continuam cadastradas; só saem do grupo.`))
                    void act({action: 'delete', data: {id: g.id}}, 'Grupo apagado.', () => setOpen(''));
                }}
              >
                Apagar
              </button>
            </article>
          ))}
        </div>
      )}
      {current && (
        <div className="pg-members">
          <h3>Pessoas em {current.name}</h3>
          <label>
            Adicionar pessoa
            <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Nome, e-mail ou CPF" maxLength={80} />
          </label>
          {found.map((f) => (
            <button
              key={f.person}
              type="button"
              className="pg-found"
              disabled={busy || members.some((m) => m.id === f.person)}
              onClick={() =>
                void act({action: 'add', data: {id: current.id, person: f.person}}, f.name + ' entrou no grupo.', () => {
                  setQ('');
                  setFound([]);
                  reloadMembers();
                })
              }
            >
              + {f.name}
              {f.unit ? ' · ' + f.unit : ''}
            </button>
          ))}
          {!members.length ? (
            <p className="pg-empty">Ninguém neste grupo ainda.</p>
          ) : (
            members.map((m) => (
              <div key={m.id} className="pg-member">
                <span>
                  {m.name}
                  {m.unit ? <small> · {m.unit}</small> : null}
                </span>
                <button
                  type="button"
                  disabled={busy}
                  onClick={() => void act({action: 'remove', data: {id: current.id, person: m.id}}, m.name + ' saiu do grupo.', reloadMembers)}
                >
                  Remover
                </button>
              </div>
            ))
          )}
        </div>
      )}
    </section>
  );
}
