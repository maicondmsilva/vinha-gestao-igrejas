// Kids · chamar o responsável: textos usados pelo Vinha Equipe e pelo app da igreja.
export type KidsCallReason = 'diaper' | 'crying' | 'health' | 'pickup' | 'other';
export const kidsCallReasons: [KidsCallReason, string][] = [
  ['pickup', 'Buscar agora'],
  ['crying', 'Chorando'],
  ['diaper', 'Troca de fralda'],
  ['health', 'Saúde'],
  ['other', 'Outro'],
];
export type KidsCall = {
  id: string;
  attendance?: string;
  child: string;
  reason: KidsCallReason;
  reasonText?: string;
  message: string;
  createdAt: string;
  answer: 'coming' | 'ok' | null;
};

const time = (iso: string) => new Date(iso).toLocaleTimeString('pt-BR', {hour: '2-digit', minute: '2-digit'});

/** Situação do último chamado, para a equipe da sala. */
export function kidsCallAnswer(c: Pick<KidsCall, 'answer' | 'createdAt'>) {
  if (c.answer === 'coming') return 'Responsável a caminho';
  if (c.answer === 'ok') return 'Responsável viu o aviso';
  return 'Chamado às ' + time(c.createdAt) + ' · aguardando resposta';
}

/** Chamados que ainda pedem atenção da família: sem resposta e de até 30 minutos. */
export function openKidsCalls(items: KidsCall[], now = Date.now()) {
  return items.filter((c) => !c.answer && now - Date.parse(c.createdAt) < 30 * 60 * 1000);
}
