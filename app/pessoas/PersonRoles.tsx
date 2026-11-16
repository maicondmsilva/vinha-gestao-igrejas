'use client';
// Cargos e funções da pessoa: chips de cargo e a lista de grupos com a função. Usado na ficha e no cadastro.
import {useCallback, useEffect, useState} from 'react';
import {groupKindLabel, sinceLabel, type GroupHit, type GroupKind, type PersonGroup, type PersonRoles as Roles, type RolesCatalog} from '../../shared/church-roles';
import {loadCatalog, rolesCall} from './roles-api';
import './roles.css';

export {rolesCall, loadCatalog};

/** Busca de células, redes e ministérios cadastrados (substitui o antigo texto livre "Grupo / ministério"). */
export function GroupPicker({onPick, kinds, autoFocus}: {onPick: (g: GroupHit) => void; kinds?: GroupKind[]; autoFocus?: boolean}) {
  const [q, setQ] = useState(''),
    [items, setItems] = useState<GroupHit[] | null>(null);
  useEffect(() => {
    const c = new AbortController();
    const t = setTimeout(() => {
      rolesCall<{items: GroupHit[]}>(null, undefined, 'q=' + encodeURIComponent(q.trim()))
        .then((d) => !c.signal.aborted && setItems(d.items.filter((x) => !kinds || kinds.includes(x.kind))))
        .catch(() => !c.signal.aborted && setItems([]));
    }, 220);
    return () => {
      clearTimeout(t);
      c.abort();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [q, kinds?.join(',')]);
  const groups = (['network', 'cell', 'ministry'] as GroupKind[]).map((k) => [k, (items || []).filter((x) => x.kind === k)] as const).filter(([, l]) => l.length);
  return (
    <div className="rl-picker">
      <input type="search" value={q} autoFocus={autoFocus} placeholder="Buscar célula, rede ou ministério" aria-label="Buscar grupo" onChange={(e) => setQ(e.target.value)} />
      <div className="rl-picker-list" role="listbox">
        {items === null && <p className="rl-muted">Carregando grupos…</p>}
        {items !== null && !items.length && <p className="rl-muted">Nenhum grupo encontrado. Cadastre células em Células e ministérios em Configurações › Serviços.</p>}
        {groups.map(([k, list]) => (
          <div key={k}>
            <small className="rl-picker-kind">{k === 'ministry' ? 'Ministérios e departamentos' : k === 'cell' ? 'Células' : 'Redes'}</small>
            {list.map((g) => (
              <button key={g.id} type="button" role="option" aria-selected="false" onClick={() => onPick(g)}>
                <b>{g.name}</b>
                <span>
                  {g.detail} · {g.unit}
                </span>
              </button>
            ))}
          </div>
        ))}
      </div>
    </div>
  );
}

export type StagedRoles = {
  positions: {positionId: string; name: string; since: string}[];
  groups: {kind: GroupKind; groupId: string; group: string; functionId: string; function: string; leadership: boolean}[];
};
export const emptyStaged: StagedRoles = {positions: [], groups: []};

/** Aplica o que foi escolhido no cadastro de uma pessoa nova, depois de salvar. */
export async function applyStaged(person: string, staged: StagedRoles) {
  for (const p of staged.positions) await rolesCall('person.position.add', {person, position: p.positionId, since: p.since ? p.since + '-01-01' : ''});
  for (const g of staged.groups) await rolesCall('assign', {person, kind: g.kind, group: g.groupId, function: g.functionId});
}

type Props = {person?: string; editable?: boolean; staged?: StagedRoles; onStaged?: (s: StagedRoles) => void; onChanged?: () => void};

export default function PersonRoles({person, editable = false, staged, onStaged, onChanged}: Props) {
  const [catalog, setCatalog] = useState<RolesCatalog | null>(null),
    [roles, setRoles] = useState<Roles | null>(null),
    [error, setError] = useState(''),
    [busy, setBusy] = useState(false),
    [adding, setAdding] = useState<'' | 'position' | 'group'>(''),
    [posId, setPosId] = useState(''),
    [posYear, setPosYear] = useState(''),
    [hit, setHit] = useState<GroupHit | null>(null),
    [fnId, setFnId] = useState('');
  const live = !!person;
  useEffect(() => {
    loadCatalog()
      .then(setCatalog)
      .catch((e) => setError(e.message));
  }, []);
  const load = useCallback(() => {
    if (!person) return;
    rolesCall<Roles>(null, undefined, 'person=' + person)
      .then((d) => {
        setRoles(d);
        setError('');
      })
      .catch((e) => setError(e.message));
  }, [person]);
  useEffect(load, [load]);

  const canEdit = live ? editable && !!roles?.canEdit : editable;
  const label = catalog?.label || 'Cargo',
    plural = catalog?.labelPlural || 'Cargos';
  const positions = live
    ? roles?.positions || []
    : (staged?.positions || []).map((p) => ({id: p.positionId, positionId: p.positionId, name: p.name, pastoral: false, since: p.since ? p.since + '-01-01' : null, unit: null}));
  const groups: PersonGroup[] = live
    ? roles?.groups || []
    : (staged?.groups || []).map((g) => ({id: g.groupId + g.functionId, kind: g.kind, groupId: g.groupId, group: g.group, functionId: g.functionId, function: g.function, leadership: g.leadership, since: null, editable: true}));
  const freePositions = (catalog?.positions || []).filter((p) => p.active && !positions.some((x) => x.positionId === p.id));
  const kindFunctions = (catalog?.functions || []).filter((f) => f.active && hit && f.kind === hit.kind);

  async function act(action: string, data: Record<string, unknown>) {
    setBusy(true);
    setError('');
    try {
      const d = await rolesCall<Roles>(action, data);
      setRoles(d);
      onChanged?.();
      return true;
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Não foi possível concluir.');
      return false;
    } finally {
      setBusy(false);
    }
  }
  function reset() {
    setAdding('');
    setPosId('');
    setPosYear('');
    setHit(null);
    setFnId('');
  }
  async function addPosition() {
    const pos = catalog?.positions.find((p) => p.id === posId);
    if (!pos) return;
    const year = /^\d{4}$/.test(posYear) ? posYear : '';
    if (!live) {
      onStaged?.({...(staged || emptyStaged), positions: [...(staged?.positions || []), {positionId: pos.id, name: pos.name, since: year}]});
      return reset();
    }
    if (await act('person.position.add', {person, position: pos.id, since: year ? year + '-01-01' : ''})) reset();
  }
  async function addGroup() {
    const fn = catalog?.functions.find((f) => f.id === fnId);
    if (!hit || !fn) return;
    if (!live) {
      onStaged?.({
        ...(staged || emptyStaged),
        groups: [...(staged?.groups || []), {kind: hit.kind, groupId: hit.id, group: hit.name, functionId: fn.id, function: fn.name, leadership: fn.leadership}],
      });
      return reset();
    }
    if (await act('assign', {person, kind: hit.kind, group: hit.id, function: fn.id})) reset();
  }
  function removePosition(id: string, name: string) {
    if (!live) return onStaged?.({...(staged || emptyStaged), positions: (staged?.positions || []).filter((p) => p.positionId !== id)});
    if (window.confirm('Encerrar o ' + label.toLowerCase() + ' "' + name + '"? Ele continua no histórico com a data de hoje.')) void act('person.position.end', {id});
  }
  function removeGroup(g: PersonGroup) {
    if (!live) return onStaged?.({...(staged || emptyStaged), groups: (staged?.groups || []).filter((x) => x.groupId + x.functionId !== g.id)});
    const msg = g.id ? 'Encerrar a função "' + g.function + '" em ' + g.group + '?' : 'Tirar a pessoa da célula ' + g.group + '?';
    if (!window.confirm(msg)) return;
    if (g.id) void act('unassign', {id: g.id});
    else if (g.kind === 'cell' && g.groupId) void act('cell.leave', {person, group: g.groupId});
  }

  return (
    <div className="rl-person">
      {error && (
        <p className="rl-error" role="alert">
          {error}
        </p>
      )}
      <div className="rl-block">
        <div className="rl-block-head">
          <b>{plural}</b>
          {canEdit && adding !== 'position' && (
            <button type="button" className="rl-link" onClick={() => (reset(), setAdding('position'))} disabled={busy || !freePositions.length}>
              ＋ Adicionar {label.toLowerCase()}
            </button>
          )}
        </div>
        {live && !roles && !error && <p className="rl-muted">Carregando…</p>}
        {(!live || roles) && !positions.length && adding !== 'position' && <p className="rl-muted">Nenhum {label.toLowerCase()} registrado.</p>}
        {!!positions.length && (
          <ul className="rl-chips">
            {positions.map((p) => (
              <li key={p.id} className={p.pastoral ? 'rl-chip gold' : 'rl-chip'}>
                <span>{p.name}</span>
                {sinceLabel(p.since) && <small>{sinceLabel(p.since)}</small>}
                {canEdit && (
                  <button type="button" aria-label={'Encerrar ' + p.name} title="Encerrar" disabled={busy} onClick={() => removePosition(live ? p.id : p.positionId, p.name)}>
                    ×
                  </button>
                )}
              </li>
            ))}
          </ul>
        )}
        {adding === 'position' && (
          <div className="rl-inline">
            <label>
              {label}
              <select value={posId} onChange={(e) => setPosId(e.target.value)} autoFocus>
                <option value="">Selecione</option>
                {freePositions.map((p) => (
                  <option key={p.id} value={p.id}>
                    {p.name}
                    {p.nameFemale ? ' / ' + p.nameFemale : ''}
                  </option>
                ))}
              </select>
            </label>
            <label className="rl-year">
              Desde (ano)
              <input inputMode="numeric" maxLength={4} placeholder="Opcional" value={posYear} onChange={(e) => setPosYear(e.target.value.replace(/\D/g, ''))} />
            </label>
            <div className="rl-inline-actions">
              <button type="button" onClick={reset}>
                Cancelar
              </button>
              <button type="button" className="rl-primary" disabled={!posId || busy} onClick={() => void addPosition()}>
                Adicionar
              </button>
            </div>
          </div>
        )}
      </div>

      <div className="rl-block">
        <div className="rl-block-head">
          <b>Grupos e funções</b>
          {canEdit && adding !== 'group' && (
            <button type="button" className="rl-link" onClick={() => (reset(), setAdding('group'))} disabled={busy}>
              ＋ Adicionar a um grupo
            </button>
          )}
        </div>
        {(!live || roles) && !groups.length && adding !== 'group' && <p className="rl-muted">Ainda não participa de células, redes ou ministérios.</p>}
        {!!groups.length && (
          <ul className="rl-groups">
            {groups.map((g, i) => (
              <li key={(g.id || g.kind + g.groupId + g.function) + i}>
                <span className={'rl-kind k-' + g.kind}>{groupKindLabel[g.kind]}</span>
                <div>
                  <b>{g.group}</b>
                  <small>
                    {g.leadership && <em className="rl-star">★ </em>}
                    {g.function}
                    {sinceLabel(g.since) ? ' · ' + sinceLabel(g.since) : ''}
                    {!g.editable && g.kind === 'scale' && ' · pelo módulo Escalas'}
                    {!g.editable && g.kind === 'kids' && ' · pela equipe Kids'}
                  </small>
                </div>
                {canEdit && (g.editable || (g.kind === 'cell' && live)) && (
                  <button type="button" className="rl-x" aria-label={'Remover de ' + g.group} title="Remover" disabled={busy} onClick={() => removeGroup(g)}>
                    ×
                  </button>
                )}
              </li>
            ))}
          </ul>
        )}
        {adding === 'group' && (
          <div className="rl-add-group">
            {!hit ? (
              <GroupPicker autoFocus onPick={(g) => (setHit(g), setFnId(''))} />
            ) : (
              <div className="rl-inline">
                <div className="rl-picked">
                  <span className={'rl-kind k-' + hit.kind}>{groupKindLabel[hit.kind]}</span>
                  <b>{hit.name}</b>
                  <button type="button" className="rl-link" onClick={() => setHit(null)}>
                    Trocar
                  </button>
                </div>
                <label>
                  Função
                  <select value={fnId} onChange={(e) => setFnId(e.target.value)} autoFocus>
                    <option value="">Selecione</option>
                    {kindFunctions.map((f) => (
                      <option key={f.id} value={f.id}>
                        {f.leadership ? '★ ' : ''}
                        {f.name}
                        {f.nameFemale ? ' / ' + f.nameFemale : ''}
                      </option>
                    ))}
                  </select>
                </label>
                {catalog?.functions.find((f) => f.id === fnId)?.template && (
                  <p className="rl-hint">Função de liderança: o acesso sugerido vai para confirmação do administrador.</p>
                )}
                <div className="rl-inline-actions">
                  <button type="button" onClick={reset}>
                    Cancelar
                  </button>
                  <button type="button" className="rl-primary" disabled={!fnId || busy} onClick={() => void addGroup()}>
                    Adicionar
                  </button>
                </div>
              </div>
            )}
            {!hit && (
              <div className="rl-inline-actions">
                <button type="button" onClick={reset}>
                  Cancelar
                </button>
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  );
}
