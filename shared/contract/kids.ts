const kidsUuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
export type KidsOperation =
  | 'room'
  | 'class'
  | 'session'
  | 'group'
  | 'assignment'
  | 'sessionState'
  | 'checkin'
  | 'checkout'
  | 'recover'
  | 'hold'
  | 'transfer'
  | 'transferAccept'
  | 'transferCancel';
export type KidsOperationCommand = {requestId: string; action: KidsOperation; id: string; version: number; data: Record<string, unknown>};
export type KidsRoom = {id: string; name: string; location: string; capacity: number; active: boolean; version: number};
export type KidsClass = {id: string; name: string; minMonths: number; maxMonths: number; active: boolean; version: number};
export type KidsSession = {id: string; name: string; startsAt: string; endsAt: string; status: 'draft' | 'open' | 'closed' | 'cancelled'; version: number};
export type KidsGroup = {
  id: string;
  roomId: string;
  classId: string;
  room: string;
  className: string;
  capacity: number;
  occupied: number;
  reserved?: number;
  minStaff: number;
  staffCount: number;
  version: number;
};
export type KidsAssignment = {
  id: string;
  personId: string;
  name: string;
  groupId: string | null;
  role: 'supervisor' | 'reception' | 'teacher' | 'assistant';
  canCare: boolean;
  active: boolean;
  version: number;
};
export type KidsAdult = {id: string; name: string};
export type KidsAdmission = {id: string; name: string; birthDate: string; guardians: KidsAdult[]};
export type KidsPresence = {
  id: string;
  profileId: string;
  name: string;
  groupId: string;
  status: 'present' | 'out';
  version: number;
  inAt: string;
  outAt: string | null;
  hold: boolean;
  holdReason: string;
  transferTo: string | null;
  canAccept: boolean;
  failedAttempts: number;
  receiptExpiresAt: string | null;
  guardians: KidsAdult[];
  care: string | null;
};
export type KidsOperationsPage = {
  unitId: string;
  sessionId: string | null;
  canConfigure: boolean;
  canSupervise: boolean;
  canReceive: boolean;
  canDirectory: boolean;
  updatedAt: string;
  items: KidsPresence[];
  nextCursor: string | null;
  rooms: KidsRoom[];
  classes: KidsClass[];
  sessions: KidsSession[];
  groups: KidsGroup[];
  assignments: KidsAssignment[];
  history: {id: string; action: string; at: string; actor: string; child: string | null; details: Record<string, unknown>}[];
};
const obj = (v: unknown): Record<string, unknown> => {
  if (!v || typeof v !== 'object' || Array.isArray(v)) throw Error('Formato inválido.');
  return v as Record<string, unknown>;
};
const uuid = (v: unknown) => typeof v === 'string' && kidsUuid.test(v);
const text = (v: unknown, min: number, max: number) => {
  if (typeof v !== 'string' || v.trim().length < min || v.length > max || /[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/.test(v)) throw Error('Revise os campos de texto.');
  return v;
};
const integer = (v: unknown, min: number, max: number) => Number.isSafeInteger(v) && Number(v) >= min && Number(v) <= max;
const date = (v: unknown) => typeof v === 'string' && /^\d{4}-\d\d-\d\dT/.test(v) && Number.isFinite(Date.parse(v));
export function kidsOperationCommand(value: unknown): KidsOperationCommand {
  const v = obj(value),
    d = obj(v.data);
  if (Object.keys(v).sort().join(',') !== 'action,data,id,requestId,version' || !uuid(v.id) || !uuid(v.requestId) || !integer(v.version, 0, 2147483646))
    throw Error('Operação inválida.');
  let keys: string[] = [];
  const ids = (...names: string[]) => {
    if (names.some((k) => !uuid(d[k]))) throw Error('Selecione os cadastros vinculados.');
  };
  const bool = (...names: string[]) => {
    if (names.some((k) => typeof d[k] !== 'boolean')) throw Error('Opção inválida.');
  };
  const num = (key: string, min: number, max: number) => {
    if (!integer(d[key], min, max)) throw Error('Informe números inteiros válidos.');
  };
  switch (v.action) {
    case 'room':
      keys = ['name', 'location', 'capacity', 'active'];
      text(d.name, 2, 100);
      text(d.location, 0, 200);
      num('capacity', 1, 500);
      bool('active');
      break;
    case 'class':
      keys = ['name', 'minMonths', 'maxMonths', 'active'];
      text(d.name, 2, 100);
      num('minMonths', 0, 215);
      num('maxMonths', Number(d.minMonths), 215);
      bool('active');
      break;
    case 'session':
      keys = ['name', 'startsAt', 'endsAt'];
      text(d.name, 2, 100);
      if (
        !date(d.startsAt) ||
        !date(d.endsAt) ||
        Date.parse(String(d.endsAt)) <= Date.parse(String(d.startsAt)) ||
        Date.parse(String(d.endsAt)) - Date.parse(String(d.startsAt)) > 86400000
      )
        throw Error('A sessão deve durar até 24 horas.');
      break;
    case 'group':
      keys = ['sessionId', 'roomId', 'classId', 'capacity', 'minStaff'];
      ids('sessionId', 'roomId', 'classId');
      num('capacity', 1, 500);
      num('minStaff', 1, 30);
      break;
    case 'assignment':
      keys = ['sessionId', 'groupId', 'personId', 'role', 'canCare', 'active'];
      ids('sessionId', 'personId');
      bool('canCare', 'active');
      if (
        !['supervisor', 'reception', 'teacher', 'assistant'].includes(String(d.role)) ||
        (['supervisor', 'reception'].includes(String(d.role)) ? d.groupId !== null : !uuid(d.groupId)) ||
        (d.canCare && !['supervisor', 'teacher'].includes(String(d.role)))
      )
        throw Error('Papel ou sala inválidos.');
      break;
    case 'sessionState':
      keys = ['status'];
      if (!['open', 'closed', 'cancelled'].includes(String(d.status))) throw Error('Situação inválida.');
      break;
    case 'checkin':
      keys = ['sessionId', 'groupId', 'profileId', 'guardianId', 'identityConfirmed', 'receiptSecret'];
      ids('sessionId', 'groupId', 'profileId', 'guardianId');
      if (v.version !== 0) throw Error('Entrada inválida.');
      break;
    case 'checkout':
      keys = ['guardianId', 'identityConfirmed', 'receiptSecret'];
      ids('guardianId');
      break;
    case 'recover':
      keys = ['guardianId', 'identityConfirmed', 'receiptSecret', 'reason'];
      ids('guardianId');
      text(d.reason, 20, 500);
      break;
    case 'hold':
      keys = ['hold', 'reason'];
      bool('hold');
      text(d.reason, 10, 500);
      break;
    case 'transfer':
      keys = ['targetGroupId', 'reason'];
      ids('targetGroupId');
      text(d.reason, 10, 500);
      break;
    case 'transferAccept':
    case 'transferCancel':
      break;
    default:
      throw Error('Operação não disponível.');
  }
  if (['checkin', 'checkout', 'recover'].includes(String(v.action))) {
    if (d.identityConfirmed !== true) throw Error('Confira presencialmente a identidade do responsável.');
    if (typeof d.receiptSecret !== 'string' || !/^[a-f0-9]{64}$/.test(d.receiptSecret)) throw Error('Cole o código completo do comprovante.');
  }
  if (Object.keys(d).some((k) => !keys.includes(k)) || keys.some((k) => !(k in d))) throw Error('Campos não suportados.');
  return v as KidsOperationCommand;
}
export function kidsOperationsQuery(request: Request) {
  const p = new URL(request.url).searchParams;
  if (p.getAll('unitId').length !== 1 || !uuid(p.get('unitId'))) throw Error('Selecione uma igreja.');
  for (const k of ['sessionId', 'after']) if (p.getAll(k).length > 1 || (p.has(k) && !uuid(p.get(k)))) throw Error('Filtro inválido.');
  for (const k of ['search', 'status', 'q']) if (p.getAll(k).length > 1) throw Error('Filtro inválido.');
  const q = p.get('q'),
    status = p.get('status') || 'present';
  if (q !== null) {
    text(q, 2, 80);
    if (!uuid(p.get('sessionId'))) throw Error('Selecione uma sessão.');
  }
  if (!['present', 'out', 'all'].includes(status)) throw Error('Situação inválida.');
  return {unitId: p.get('unitId')!, sessionId: p.get('sessionId'), after: p.get('after'), search: text(p.get('search') || '', 0, 100), status, q};
}
export function kidsOperationsPage(value: unknown, unitId: string): KidsOperationsPage {
  const v = obj(value);
  if (
    v.unitId !== unitId ||
    (v.sessionId !== null && !uuid(v.sessionId)) ||
    !date(v.updatedAt) ||
    (v.nextCursor !== null && !uuid(v.nextCursor)) ||
    !['canConfigure', 'canReceive', 'canSupervise', 'canDirectory'].every((k) => typeof v[k] === 'boolean')
  )
    throw Error('Resposta Kids inválida.');
  for (const [key, max] of [
    ['items', 50],
    ['history', 50],
    ['sessions', 60],
    ['rooms', 200],
    ['classes', 200],
    ['groups', 500],
    ['assignments', 1000],
  ] as const) {
    if (!Array.isArray(v[key]) || v[key].length > max) throw Error('Lista Kids inválida.');
    for (const raw of v[key]) {
      const r = obj(raw);
      if (key !== 'history' && !uuid(r.id)) throw Error('Registro Kids inválido.');
      if (key !== 'history' && !integer(r.version, 1, 2147483647)) throw Error('Versão inválida.');
    }
  }
  // Neither receipt hashes nor raw secrets may cross the read boundary.
  if (/"(?:receiptSecret|receipt_hash|receiptHash)"\s*:/.test(JSON.stringify(v))) throw Error('Resposta com campo reservado.');
  return v as unknown as KidsOperationsPage;
}
export function kidsAdmissionPage(value: unknown, unitId: string): KidsAdmission[] {
  const v = obj(value);
  if (v.unitId !== unitId || !Array.isArray(v.items) || v.items.length > 20) throw Error('Busca inválida.');
  for (const raw of v.items) {
    const r = obj(raw);
    if (
      !uuid(r.id) ||
      typeof r.name !== 'string' ||
      !Array.isArray(r.guardians) ||
      r.guardians.some((g) => !uuid(obj(g).id) || typeof obj(g).name !== 'string')
    )
      throw Error('Criança inválida.');
  }
  return v.items as KidsAdmission[];
}
export const kidsOperationLabels: Record<string, string> = {
  room: 'Sala atualizada',
  class: 'Turma atualizada',
  session: 'Sessão atualizada',
  group: 'Sala da sessão atualizada',
  assignment: 'Equipe atualizada',
  sessionState: 'Situação da sessão atualizada',
  checkin: 'Entrada registrada',
  checkout: 'Retirada confirmada',
  recover: 'Comprovante substituído',
  hold: 'Proteção de retirada atualizada',
  transfer: 'Transferência solicitada',
  transferAccept: 'Transferência recebida',
  transferCancel: 'Transferência cancelada',
  receiptRefused: 'Comprovante recusado',
};

// ── Estações (Etapa 3 · PR 3): tablet ou celular da recepção em modo estação ──
export type KidsStation = {
  id: string;
  name: string;
  platform: 'android' | 'ios' | 'web' | 'other';
  user: string;
  createdAt: string;
  lastSeenAt: string;
  revokedAt: string | null;
  mine: boolean;
};
export type KidsStationList = {ok: true; timezone: string; items: KidsStation[]};
export type KidsStationCommand =
  | {action: 'register'; data: {name: string; platform: KidsStation['platform']}}
  | {action: 'heartbeat'; id: string}
  | {action: 'revoke'; id: string};
/** Station heartbeat interval in the app; a station silent for longer shows as offline in the panel. */
export const kidsStationHeartbeatMs = 120_000;
export function kidsStationCommand(value: unknown): KidsStationCommand {
  const v = obj(value);
  if (v.action === 'register') {
    const d = obj(v.data);
    if (Object.keys(v).sort().join(',') !== 'action,data' || Object.keys(d).sort().join(',') !== 'name,platform') throw Error('Estação inválida.');
    text(d.name, 2, 60);
    if (typeof d.name !== 'string' || d.name.trim().length < 2) throw Error('Dê um nome à estação.');
    if (!['android', 'ios', 'web', 'other'].includes(d.platform as string)) throw Error('Aparelho inválido.');
    return {action: 'register', data: {name: d.name.trim(), platform: d.platform as KidsStation['platform']}};
  }
  if ((v.action === 'heartbeat' || v.action === 'revoke') && Object.keys(v).sort().join(',') === 'action,id' && typeof v.id === 'string' && anyUuid.test(v.id))
    return {action: v.action, id: v.id};
  throw Error('Estação inválida.');
}
const anyUuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
/** Whether the panel shows the station as online. */
export const kidsStationOnline = (s: Pick<KidsStation, 'lastSeenAt' | 'revokedAt'>, now = Date.now()) =>
  !s.revokedAt && now - Date.parse(s.lastSeenAt) < kidsStationHeartbeatMs * 2.5;
