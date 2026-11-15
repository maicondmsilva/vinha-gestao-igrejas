// Kids · configuração sem sessão ativa: salas, turmas, equipe fixa e sessões que se repetem.
// Usado pelo painel (Kids › Equipe e repetições) e pelo Vinha Equipe (Configurar Kids).
export type KidsSetupRoom = {id: string; name: string; location: string; capacity: number; active: boolean; version: number};
export type KidsSetupClass = {id: string; name: string; minMonths: number; maxMonths: number; active: boolean; version: number};
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
};
export type KidsSeriesRule = 'daily' | 'weekly' | 'monthly_day' | 'monthly_week';
export type KidsSeriesRoom = {roomId: string; classId: string; capacity: number; minStaff: number};
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
};
export type KidsSetup = {rooms: KidsSetupRoom[]; classes: KidsSetupClass[]; team: KidsTeamMember[]; series: KidsSeries[]; sessions: KidsSetupSession[]};

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
        : /in_use/.test(m)
          ? 'Está em uso numa sessão aberta. Encerre a sessão antes.'
          : 'Revise os dados e tente de novo.';
