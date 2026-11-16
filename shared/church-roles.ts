// Grupos, Cargos e Funções: tipos e textos comuns ao painel e ao app.
export type GroupKind = 'cell' | 'network' | 'ministry';
export type RolePosition = {id: string; name: string; nameFemale: string; pastoral: boolean; showInApp: boolean; sort: number; active: boolean; system: boolean; version: number; count: number};
export type RoleFunction = {
  id: string;
  kind: GroupKind;
  name: string;
  nameFemale: string;
  leadership: boolean;
  template: string | null;
  templateLabel: string | null;
  sort: number;
  active: boolean;
  system: string | null;
  version: number;
  count: number;
};
export type RolesCatalog = {
  canManage: boolean;
  canApprove: boolean;
  label: string;
  labelPlural: string;
  positions: RolePosition[];
  functions: RoleFunction[];
  templates: {code: string; label: string; description: string}[];
  pendingAccess: number;
  toReview: number;
};
export type PersonPosition = {id: string; positionId: string; name: string; pastoral: boolean; since: string | null; unit: string | null};
export type PersonGroup = {
  id: string | null;
  kind: GroupKind | 'scale' | 'kids';
  groupId: string | null;
  group: string;
  functionId: string | null;
  function: string;
  leadership: boolean;
  since: string | null;
  editable: boolean;
};
export type PersonRoles = {positions: PersonPosition[]; groups: PersonGroup[]; canEdit: boolean};
export type GroupHit = {kind: GroupKind; id: string; name: string; unit: string; detail: string};

export const groupKindLabel: Record<PersonGroup['kind'], string> = {
  network: 'Rede',
  cell: 'Célula',
  ministry: 'Ministério',
  scale: 'Escala',
  kids: 'Kids',
};
export const groupKindPlural: Record<GroupKind, string> = {cell: 'Células', network: 'Redes', ministry: 'Ministérios e departamentos'};

export const rolesActions = [
  'catalog',
  'position.save',
  'position.order',
  'function.save',
  'person',
  'person.position.add',
  'person.position.end',
  'assign',
  'unassign',
  'cell.leave',
  'groups.search',
  'ministries',
  'ministry.teams',
  'members',
  'access.list',
  'access.approve',
  'access.dismiss',
  'review.list',
  'review.link',
  'review.clear',
] as const;

/** Mensagem clara para cada recusa do banco. */
export function rolesError(code: string, message: string): {message: string; status: number} {
  if (/roles_no_user/.test(message))
    return {message: 'Esta pessoa ainda não tem usuário na equipe. Convide-a em Configurações › Usuários e permissões e confirme o acesso depois.', status: 409};
  if (code === '42501' || /denied/.test(message)) return {message: 'Você não tem permissão para esta ação.', status: 403};
  if (code === '40001' || /changed/.test(message)) return {message: 'Outra pessoa alterou este item. Atualize a página e tente de novo.', status: 409};
  if (code === '23505') return {message: 'Já existe um item com este nome.', status: 409};
  if (/template_missing/.test(message)) return {message: 'O modelo de acesso desta função não existe mais. Escolha outro em Funções.', status: 409};
  return {message: 'Revise os dados informados.', status: 400};
}

/** "desde 2015" / "" */
export const sinceLabel = (iso: string | null | undefined) => (iso && /^\d{4}/.test(iso) ? 'desde ' + iso.slice(0, 4) : '');
