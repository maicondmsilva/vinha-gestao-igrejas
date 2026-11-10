export type ScaleReport = {
  unitName: string;
  timezone: string;
  services: number;
  slots: number;
  filled: number;
  invites: number;
  confirmed: number;
  declined: number;
  pending: number;
  averageReplyMinutes: number | null;
  attendanceBase: number;
  present: number;
  absent: number;
  changes: {total: number; approved: number; pending: number};
  distributionTotal: number;
  distribution: {id: string; name: string; services: number; assignments: number; confirmed: number}[];
  teamRoles: {team: string; role: string; required: number; filled: number; invites: number; confirmed: number; declined: number; pending: number}[];
};

export type ScaleFilters = {
  timezone: string;
  choices: {team: string; teamName: string; role: string; roleName: string}[];
};

export type ScalePendingResult = {
  timezone: string;
  total: number;
  items: {
    service_id: string;
    title: string;
    starts_at: string;
    team: string;
    role: string;
    name: string | null;
    kind: 'replacement' | 'vacancy' | 'declined' | 'reply';
    due: string;
    role_id: string;
    ordinal: number;
  }[];
};

const rate = (numerator: number, denominator: number) => (denominator ? `${Math.round((numerator / denominator) * 100)}%` : '—');

export function scaleMetrics(report: ScaleReport): [string, string | number][] {
  return [
    ['Serviços', report.services],
    ['Cobertura de vagas', `${report.filled} de ${report.slots} · ${rate(report.filled, report.slots)}`],
    ['Confirmações', `${report.confirmed} de ${report.invites} · ${rate(report.confirmed, report.invites)}`],
    ['Recusas', report.declined],
    ['Aguardando resposta', report.pending],
    ['Tempo médio de resposta', report.averageReplyMinutes === null ? '—' : `${report.averageReplyMinutes} min`],
    ['Presenças', `${report.present} de ${report.attendanceBase} · ${rate(report.present, report.attendanceBase)}`],
    ['Ausências registradas', report.absent],
    ['Sem registro de presença', report.attendanceBase - report.present - report.absent],
    ['Trocas solicitadas', report.changes.total],
    ['Trocas aprovadas', report.changes.approved],
    ['Trocas pendentes', report.changes.pending],
  ];
}

export const scaleReportBasis =
  'Vagas: posições exigidas. Respostas: convites vigentes. Presença: uma pessoa por serviço terminado, sem incluir recusas sem registro de presença. Escalas canceladas e rascunhos ficam fora dos totais.';
