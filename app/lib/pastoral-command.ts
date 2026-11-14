import {uuidPattern} from './private-files.ts';
export const pastoralStaffActions = ['save_attendant', 'hours', 'block', 'unblock', 'decide', 'schedule', 'status', 'note', 'slots'] as const;
/** Forma do pedido do painel para a agenda pastoral. As regras de negócio e o acesso são conferidos no banco. */
export function pastoralCommand(value: unknown) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
  const b = value as Record<string, unknown>;
  if (Object.keys(b).sort().join(',') !== 'action,data,unit') return null;
  if (typeof b.unit !== 'string' || !uuidPattern.test(b.unit)) return null;
  if (!pastoralStaffActions.includes(b.action as (typeof pastoralStaffActions)[number])) return null;
  if (!b.data || typeof b.data !== 'object' || Array.isArray(b.data) || JSON.stringify(b.data).length > 16000) return null;
  return {unit: b.unit, action: String(b.action), data: b.data as Record<string, unknown>};
}
export function pastoralStaffError(code?: string, message = '') {
  if (code === '42501') return {status: 403, error: 'Seu acesso não permite esta ação na agenda pastoral.'};
  if (code === '40001')
    return {status: 409, error: /slot_taken/.test(message) ? 'Esse horário já está ocupado. Escolha outro.' : 'A agenda mudou. Atualize e tente de novo.'};
  return {status: 400, error: 'Revise os dados: horários, durações e pessoas.'};
}
