// Kids · configuração sem sessão ativa: salas, turmas, equipe fixa e sessões que se repetem.
// Usado pelo painel (Kids › Equipe e repetições) e pelo Vinha Equipe (Configurar Kids).
export type KidsSetupRoom = {id: string; name: string; location: string; capacity: number; active: boolean; version: number; locked?: boolean};
export type KidsSetupClass = {id: string; name: string; minMonths: number; maxMonths: number; active: boolean; version: number; locked?: boolean};
export type KidsTeamRole = 'supervisor' | 'reception' | 'teacher' | 'assistant';
export type KidsTeamMember = {
  id: string;
  personId: string;
  name: string;
  role: KidsTeamRole;
  classId: string | null;
  canCare: boolean;
  active: boolean;
  version: number;
  rotation?: number | null;
  unavailable?: string[];
};
export type KidsSeriesRule = 'daily' | 'weekly' | 'monthly_day' | 'monthly_week';
export type KidsSeriesRoom = {roomId: string; classId: string; capacity: number; minStaff: number; staff?: string[]};
export type KidsSeries = {
  id: string;
  name: string;
  rule: KidsSeriesRule;
  weekdays: number[];
  monthDay: number | null;
  monthWeek: number | null;
  startsTime: string;
  durationMinutes: number;
  validFrom: string;
  validUntil: string | null;
  openBeforeHours: number;
  rooms: KidsSeriesRoom[];
  autoTeam: boolean;
  active: boolean;
  version: number;
  next: string[];
  rotationGroups?: number;
  autoOpen?: boolean;
};
export type KidsSetupSession = {
  id: string;
  name: string;
  startsAt: string;
  endsAt: string;
  status: string;
  seriesId: string | null;
  bookableFrom: string | null;
  rooms: number;
  staff: number;
  version: number;
  /** Já tem lançamentos (entrada, reserva ou retirada): não pode ser excluído, só desativado. */
  locked?: boolean;
};
export type KidsSetup = {rooms: KidsSetupRoom[]; classes: KidsSetupClass[]; team: KidsTeamMember[]; series: KidsSeries[]; sessions: KidsSetupSession[]};

/** Confere o formato da configuração antes de exibir (uma resposta inesperada vira aviso, não quebra a página). */
export function isKidsSetup(v: unknown): v is KidsSetup {
  const o = v as Record<string, unknown> | null;
  return !!o && typeof o === 'object' && ['rooms', 'classes', 'team', 'series', 'sessions'].every((k) => Array.isArray(o[k]));
}

export const kidsTeamRoles: [KidsTeamRole, string][] = [
  ['teacher', 'Professor(a)'],
  ['assistant', 'Auxiliar'],
  ['reception', 'Recepção'],
  ['supervisor', 'Coordenação'],
];
export const kidsRuleLabels: [KidsSeriesRule, string][] = [
  ['weekly', 'Toda semana'],
  ['daily', 'Todo dia'],
  ['monthly_day', 'Todo mês (no dia)'],
  ['monthly_week', 'Todo mês (no dia da semana)'],
];
export const weekdayNames = ['domingo', 'segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado'];
export const weekdayShort = ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb'];
export const openBeforeOptions: [number, string][] = [
  [2, '2 horas antes'],
  [24, '1 dia antes'],
  [48, '2 dias antes'],
  [72, '3 dias antes'],
  [168, '1 semana antes'],
];
const ordinal = ['', '1º', '2º', '3º', '4º', '5º'];

/** "Todo domingo e quarta às 09:00", "Todo mês no 1º sábado às 18:30"… */
export function describeSeries(s: Pick<KidsSeries, 'rule' | 'weekdays' | 'monthDay' | 'monthWeek' | 'startsTime'>) {
  const at = ' às ' + s.startsTime;
  if (s.rule === 'daily') return 'Todo dia' + at;
  if (s.rule === 'weekly') {
    const days = [...s.weekdays].sort((a, b) => a - b).map((d) => weekdayNames[d]);
    if (!days.length) return 'Escolha os dias da semana';
    const list = days.length > 1 ? days.slice(0, -1).join(', ') + ' e ' + days[days.length - 1] : days[0];
    return (s.weekdays.length === 1 && [0, 6].includes(s.weekdays[0]!) ? 'Todo ' : 'Toda ') + list + at;
  }
  if (s.rule === 'monthly_day') return `Todo mês no dia ${s.monthDay || '?'}` + at;
  return `Todo mês no ${ordinal[s.monthWeek || 0] || '?'} ${weekdayNames[s.weekdays[0] ?? 0]}` + at;
}

/** Problema que impede salvar a repetição (mesmas regras do banco). */
export function seriesProblem(s: Pick<KidsSeries, 'name' | 'rule' | 'weekdays' | 'monthDay' | 'monthWeek' | 'startsTime' | 'durationMinutes' | 'rooms'>) {
  if (s.name.trim().length < 2) return 'Dê um nome à sessão (ex.: Kids domingo manhã).';
  if (!/^([01]\d|2[0-3]):[0-5]\d$/.test(s.startsTime)) return 'Horário no formato 09:00.';
  if (s.durationMinutes < 15 || s.durationMinutes > 720) return 'Duração de 15 minutos a 12 horas.';
  if (s.rule === 'weekly' && !s.weekdays.length) return 'Escolha ao menos um dia da semana.';
  if (s.rule === 'monthly_day' && !s.monthDay) return 'Escolha o dia do mês.';
  if (s.rule === 'monthly_week' && (!s.monthWeek || s.weekdays.length !== 1)) return 'Escolha a semana e o dia da semana.';
  if (!s.rooms.length) return 'Inclua ao menos uma sala com turma.';
  return '';
}

export const kidsSetupError = (m: string) =>
  /identity_required/.test(m)
    ? 'A pessoa precisa ser adulta e ter conta ativa no app da igreja.'
    : /access_denied/.test(m)
      ? 'Somente a coordenação do Kids configura salas, equipe e sessões.'
      : /version_conflict/.test(m)
        ? 'Alguém alterou isso agora. Atualize e tente de novo.'
        : /has_records/.test(m)
          ? 'Já tem lançamentos (entradas ou reservas). Para guardar o histórico, desative em vez de excluir.'
          : /in_use/.test(m)
            ? 'Está em uso numa sessão aberta. Encerre a sessão antes.'
            : 'Revise os dados e tente de novo.';

export type KidsReportRow = {
  id: string;
  series: string;
  startsAt: string;
  status: string;
  children: number;
  reserved: number;
  capacity: number;
  staff: number;
  confirmed: number;
};
/** Letra da equipe no revezamento (1 → A). */
export const rotationLetter = (n?: number | null) => (n ? String.fromCharCode(64 + n) : '');
/** Ocupação da sessão em %, para o relatório. */
export const occupancy = (r: Pick<KidsReportRow, 'children' | 'capacity'>) => (r.capacity ? Math.round((r.children / r.capacity) * 100) : 0);

/** Data dd/mm/aaaa + horários HH:MM (hora do aparelho) → início e fim em ISO; null se inválido. */
export function sessionTimes(date: string, start: string, end: string) {
  const m = /^(\d{2})\/(\d{2})\/(\d{4})$/.exec(date.trim()),
    a = /^(\d{2}):(\d{2})$/.exec(start.trim()),
    b = /^(\d{2}):(\d{2})$/.exec(end.trim());
  if (!m || !a || !b) return null;
  const at = (h: string, mi: string) => new Date(Number(m[3]), Number(m[2]) - 1, Number(m[1]), Number(h), Number(mi));
  const s = at(a[1]!, a[2]!),
    e = at(b[1]!, b[2]!);
  if (s.getDate() !== Number(m[1]) || s.getMonth() !== Number(m[2]) - 1 || Number(a[1]) > 23 || Number(b[1]) > 23 || Number(a[2]) > 59 || Number(b[2]) > 59)
    return null;
  if (e <= s) return null;
  return {startsAt: s.toISOString(), endsAt: e.toISOString()};
}

/** Formulário único de Sessão: "Não repete" (uma data) ou "Toda semana" (dias marcados). */
export type SessionForm = {
  id: string;
  version: number;
  name: string;
  repeat: 'once' | 'weekly' | 'legacy';
  date: string; // dd/mm/aaaa
  weekdays: number[];
  start: string; // HH:MM
  duration: number;
  rooms: {roomId: string; classId: string; staff: string[]}[];
  active: boolean;
  openBeforeHours: number;
  legacy?: KidsSeries;
};
const isoToBr = (d: string) => d.split('-').reverse().join('/');
const brToIso = (d: string) => {
  const m = /^(\d{2})\/(\d{2})\/(\d{4})$/.exec(d.trim());
  if (!m) return '';
  const iso = m[3] + '-' + m[2] + '-' + m[1],
    t = new Date(iso + 'T12:00:00Z');
  return Number.isFinite(t.getTime()) && t.toISOString().slice(0, 10) === iso ? iso : '';
};
export function blankSessionForm(id: string, today = new Date()): SessionForm {
  const d = today.toLocaleDateString('pt-BR', {day: '2-digit', month: '2-digit', year: 'numeric'});
  return {id, version: 0, name: '', repeat: 'weekly', date: d, weekdays: [0], start: '09:00', duration: 120, rooms: [], active: true, openBeforeHours: 24};
}
export function sessionFormFrom(s: KidsSeries): SessionForm {
  const once = !!s.validUntil && s.validUntil === s.validFrom && s.rule === 'weekly',
    weekly = s.rule === 'weekly' || s.rule === 'daily';
  return {
    id: s.id,
    version: s.version,
    name: s.name,
    repeat: once ? 'once' : weekly ? 'weekly' : 'legacy',
    date: isoToBr(s.validFrom),
    weekdays: s.rule === 'daily' ? [0, 1, 2, 3, 4, 5, 6] : [...s.weekdays],
    start: s.startsTime,
    duration: s.durationMinutes,
    rooms: s.rooms.map((r) => ({roomId: r.roomId, classId: r.classId, staff: [...(r.staff || [])]})),
    active: s.active,
    openBeforeHours: s.openBeforeHours,
    legacy: s,
  };
}
/** O que falta para salvar (texto curto) ou ''. */
export function sessionFormProblem(f: SessionForm, today = new Date()) {
  if (f.name.trim().length < 2) return 'Dê um nome para a sessão.';
  if (!/^([01]\d|2[0-3]):[0-5]\d$/.test(f.start)) return 'Informe o horário (ex.: 09:00).';
  if (f.repeat === 'once') {
    const iso = brToIso(f.date);
    if (!iso) return 'Informe a data (dd/mm/aaaa).';
    const t = today.getFullYear() + '-' + String(today.getMonth() + 1).padStart(2, '0') + '-' + String(today.getDate()).padStart(2, '0');
    if (iso < t) return 'A data já passou.';
  }
  if (f.repeat === 'weekly' && !f.weekdays.length) return 'Marque ao menos um dia da semana.';
  if (!f.rooms.length) return 'Escolha ao menos uma sala com turma.';
  return '';
}
/** Dados para kids_setup('series_save'). */
export function sessionPayload(f: SessionForm, capacity: (roomId: string) => number, today = new Date()) {
  const iso = brToIso(f.date),
    todayIso = today.getFullYear() + '-' + String(today.getMonth() + 1).padStart(2, '0') + '-' + String(today.getDate()).padStart(2, '0'),
    l = f.legacy;
  const base =
    f.repeat === 'once'
      ? {rule: 'weekly', weekdays: [new Date(iso + 'T12:00:00Z').getUTCDay()], monthDay: '', monthWeek: '', validFrom: iso, validUntil: iso}
      : f.repeat === 'legacy' && l
        ? {rule: l.rule, weekdays: l.weekdays, monthDay: l.monthDay ?? '', monthWeek: l.monthWeek ?? '', validFrom: l.validFrom, validUntil: l.validUntil || ''}
        : {
            rule: 'weekly',
            weekdays: [...f.weekdays].sort(),
            monthDay: '',
            monthWeek: '',
            validFrom: l && l.validUntil !== l.validFrom ? l.validFrom : todayIso,
            validUntil: '',
          };
  return {
    id: f.id,
    version: f.version,
    name: f.name.trim(),
    ...base,
    startsTime: f.start,
    durationMinutes: f.duration,
    openBeforeHours: f.openBeforeHours,
    rooms: f.rooms.map((r) => ({roomId: r.roomId, classId: r.classId, capacity: capacity(r.roomId), minStaff: 1, staff: r.staff})),
    autoTeam: !!l?.autoTeam && f.rooms.every((r) => !r.staff.length),
    active: f.active,
  };
}
export const durationOptions: [number, string][] = [
  [60, '1 h'],
  [90, '1 h 30'],
  [120, '2 h'],
  [150, '2 h 30'],
  [180, '3 h'],
];
/** "Toda semana: Dom e Qua às 09:00" · "Só em 20/11 às 19:30". */
export function describeSession(f: SessionForm) {
  if (f.repeat === 'once') return 'Só em ' + f.date.slice(0, 5) + ' às ' + f.start;
  if (f.repeat === 'legacy' && f.legacy) return describeSeries(f.legacy);
  const days = [...f.weekdays].sort().map((d) => weekdayShort[d]);
  return (
    (days.length === 7 ? 'Todo dia' : 'Toda semana: ' + (days.length > 1 ? days.slice(0, -1).join(', ') + ' e ' + days.at(-1) : days[0])) + ' às ' + f.start
  );
}
