// Kids · recepção (Vinha Equipe e painel): código do comprovante e mensagens das recusas do banco.

/** Código do comprovante: 32 bytes aleatórios em hexadecimal (o banco guarda só o hash). */
export function receiptCode(bytes: Uint8Array) {
  if (bytes.length !== 32) throw Error('Comprovante inválido.');
  return Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('');
}

export function receptionError(message: string) {
  if (/kids_guardian_required/.test(message)) return 'Esse adulto não está autorizado a levar ou buscar esta criança.';
  if (/kids_age_outside_class/.test(message)) return 'A idade da criança não combina com essa turma. Escolha outra sala.';
  if (/kids_capacity_full/.test(message)) return 'Essa sala está cheia. Escolha outra sala.';
  if (/kids_staff_insufficient/.test(message)) return 'Essa sala ainda não tem a equipe mínima.';
  if (/kids_session_not_open/.test(message)) return 'A sessão não está aberta.';
  if (/kids_hold_or_transfer_pending/.test(message)) return 'Há uma retenção ou transferência pendente. Chame a coordenação.';
  if (/kids_receipt_recovery_required/.test(message)) return 'O comprovante expirou ou teve tentativas demais. A coordenação precisa liberar.';
  if (/kids_version_conflict/.test(message)) return 'Os dados mudaram. Atualize e tente de novo.';
  if (/kids_access_denied/.test(message)) return 'Você não está na recepção desta sessão.';
  return 'Não foi possível registrar agora. Tente de novo.';
}

/** Dados que a recepção recebe ao ler o QR Code da reserva (kids_pass). */
export type KidsPass = {
  found: boolean;
  reservation: string;
  sessionId: string;
  session: string;
  sessionStatus: string;
  groupId: string;
  room: string | null;
  profileId: string;
  child: string;
  care: string | null;
  reservedBy: string | null;
  guardians: {id: string; name: string; relationship: string; temporary: boolean; validUntil: string | null}[];
  attendance: {id: string; version: number; status: 'present' | 'out'; tag: number | null} | null;
};
/** O código de 64 caracteres dentro do QR (pode vir sozinho ou dentro de um link). */
export const kidsPassCode = (scanned: string) => /[a-f0-9]{64}/i.exec(scanned || '')?.[0].toLowerCase() || '';
