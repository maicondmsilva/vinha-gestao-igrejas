/** Agenda pastoral: tipos e regras puras usadas no app e nos testes. */
export type PastoralAttendant = {
  id: string;
  name: string;
  role: string;
  about: string;
  durations: number[];
  kinds: string[];
  modes: string[];
  autoConfirm: boolean;
  myLeader: boolean;
  pastor: boolean;
};
export type DayState = 'available' | 'full' | 'none' | 'past' | 'closed';
export type PastoralDay = {date: string; state: DayState; slots: number};
export type PastoralSlot = {startsAt: string; label: string};
export type PastoralAppointment = {
  id: string;
  attendant: string;
  role: string;
  kind: string;
  mode: string;
  startsAt: string;
  endsAt: string;
  status: string;
  origin: string;
  memberAck: boolean;
  message: string;
  link: string;
  reason: string;
  version: number;
  address: string;
};

export const pastoralKinds: Record<string, string> = {
  conversa: 'Conversa pastoral',
  aconselhamento: 'Aconselhamento',
  oracao: 'Oração',
  visita: 'Visita em casa',
  outro: 'Outro assunto',
};
export const pastoralModes: Record<string, string> = {presencial: 'Na igreja', online: 'Online', visita: 'Na minha casa'};
export const pastoralStatus: Record<string, string> = {
  requested: 'Aguardando confirmação',
  confirmed: 'Confirmado',
  declined: 'Não foi possível',
  cancelled: 'Cancelado',
  done: 'Realizado',
  missed: 'Não compareceu',
};
export const dayLegend: [DayState, string][] = [
  ['available', 'Com horários livres'],
  ['full', 'Agenda cheia'],
  ['none', 'Sem atendimento'],
];

/** Líder da minha célula e pastores primeiro; depois por nome. */
export function sortAttendants(list: PastoralAttendant[]) {
  const rank = (a: PastoralAttendant) => (a.myLeader ? 0 : a.pastor ? 1 : 2);
  return [...list].sort((a, b) => rank(a) - rank(b) || a.name.localeCompare(b.name, 'pt-BR'));
}

/** Semanas do mês (domingo a sábado) com espaços vazios antes do dia 1 e depois do último dia. */
export function monthGrid(month: string) {
  const [y, m] = month.split('-').map(Number);
  const first = new Date(Date.UTC(y!, m! - 1, 1)),
    days = new Date(Date.UTC(y!, m!, 0)).getUTCDate(),
    cells: (string | null)[] = Array(first.getUTCDay()).fill(null);
  for (let d = 1; d <= days; d++) cells.push(`${month}-${String(d).padStart(2, '0')}`);
  while (cells.length % 7) cells.push(null);
  const weeks: (string | null)[][] = [];
  for (let i = 0; i < cells.length; i += 7) weeks.push(cells.slice(i, i + 7));
  return weeks;
}

export function shiftMonth(month: string, by: number) {
  const [y, m] = month.split('-').map(Number);
  const d = new Date(Date.UTC(y!, m! - 1 + by, 1));
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}`;
}

export const monthNames = ['Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho', 'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro'];
export function monthTitle(month: string) {
  const [y, m] = month.split('-').map(Number);
  return `${monthNames[m! - 1]} de ${y}`;
}

/** O membro cancela até 12 h antes de pedidos em aberto ou confirmados. */
export function canCancel(a: Pick<PastoralAppointment, 'status' | 'startsAt'>, now = Date.now()) {
  return ['requested', 'confirmed'].includes(a.status) && Date.parse(a.startsAt) - now >= 12 * 3600 * 1000;
}

export function openCount(list: Pick<PastoralAppointment, 'status' | 'endsAt'>[], now = Date.now()) {
  return list.filter((a) => ['requested', 'confirmed'].includes(a.status) && Date.parse(a.endsAt) > now).length;
}

export function pastoralError(message: string) {
  if (/pastoral_open_limit/.test(message)) return 'Você já tem 2 pedidos em aberto. Aguarde um deles acontecer ou cancele um para pedir outro.';
  if (/pastoral_slot_taken|pastoral_changed/.test(message)) return 'Esse horário acabou de ser ocupado. Escolha outro.';
  if (/pastoral_cancel_late/.test(message)) return 'Faltam menos de 12 horas. Para cancelar agora, fale com a secretaria da igreja.';
  if (/pastoral_profile_required/.test(message)) return 'Seu cadastro precisa estar vinculado à igreja para pedir um horário.';
  if (/member_login_required/.test(message)) return 'Entre na sua conta para pedir um horário.';
  return 'Não foi possível concluir agora. Tente de novo.';
}

/** 30 → "30 min", 60 → "1 hora", 90 → "1h30", 120 → "2 horas". */
export function durationLabel(min: number) {
  if (min < 60) return `${min} min`;
  if (min % 60) return `${Math.floor(min / 60)}h${String(min % 60).padStart(2, '0')}`;
  return min === 60 ? '1 hora' : `${min / 60} horas`;
}
