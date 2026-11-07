export const serviceStatus: Record<string, string> = {draft: 'Rascunho', published: 'Publicada', closed: 'Encerrada', cancelled: 'Cancelada'};
export const responseStatus: Record<string, string> = {pending: 'Aguardando resposta', accepted: 'Confirmado', declined: 'Recusado'};
export const presenceStatus: Record<string, string> = {unset: 'Não registrada', present: 'Presente', absent: 'Ausente'};
export const conflictLabels: Record<string, string> = {
  duplicate: 'Pessoa repetida na mesma função',
  qualification: 'Função não habilitada',
  unavailable: 'Indisponibilidade informada',
  availability: 'Fora da disponibilidade semanal',
  overlap: 'Sobreposição ou intervalo de deslocamento',
};
export const weekdays = ['Domingo', 'Segunda-feira', 'Terça-feira', 'Quarta-feira', 'Quinta-feira', 'Sexta-feira', 'Sábado'];
export function scaleOperationError(message = '', code = '') {
  if (code === '42501' || /denied|identity_pending/.test(message))
    return 'Seu vínculo ou sua permissão não permite esta operação. Confira o cadastro oficial com a igreja.';
  if (code === '40001' || message.includes('scale_changed')) return 'A escala, o convite ou a solicitação mudou. Atualize antes de confirmar novamente.';
  const errors: Record<string, string> = {
    scale_conflict: 'Há conflito de horário ou disponibilidade. Corrija a atribuição ou peça ao responsável uma exceção justificada.',
    scale_qualification: 'Escolha uma pessoa ativa e habilitada para esta função. Revise as habilitações em Equipes e funções.',
    scale_state: 'A situação ou o horário da escala não permite esta ação. Atualize e confira chegada, término e publicação.',
    scale_deadline: 'O prazo para responder terminou. Procure o responsável pela escala.',
    scale_reason:
      'Informe uma justificativa objetiva: pelo menos 10 caracteres para revisão, cancelamento, substituição ou resposta registrada pela liderança.',
    scale_presence:
      'A presença pode ser registrada de 2 horas antes da chegada até 7 dias após o término. Para corrigir um registro, informe ao menos 5 caracteres de justificativa.',
    scale_person_duplicate: 'Uma pessoa não pode preencher duas vagas da mesma função. Escolha outro integrante.',
    scale_primary_role: 'A função principal é definida no cadastro do integrante. Altere-a por lá antes de remover esta habilitação.',
  };
  for (const [key, value] of Object.entries(errors)) if (message.includes(key)) return value;
  if (code === '23505') return 'Já existe uma solicitação pendente ou um registro equivalente. Atualize a consulta.';
  if (['22023', '23514', '22007', '22008', '22P02', '23502'].includes(code))
    return 'Revise datas, horários, função e campos obrigatórios. O fim deve ser depois do início.';
  return 'Não foi possível confirmar a operação. Atualize a consulta antes de repetir.';
}
