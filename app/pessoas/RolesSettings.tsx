'use client';
// Configurações › Cargos e funções: catálogo de cargos, funções por tipo de grupo, ministérios, acessos sugeridos e conferência do texto antigo.
import {useCallback, useEffect, useState, type FormEvent} from 'react';
import {useMinistryLanguage} from '../MinistryLanguage';
import {PersonPicker} from '../PeopleConverts';
import {groupKindLabel, groupKindPlural, type GroupHit, type GroupKind, type RoleFunction, type RolePosition, type RolesCatalog} from '../../shared/church-roles';
import {GroupPicker} from './PersonRoles';
import {loadCatalog, rolesCall} from './roles-api';
import './roles.css';

type Tab = 'positions' | 'functions' | 'ministries' | 'access' | 'review';
type Ministry = {id: string; name: string; kind: string; unit: string; unitId: string; leaders: {person: string; name: string; function: string}[]; members: number; teams: {id: string; name: string}[]};
type Team = {id: string; name: string; unitId: string; ministry: string | null};
type Proposal = {id: string; action: 'grant' | 'revoke'; person: string; name: string; template: string; kind: GroupKind; group: string; function: string | null; hasUser: boolean};
type Review = {person: string; name: string; text: string; unit: string; match: {kind: GroupKind; id: string; name: string} | null};
type Member = {id: string; person: string; name: string; function: string; leadership: boolean};

const initials = (n: string) =>
  n
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((x) => x[0])
    .join('')
    .toUpperCase();

export default function RolesSettings() {
  const lang = useMinistryLanguage();
  const [tab, setTab] = useState<Tab>('positions'),
    [catalog, setCatalog] = useState<RolesCatalog | null>(null),
    [notice, setNotice] = useState(''),
    [error, setError] = useState(''),
    [busy, setBusy] = useState(false);
  const reload = useCallback(() => {
    loadCatalog(true)
      .then((c) => {
        setCatalog(c);
        setError('');
      })
      .catch((e) => setError(e.message));
  }, []);
  useEffect(reload, [reload]);
  async function run(action: string, data: Record<string, unknown>, ok: string) {
    setBusy(true);
    setError('');
    setNotice('');
    try {
      await rolesCall(action, data);
      setNotice(ok);
      reload();
      return true;
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Não foi possível concluir.');
      return false;
    } finally {
      setBusy(false);
    }
  }
  const label = lang.t('pessoas.cargo'),
    plural = lang.t('pessoas.cargos');
  const tabs: [Tab, string, number?][] = [
    ['positions', plural],
    ['functions', 'Funções nos grupos'],
    ['ministries', 'Ministérios'],
    ...(catalog?.canApprove ? ([['access', 'Acessos sugeridos', catalog.pendingAccess]] as [Tab, string, number][]) : []),
    ['review', 'Conferir grupos antigos', catalog?.toReview],
  ];
  return (
    <section className="rl-settings rl-shell" aria-label={plural + ' e funções'}>
      <div className="rl-settings-head">
        <div>
          <p className="section-over">PESSOAS</p>
          <h2>{plural} e funções</h2>
          <p>
            {plural} dizem o que a pessoa é na igreja (pode ter mais de um). Funções dizem o que ela faz em cada célula, rede ou ministério. Funções de liderança sugerem um acesso, que
            só vale depois que um administrador confirma.
          </p>
        </div>
      </div>
      <nav className="rl-tabs" role="tablist" aria-label="Seções">
        {tabs.map(([id, l, n]) => (
          <button key={id} type="button" role="tab" aria-selected={tab === id} onClick={() => (setTab(id), setNotice(''), setError(''))}>
            {l}
            {!!n && <em>{n}</em>}
          </button>
        ))}
      </nav>
      {notice && (
        <p className="rl-notice" role="status">
          {notice}
        </p>
      )}
      {error && (
        <p className="rl-error" role="alert">
          {error}
        </p>
      )}
      {!catalog && !error && <p className="rl-muted">Carregando…</p>}
      {catalog && tab === 'positions' && <Positions catalog={catalog} label={label} plural={plural} busy={busy} run={run} />}
      {catalog && tab === 'functions' && <Functions catalog={catalog} busy={busy} run={run} />}
      {catalog && tab === 'ministries' && <Ministries canManage={catalog.canManage} functions={catalog.functions} onChange={reload} />}
      {catalog && tab === 'access' && <Access onChange={reload} />}
      {catalog && tab === 'review' && <ReviewList onChange={reload} />}
    </section>
  );
}

function NameSettings({label, plural}: {label: string; plural: string}) {
  const lang = useMinistryLanguage();
  const [one, setOne] = useState(label),
    [many, setMany] = useState(plural),
    [msg, setMsg] = useState(''),
    [busy, setBusy] = useState(false);
  useEffect(() => {
    setOne(label);
    setMany(plural);
  }, [label, plural]);
  async function save(e: FormEvent) {
    e.preventDefault();
    if (!lang.state) return;
    setBusy(true);
    setMsg('');
    try {
      await lang.save({...lang.state.labels, 'pessoas.cargo': one.trim(), 'pessoas.cargos': many.trim()}, lang.state.version);
      setMsg('Nome atualizado em todo o painel e no app.');
    } catch (err) {
      setMsg(err instanceof Error ? err.message : 'Não foi possível salvar.');
    } finally {
      setBusy(false);
    }
  }
  const suggestions: [string, string][] = [
    ['Cargo', 'Cargos'],
    ['Título', 'Títulos'],
    ['Ofício', 'Ofícios'],
    ['Ministério', 'Ministérios'],
  ];
  return (
    <form className="rl-card" onSubmit={save}>
      <h3>Como a sua igreja chama</h3>
      <p>Use o nome que a igreja já usa. Ele aparece no cadastro, na ficha, nos filtros e no app.</p>
      <div className="rl-teams" aria-label="Sugestões">
        {suggestions.map(([a, b]) => (
          <button key={a} type="button" className={'rl-team' + (one === a ? ' on' : '')} onClick={() => (setOne(a), setMany(b))} disabled={!lang.state?.canManage}>
            {a}
          </button>
        ))}
      </div>
      <div className="rl-name-form">
        <label>
          No singular
          <input value={one} maxLength={48} onChange={(e) => setOne(e.target.value)} disabled={!lang.state?.canManage} />
        </label>
        <label>
          No plural
          <input value={many} maxLength={48} onChange={(e) => setMany(e.target.value)} disabled={!lang.state?.canManage} />
        </label>
        <button type="submit" className="rl-primary" disabled={busy || !lang.state?.canManage || one.trim().length < 2 || many.trim().length < 2 || (one === label && many === plural)}>
          {busy ? 'Salvando…' : 'Salvar nome'}
        </button>
      </div>
      {msg && <p className="rl-muted">{msg}</p>}
      {!lang.state?.canManage && <p className="rl-muted">Só o dono e administradores mudam este nome.</p>}
    </form>
  );
}

type Run = (action: string, data: Record<string, unknown>, ok: string) => Promise<boolean>;

function Positions({catalog, label, plural, busy, run}: {catalog: RolesCatalog; label: string; plural: string; busy: boolean; run: Run}) {
  const [edit, setEdit] = useState<Partial<RolePosition> | null>(null);
  const active = catalog.positions.filter((p) => p.active),
    archived = catalog.positions.filter((p) => !p.active);
  async function save(e: FormEvent) {
    e.preventDefault();
    if (!edit) return;
    if (
      await run(
        'position.save',
        {id: edit.id || '', name: edit.name || '', nameFemale: edit.nameFemale || '', pastoral: !!edit.pastoral, showInApp: edit.showInApp !== false, version: edit.version},
        edit.id ? label + ' atualizado.' : label + ' criado. Já pode ser usado no cadastro das pessoas.',
      )
    )
      setEdit(null);
  }
  function move(i: number, d: number) {
    const ids = active.map((p) => p.id);
    [ids[i], ids[i + d]] = [ids[i + d]!, ids[i]!];
    void run('position.order', {ids}, 'Ordem atualizada. É a ordem usada na página Liderança do app.');
  }
  const form = (
    <form className="rl-form" onSubmit={save}>
      <label>
        Nome
        <input value={edit?.name || ''} maxLength={60} required autoFocus placeholder="Ex.: Pastor" onChange={(e) => setEdit({...edit, name: e.target.value})} />
      </label>
      <label>
        Nome no feminino (opcional)
        <input value={edit?.nameFemale || ''} maxLength={60} placeholder="Ex.: Pastora" onChange={(e) => setEdit({...edit, nameFemale: e.target.value})} />
      </label>
      <label className="rl-check">
        <input type="checkbox" checked={!!edit?.pastoral} onChange={(e) => setEdit({...edit, pastoral: e.target.checked})} />
        <span>
          Conta como pastor
          <small>Pode agendar atendimentos com qualquer pessoa na Agenda pastoral e aparece primeiro na página Liderança.</small>
        </span>
      </label>
      <label className="rl-check">
        <input type="checkbox" checked={edit?.showInApp !== false} onChange={(e) => setEdit({...edit, showInApp: e.target.checked})} />
        <span>
          Mostrar na página Liderança do app
          <small>Os membros veem o nome e podem enviar mensagem. O telefone só aparece se a pessoa autorizar.</small>
        </span>
      </label>
      <div className="rl-form-actions">
        <button type="button" onClick={() => setEdit(null)}>
          Cancelar
        </button>
        <button type="submit" className="rl-primary" disabled={busy || (edit?.name || '').trim().length < 2}>
          {edit?.id ? 'Salvar' : 'Criar ' + label.toLowerCase()}
        </button>
      </div>
    </form>
  );
  const row = (p: RolePosition, i: number, list: RolePosition[]) =>
    edit?.id === p.id ? (
      <div key={p.id}>{form}</div>
    ) : (
      <div key={p.id} className={'rl-row' + (p.active ? '' : ' off')}>
        <div className="rl-order">
          {p.active && catalog.canManage && (
            <>
              <button type="button" aria-label={'Subir ' + p.name} disabled={busy || i === 0} onClick={() => move(i, -1)}>
                ▲
              </button>
              <button type="button" aria-label={'Descer ' + p.name} disabled={busy || i === list.length - 1} onClick={() => move(i, 1)}>
                ▼
              </button>
            </>
          )}
        </div>
        <div className="rl-row-main">
          <b>
            {p.name}
            {p.nameFemale ? ' / ' + p.nameFemale : ''}
          </b>
          <div className="rl-tags">
            {p.pastoral && <span className="rl-tag gold">Pastoral</span>}
            {p.showInApp ? <span className="rl-tag">Aparece no app</span> : <span className="rl-tag grey">Não aparece no app</span>}
            {!p.active && <span className="rl-tag grey">Arquivado</span>}
          </div>
        </div>
        <span className="rl-count">{p.count === 1 ? '1 pessoa' : p.count + ' pessoas'}</span>
        {catalog.canManage && (
          <div className="rl-actions">
            <button type="button" disabled={busy || !!edit} onClick={() => setEdit(p)}>
              Editar
            </button>
            <button
              type="button"
              disabled={busy}
              onClick={() =>
                (p.active ? window.confirm('Arquivar "' + p.name + '"? As ' + p.count + ' pessoas com este ' + label.toLowerCase() + ' ficam com ele no histórico.') : true) &&
                void run('position.save', {...p, active: !p.active}, p.active ? label + ' arquivado.' : label + ' reativado.')
              }
            >
              {p.active ? 'Arquivar' : 'Reativar'}
            </button>
          </div>
        )}
      </div>
    );
  return (
    <>
      <NameSettings label={label} plural={plural} />
      <div className="rl-card">
        <div className="rl-block-head">
          <h3>{plural} da igreja</h3>
          {catalog.canManage && !edit && (
            <button type="button" className="rl-primary rl-link-btn" onClick={() => setEdit({showInApp: true})} disabled={busy}>
              ＋ Novo {label.toLowerCase()}
            </button>
          )}
        </div>
        {edit && !edit.id && form}
        <div className="rl-table">{active.map((p, i) => row(p, i, active))}</div>
        {!!archived.length && (
          <>
            <h3>Arquivados</h3>
            <div className="rl-table">{archived.map((p, i) => row(p, i, archived))}</div>
          </>
        )}
      </div>
    </>
  );
}

function Functions({catalog, busy, run}: {catalog: RolesCatalog; busy: boolean; run: Run}) {
  const [edit, setEdit] = useState<Partial<RoleFunction> | null>(null);
  const core = ['leader', 'supervisor', 'member', 'participant'];
  async function save(e: FormEvent) {
    e.preventDefault();
    if (!edit) return;
    const ok = await run(
      'function.save',
      {
        id: edit.id || '',
        kind: edit.kind,
        name: edit.name || '',
        nameFemale: edit.nameFemale || '',
        leadership: !!edit.leadership,
        template: edit.leadership ? edit.template || '' : '',
        active: edit.active !== false,
        version: edit.version,
      },
      edit.id ? 'Função atualizada.' : 'Função criada.',
    );
    if (ok) setEdit(null);
  }
  const form = (
    <form className="rl-form" onSubmit={save}>
      <label>
        Nome
        <input value={edit?.name || ''} maxLength={60} required autoFocus placeholder="Ex.: Vice-líder" onChange={(e) => setEdit({...edit, name: e.target.value})} />
      </label>
      <label>
        Nome no feminino (opcional)
        <input value={edit?.nameFemale || ''} maxLength={60} onChange={(e) => setEdit({...edit, nameFemale: e.target.value})} />
      </label>
      <label className="rl-check">
        <input type="checkbox" checked={!!edit?.leadership} onChange={(e) => setEdit({...edit, leadership: e.target.checked})} />
        <span>
          É função de liderança
          <small>Aparece no organograma, na página Liderança do app e pode sugerir um acesso.</small>
        </span>
      </label>
      {edit?.leadership && (
        <label>
          Acesso sugerido
          <select value={edit.template || ''} onChange={(e) => setEdit({...edit, template: e.target.value})}>
            <option value="">Nenhum</option>
            {catalog.templates.map((t) => (
              <option key={t.code} value={t.code}>
                {t.label}
              </option>
            ))}
          </select>
        </label>
      )}
      {edit?.leadership && edit.template && (
        <p className="rl-hint" style={{gridColumn: '1/-1'}}>
          O acesso vale só para o grupo da pessoa ({edit.kind === 'ministry' ? 'as equipes de escala ligadas ao ministério' : edit.kind === 'cell' ? 'a própria célula' : 'a própria rede'}) e só
          depois que o dono ou um administrador confirmar.
        </p>
      )}
      <div className="rl-form-actions">
        <button type="button" onClick={() => setEdit(null)}>
          Cancelar
        </button>
        <button type="submit" className="rl-primary" disabled={busy || (edit?.name || '').trim().length < 2}>
          {edit?.id ? 'Salvar' : 'Criar função'}
        </button>
      </div>
    </form>
  );
  return (
    <div className="rl-kinds">
      {(['cell', 'network', 'ministry'] as GroupKind[]).map((k) => (
        <div key={k} className="rl-card">
          <div className="rl-block-head">
            <h3>{groupKindPlural[k]}</h3>
            {catalog.canManage && !edit && (
              <button type="button" className="rl-link" onClick={() => setEdit({kind: k})} disabled={busy}>
                ＋ Nova função
              </button>
            )}
          </div>
          {edit && !edit.id && edit.kind === k && form}
          <div className="rl-table">
            {catalog.functions
              .filter((f) => f.kind === k)
              .map((f) =>
                edit?.id === f.id ? (
                  <div key={f.id}>{form}</div>
                ) : (
                  <div key={f.id} className={'rl-row' + (f.active ? '' : ' off')}>
                    <div className="rl-row-main">
                      <b>
                        {f.leadership && <span className="rl-star">★ </span>}
                        {f.name}
                        {f.nameFemale ? ' / ' + f.nameFemale : ''}
                      </b>
                      <small>
                        {f.count === 1 ? '1 pessoa' : f.count + ' pessoas'}
                        {f.leadership ? ' · ' + (f.templateLabel ? 'acesso sugerido: ' + f.templateLabel : 'sem acesso sugerido') : ''}
                        {!f.active ? ' · arquivada' : ''}
                      </small>
                    </div>
                    {catalog.canManage && (
                      <div className="rl-actions">
                        <button type="button" disabled={busy || !!edit} onClick={() => setEdit(f)}>
                          Editar
                        </button>
                        {!core.includes(f.system || '') && (
                          <button type="button" disabled={busy} onClick={() => void run('function.save', {...f, template: f.template || '', active: !f.active}, f.active ? 'Função arquivada.' : 'Função reativada.')}>
                            {f.active ? 'Arquivar' : 'Reativar'}
                          </button>
                        )}
                      </div>
                    )}
                  </div>
                ),
              )}
          </div>
        </div>
      ))}
    </div>
  );
}

function Ministries({canManage, functions, onChange}: {canManage: boolean; functions: RoleFunction[]; onChange: () => void}) {
  const [data, setData] = useState<{items: Ministry[]; teams: Team[]} | null>(null),
    [open, setOpen] = useState(''),
    [members, setMembers] = useState<Member[]>([]),
    [fn, setFn] = useState(''),
    [msg, setMsg] = useState(''),
    [busy, setBusy] = useState(false);
  const load = useCallback(() => {
    rolesCall<{items: Ministry[]; teams: Team[]}>(null, undefined, 'view=ministries')
      .then(setData)
      .catch((e) => setMsg(e.message));
  }, []);
  useEffect(load, [load]);
  const loadMembers = useCallback((id: string) => {
    rolesCall<{items: Member[]}>('members', {kind: 'ministry', group: id})
      .then((d) => setMembers(d.items))
      .catch((e) => setMsg(e.message));
  }, []);
  const ministryFns = functions.filter((f) => f.kind === 'ministry' && f.active);
  async function act(action: string, body: Record<string, unknown>, ok: string, id: string) {
    setBusy(true);
    setMsg('');
    try {
      await rolesCall(action, body);
      setMsg(ok);
      load();
      loadMembers(id);
      onChange();
    } catch (e) {
      setMsg(e instanceof Error ? e.message : 'Não foi possível concluir.');
    } finally {
      setBusy(false);
    }
  }
  if (!data) return <p className="rl-muted">{msg || 'Carregando ministérios…'}</p>;
  if (!data.items.length)
    return (
      <div className="rl-empty">
        <b>Nenhum ministério cadastrado</b>
        Cadastre os ministérios e departamentos em Configurações › Serviços e segurança › Ministérios e departamentos.
      </div>
    );
  return (
    <div className="rl-table">
      {msg && <p className="rl-notice">{msg}</p>}
      {data.items.map((m) => {
        const teams = data.teams.filter((t) => t.unitId === m.unitId);
        const linked = new Set(m.teams.map((t) => t.id));
        return (
          <div key={m.id} className="rl-card rl-ministry">
            <div className="rl-ministry-head">
              <div>
                <h3>{m.name}</h3>
                <small>
                  {m.kind === 'ministry' ? 'Ministério' : 'Departamento'} · {m.unit} · {m.members === 1 ? '1 pessoa' : m.members + ' pessoas'}
                </small>
              </div>
              {canManage && (
                <button
                  type="button"
                  className="rl-link"
                  onClick={() => {
                    const next = open === m.id ? '' : m.id;
                    setOpen(next);
                    setFn(ministryFns.find((f) => f.system === 'member')?.id || '');
                    if (next) loadMembers(next);
                  }}
                >
                  {open === m.id ? 'Fechar' : 'Gerenciar pessoas'}
                </button>
              )}
            </div>
            <div className="rl-tags">
              {m.leaders.length ? (
                m.leaders.map((l) => (
                  <span key={l.person + l.function} className="rl-tag gold">
                    ★ {l.function}: {l.name}
                  </span>
                ))
              ) : (
                <span className="rl-tag grey">Sem liderança definida</span>
              )}
            </div>
            <div>
              <small className="rl-picker-kind">Equipes de escala deste ministério</small>
              {teams.length ? (
                <div className="rl-teams">
                  {teams.map((t) => (
                    <label key={t.id} className={'rl-team' + (linked.has(t.id) ? ' on' : '')}>
                      <input
                        type="checkbox"
                        checked={linked.has(t.id)}
                        disabled={!canManage || busy || (!!t.ministry && t.ministry !== m.id)}
                        onChange={(e) =>
                          void act(
                            'ministry.teams',
                            {ministry: m.id, teams: e.target.checked ? [...linked, t.id] : [...linked].filter((x) => x !== t.id)},
                            'Equipes atualizadas. A liderança do ministério passa a valer para estas escalas.',
                            m.id,
                          )
                        }
                      />
                      {t.name}
                      {t.ministry && t.ministry !== m.id ? ' (outro ministério)' : ''}
                    </label>
                  ))}
                </div>
              ) : (
                <p className="rl-muted">Nenhuma equipe de escala nesta igreja.</p>
              )}
            </div>
            {open === m.id && (
              <div className="rl-members">
                <ul>
                  {members.map((x) => (
                    <li key={x.id}>
                      <b>{x.name}</b>
                      <small>
                        {x.leadership ? '★ ' : ''}
                        {x.function}
                      </small>
                      <button
                        type="button"
                        className="rl-x"
                        aria-label={'Tirar ' + x.name}
                        disabled={busy}
                        onClick={() => window.confirm('Tirar ' + x.name + ' de ' + m.name + '?') && void act('unassign', {id: x.id}, x.name + ' saiu de ' + m.name + '.', m.id)}
                      >
                        ×
                      </button>
                    </li>
                  ))}
                  {!members.length && <p className="rl-muted">Ninguém neste ministério ainda.</p>}
                </ul>
                <div className="rl-inline">
                  <label>
                    Função
                    <select value={fn} onChange={(e) => setFn(e.target.value)}>
                      {ministryFns.map((f) => (
                        <option key={f.id} value={f.id}>
                          {f.leadership ? '★ ' : ''}
                          {f.name}
                        </option>
                      ))}
                    </select>
                  </label>
                  <PersonPicker
                    unitId={m.unitId}
                    label="Adicionar pessoa"
                    onPick={(p) => void act('assign', {person: p.id, kind: 'ministry', group: m.id, function: fn}, p.name + ' entrou em ' + m.name + '.', m.id)}
                  />
                </div>
              </div>
            )}
          </div>
        );
      })}
    </div>
  );
}

function Access({onChange}: {onChange: () => void}) {
  const [items, setItems] = useState<Proposal[] | null>(null),
    [msg, setMsg] = useState(''),
    [err, setErr] = useState(''),
    [busy, setBusy] = useState('');
  const load = useCallback(() => {
    rolesCall<{items: Proposal[]}>(null, undefined, 'view=access')
      .then((d) => setItems(d.items))
      .catch((e) => setErr(e.message));
  }, []);
  useEffect(load, [load]);
  async function decide(p: Proposal, approve: boolean) {
    setBusy(p.id);
    setMsg('');
    setErr('');
    try {
      const r = await rolesCall<{changed?: string[]; skipped?: string[]}>(approve ? 'access.approve' : 'access.dismiss', {id: p.id});
      setMsg(
        approve
          ? (p.action === 'grant' ? 'Acesso concedido a ' : 'Acesso retirado de ') +
              p.name +
              '.' +
              (r.skipped?.length ? ' Alguns itens já tinham acesso mais amplo e foram mantidos como estavam.' : '')
          : 'Sugestão dispensada. Nada foi alterado.',
      );
      load();
      onChange();
    } catch (e) {
      setErr(e instanceof Error ? e.message : 'Não foi possível concluir.');
    } finally {
      setBusy('');
    }
  }
  if (!items) return <p className="rl-muted">{err || 'Carregando…'}</p>;
  return (
    <div className="rl-table">
      {msg && <p className="rl-notice">{msg}</p>}
      {err && <p className="rl-error">{err}</p>}
      {!items.length && (
        <div className="rl-empty">
          <b>Nenhum acesso aguardando confirmação</b>
          Quando alguém assumir ou deixar uma função de liderança, a sugestão aparece aqui.
        </div>
      )}
      {items.map((p) => (
        <div key={p.id} className={'rl-proposal' + (p.action === 'revoke' ? ' revoke' : '')}>
          <span className="rl-avatar" aria-hidden="true">
            {initials(p.name)}
          </span>
          <div>
            <b>{p.name}</b>
            <p>
              {p.action === 'grant' ? 'Assumiu ' : 'Deixou '}
              {p.function ? p.function.toLowerCase() + ' · ' : ''}
              {p.group}
            </p>
            <p>
              {p.action === 'grant' ? 'Conceder' : 'Retirar'} acesso <b>{p.template}</b> {p.kind === 'cell' ? 'só desta célula' : p.kind === 'network' ? 'só desta rede' : 'só das escalas deste ministério'}.
            </p>
            {!p.hasUser && p.action === 'grant' && <p className="rl-warn">Sem usuário na equipe: convide a pessoa em Usuários e permissões antes de confirmar.</p>}
          </div>
          <div className="rl-actions">
            <button type="button" disabled={!!busy} onClick={() => void decide(p, false)}>
              Dispensar
            </button>
            <button type="button" className="rl-primary" disabled={!!busy || (!p.hasUser && p.action === 'grant')} onClick={() => void decide(p, true)}>
              {busy === p.id ? 'Confirmando…' : p.action === 'grant' ? 'Confirmar acesso' : 'Confirmar retirada'}
            </button>
          </div>
        </div>
      ))}
    </div>
  );
}

function ReviewList({onChange}: {onChange: () => void}) {
  const [items, setItems] = useState<Review[] | null>(null),
    [choose, setChoose] = useState(''),
    [msg, setMsg] = useState(''),
    [busy, setBusy] = useState(false);
  const load = useCallback(() => {
    rolesCall<{items: Review[]}>(null, undefined, 'view=review')
      .then((d) => setItems(d.items))
      .catch((e) => setMsg(e.message));
  }, []);
  useEffect(load, [load]);
  async function act(action: string, data: Record<string, unknown>, ok: string) {
    setBusy(true);
    setMsg('');
    try {
      await rolesCall(action, data);
      setMsg(ok);
      setChoose('');
      load();
      onChange();
    } catch (e) {
      setMsg(e instanceof Error ? e.message : 'Não foi possível concluir.');
    } finally {
      setBusy(false);
    }
  }
  async function linkAll() {
    const list = (items || []).filter((x) => x.match);
    if (!list.length || !window.confirm('Vincular ' + list.length + ' cadastros aos grupos com o mesmo nome?')) return;
    setBusy(true);
    let n = 0;
    for (const x of list) {
      try {
        await rolesCall('review.link', {person: x.person, kind: x.match!.kind, group: x.match!.id});
        n++;
      } catch {
        /* segue para o próximo */
      }
    }
    setBusy(false);
    setMsg(n + ' cadastros vinculados.');
    load();
    onChange();
  }
  if (!items) return <p className="rl-muted">{msg || 'Carregando…'}</p>;
  const matches = items.filter((x) => x.match).length;
  return (
    <div className="rl-card">
      <h3>Texto antigo de “Grupo / ministério”</h3>
      <p>
        Antes, o grupo era escrito à mão. Aqui estão os cadastros com texto e sem grupo vinculado. Vincule ao grupo certo ou limpe o texto. Nada é apagado sem a sua escolha.
      </p>
      {msg && <p className="rl-notice">{msg}</p>}
      {!!matches && (
        <div>
          <button type="button" className="rl-primary rl-link-btn" disabled={busy} onClick={() => void linkAll()}>
            Vincular os {matches} que batem com um grupo
          </button>
        </div>
      )}
      {!items.length && (
        <div className="rl-empty">
          <b>Tudo conferido</b>
          Nenhum cadastro com texto antigo sem grupo.
        </div>
      )}
      <div className="rl-table">
        {items.map((x) => (
          <div key={x.person} className="rl-row">
            <span className="rl-avatar" aria-hidden="true">
              {initials(x.name)}
            </span>
            <div className="rl-row-main">
              <b>{x.name}</b>
              <small>
                Escrito: “{x.text}” · {x.unit}
              </small>
              {choose === x.person && (
                <GroupPicker
                  autoFocus
                  onPick={(g: GroupHit) => void act('review.link', {person: x.person, kind: g.kind, group: g.id}, x.name + ' vinculado a ' + g.name + '.')}
                />
              )}
            </div>
            <span />
            <div className="rl-actions">
              {x.match && (
                <button
                  type="button"
                  className="rl-primary"
                  disabled={busy}
                  onClick={() => void act('review.link', {person: x.person, kind: x.match!.kind, group: x.match!.id}, x.name + ' vinculado a ' + x.match!.name + '.')}
                >
                  Vincular a {x.match.name}
                </button>
              )}
              <button type="button" disabled={busy} onClick={() => setChoose(choose === x.person ? '' : x.person)}>
                {choose === x.person ? 'Fechar' : 'Escolher grupo'}
              </button>
              <button type="button" disabled={busy} onClick={() => void act('review.clear', {person: x.person}, 'Texto removido de ' + x.name + '.')}>
                Limpar texto
              </button>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
