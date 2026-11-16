// Relatório de atendimento, sigilo, regras do atendente e Integração Visitante: textos e validações comuns ao painel e ao app.
export type Privacy = 'team' | 'restricted' | 'secret';
export const privacyLabel: Record<Privacy, string> = {team: 'Equipe pastoral', restricted: 'Restrito', secret: 'Sigiloso'};
export const privacyHelp: Record<Privacy, string> = {
  team: 'Quem tem a permissão “Relatórios de atendimento” lê.',
  restricted: 'Só quem tem a permissão “Relatórios restritos” lê.',
  secret: 'Só você e quem tem a permissão “Relatórios sigilosos” leem.',
};
export const reportTopics: [string, string][] = [
  ['vida_espiritual', 'Vida espiritual'],
  ['familia', 'Família'],
  ['casamento', 'Casamento'],
  ['financas', 'Finanças'],
  ['luto', 'Luto'],
  ['saude', 'Saúde'],
  ['trabalho', 'Trabalho'],
  ['ministerio', 'Ministério'],
  ['outro', 'Outro'],
];
export const reportReferrals: [string, string][] = [
  ['celula', 'Célula'],
  ['discipulado', 'Curso ou discipulado'],
  ['outro_atendente', 'Outro atendente'],
  ['ministerio', 'Ministério'],
  ['profissional', 'Ajuda profissional'],
];
export const contactKinds: [string, string][] = [
  ['ligacao', 'Ligação'],
  ['mensagem', 'Mensagem'],
  ['visita', 'Visita'],
  ['encontro', 'Encontro'],
  ['culto', 'No culto'],
  ['outro', 'Outro'],
];
export const audienceLabel: Record<string, string> = {
  all: 'Todos os membros',
  leaders: 'Só líderes',
  group: 'Só a minha célula ou rede',
  invite: 'Só por convite (não aparece no app)',
};
export const faithLabel: Record<string, string> = {
  unknown: 'Não informado',
  none: 'Ainda não se decidiu',
  here: 'Decidiu-se nesta igreja',
  reconciled: 'Reconciliação',
  other_church: 'Já convertido(a), vem de outra igreja',
};
export type Report = {
  id: string;
  kind: 'atendimento' | 'acompanhamento';
  contact: string | null;
  at: string;
  author: string;
  mine: boolean;
  privacy: Privacy;
  readable: boolean;
  locked: boolean;
  appointment: {kind: string; mode: string; startsAt: string} | null;
  summary?: string;
  topics?: string[];
  prayer?: string;
  referrals?: string[];
  nextStep?: string | null;
  addenda?: {at: string; text: string}[];
};
export type ReportDraft = {summary: string; topics: string[]; prayer: string; referrals: string[]; nextStep: string; privacy: Privacy; contact: string};
export const emptyDraft: ReportDraft = {summary: '', topics: [], prayer: '', referrals: [], nextStep: '', privacy: 'team', contact: 'ligacao'};

/** Pedido do painel/app para a rota de relatórios e regras: só campos conhecidos. */
export function careCommand(value: unknown) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
  const b = value as Record<string, unknown>;
  const actions = ['save', 'addendum', 'history', 'reads', 'rules'];
  if (typeof b.action !== 'string' || !actions.includes(b.action) || typeof b.unit !== 'string' || !/^[0-9a-f-]{36}$/i.test(b.unit)) return null;
  if (!b.data || typeof b.data !== 'object' || Array.isArray(b.data) || JSON.stringify(b.data).length > 20000) return null;
  const d = b.data as Record<string, unknown>;
  if (b.action === 'save') {
    if (typeof d.summary !== 'string' || d.summary.trim().length < 3 || d.summary.length > 8000) return null;
    if (d.privacy !== undefined && !['team', 'restricted', 'secret'].includes(String(d.privacy))) return null;
    if (d.topics !== undefined && (!Array.isArray(d.topics) || d.topics.some((t) => !reportTopics.some(([k]) => k === t)))) return null;
    if (d.referrals !== undefined && (!Array.isArray(d.referrals) || d.referrals.some((t) => !reportReferrals.some(([k]) => k === t)))) return null;
    if (d.nextStep && !/^\d{4}-\d{2}-\d{2}$/.test(String(d.nextStep))) return null;
  }
  return {action: b.action, unit: b.unit, data: d};
}
export function careError(code: string, message: string) {
  if (/report_locked/.test(message)) return {status: 409, error: 'Passados 7 dias, o relatório fica travado. Use “Complementar”.'};
  if (/report_too_early/.test(message)) return {status: 400, error: 'O relatório fica disponível depois do horário do atendimento.'};
  if (/report_exists/.test(message)) return {status: 409, error: 'Este atendimento já tem relatório. Edite o existente.'};
  if (code === '42501') return {status: 403, error: 'Seu acesso não permite ver ou alterar este relatório.'};
  return {status: 400, error: 'Revise os campos do relatório.'};
}
