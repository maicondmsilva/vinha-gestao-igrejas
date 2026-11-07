// Community chat: the same rules for the panel moderation screen, the member portal and the ministry apps.
// The database repeats every rule (private.chat). Only adults (18+) with an active linked person can talk.
// Realtime: subscribe to the private Broadcast topic `chat:<room>`; the event carries only ids, read the content with `messages`/`message`.
import {z} from 'zod';
import {uuidText} from './primitives.ts';

export const chatLimits = {
  body: 2000,
  name: 80,
  description: 280,
  blockedWords: 200,
  burst: 10,
  burstSeconds: 30,
  reportsToHide: 3,
  muteMinutes: 43200,
} as const;
export const chatReasons = ['ofensa', 'assedio', 'spam', 'golpe', 'outro'] as const;
export const chatReasonLabels: Record<(typeof chatReasons)[number], string> = {
  ofensa: 'Ofensa ou desrespeito',
  assedio: 'Assédio',
  spam: 'Propaganda ou repetição',
  golpe: 'Golpe ou pedido de dinheiro',
  outro: 'Outro motivo',
};
export const chatMuteOptions = [
  {minutes: 60, label: '1 hora'},
  {minutes: 1440, label: '1 dia'},
  {minutes: 10080, label: '7 dias'},
  {minutes: 43200, label: '30 dias'},
  {minutes: 0, label: 'Liberar'},
] as const;

export type ChatRoom = {
  id: string;
  kind: 'channel' | 'direct';
  unit: string | null;
  name: string;
  description: string;
  audience: 'members' | 'staff';
  posting: 'all' | 'moderators';
  moderator: boolean;
  last: string | null;
  unread: number;
  version: number;
};
export type ChatMessage = {
  id: string;
  room: string;
  createdAt: string;
  mine: boolean;
  replyTo: string | null;
  sender: string;
  senderId: string | null;
  state: 'visible' | 'hidden' | 'deleted';
  body: string;
  hiddenReason: 'moderator' | 'reports' | null;
  reports: number | null;
};
export type ChatThread = {room: string; moderator: boolean; canPost: boolean; mutedUntil: string | null; messages: ChatMessage[]};
export type ChatReport = {message: ChatMessage; roomName: string; count: number; reasons: string[]; first: string};
export type ChatSettings = {enabled: boolean; blockedWords: string[]; version: number};
export type ChatSignal = {id: string; room: string; op: 'insert' | 'update'};

export const chatTopic = (room: string) => 'chat:' + room;
export const chatEvent = 'chat';

const room = uuidText;
const text = (min: number, max: number, message: string) =>
  z.string({error: message}).refine((s) => s.trim().length >= min && s.trim().length <= max, {message});

export const chatSendSchema = z.strictObject({
  room,
  body: text(1, chatLimits.body, `Escreva uma mensagem de até ${chatLimits.body} caracteres.`),
  client: uuidText,
  reply: uuidText.optional(),
});
export const chatRoomSchema = z.strictObject({
  id: uuidText.optional(),
  version: z.number().int().min(1).optional(),
  unit: uuidText,
  name: text(2, chatLimits.name, `Nome do canal: use de 2 a ${chatLimits.name} caracteres.`),
  description: z.string().max(chatLimits.description, `Descrição: use até ${chatLimits.description} caracteres.`).default(''),
  audience: z.enum(['members', 'staff'], {error: 'Escolha quem participa.'}),
  posting: z.enum(['all', 'moderators'], {error: 'Escolha quem pode enviar.'}),
});
export const chatSettingsSchema = z.strictObject({
  enabled: z.boolean(),
  blockedWords: z
    .array(text(2, 40, 'Cada palavra bloqueada deve ter de 2 a 40 caracteres.'), {error: 'Lista de palavras inválida.'})
    .max(chatLimits.blockedWords, `Use até ${chatLimits.blockedWords} palavras bloqueadas.`),
  version: z.number().int().min(1),
});

const cmd = <A extends string, S extends z.ZodType>(action: A, data: S) => z.strictObject({action: z.literal(action), data});
const target = z.strictObject({room, id: uuidText});
export const chatCommandSchema = z.discriminatedUnion('action', [
  cmd('send', chatSendSchema),
  cmd('delete', target),
  cmd('report', z.strictObject({room, id: uuidText, reason: z.enum(chatReasons, {error: 'Escolha o motivo da denúncia.'})})),
  cmd('direct', z.strictObject({person: uuidText})),
  cmd('people', z.strictObject({search: text(2, 60, 'Digite ao menos 2 letras do nome.')})),
  cmd('hide', target),
  cmd('unhide', target),
  cmd('resolve', target),
  cmd('mute', z.strictObject({room, user: uuidText, minutes: z.number().int().min(0).max(chatLimits.muteMinutes)})),
  cmd('room_save', chatRoomSchema),
  cmd('room_archive', z.strictObject({id: uuidText})),
  cmd('settings', chatSettingsSchema),
]);
export type ChatCommand = z.infer<typeof chatCommandSchema>;

export const chatReadSchema = z.discriminatedUnion('action', [
  z.strictObject({action: z.literal('rooms')}),
  z.strictObject({action: z.literal('messages'), room, before: z.iso.datetime({offset: true}).optional()}),
  z.strictObject({action: z.literal('message'), room, id: uuidText}),
  z.strictObject({action: z.literal('reports')}),
  z.strictObject({action: z.literal('settings')}),
]);

/** Database error code → message and field shown to the person. */
export const chatErrors: Record<string, [string, string | null, number]> = {
  chat_adult_only: ['O chat é para adultos com cadastro confirmado na igreja.', null, 403],
  chat_read_only: ['Neste canal só a moderação envia mensagens.', null, 403],
  chat_muted: ['Você está temporariamente sem enviar mensagens neste canal.', null, 403],
  chat_slow_down: ['Muitas mensagens seguidas. Aguarde alguns segundos.', null, 429],
  chat_blocked_word: ['A mensagem tem uma palavra bloqueada pela igreja. Revise o texto.', 'body', 400],
  chat_direct_unavailable: ['Esta pessoa não pode receber conversas pelo chat.', 'person', 400],
  chat_direct_closed: ['Esta conversa foi encerrada.', null, 403],
  chat_room_limit: ['Limite de 100 canais ativos atingido. Arquive canais que não são usados.', null, 400],
  chat_conflict: ['Outra pessoa alterou isto agora. Atualize e tente de novo.', null, 409],
  chat_denied: ['Seu acesso não permite esta ação no chat.', null, 403],
  invalid_chat: ['Revise os dados enviados.', null, 400],
};
export function chatError(message?: string | null) {
  const hit = Object.entries(chatErrors).find(([k]) => message?.includes(k));
  return hit ? {code: hit[0], error: hit[1][0], field: hit[1][1], status: hit[1][2]} : null;
}

/** Reads a Broadcast payload defensively (only ids travel over realtime). */
export function chatSignal(v: unknown): ChatSignal | null {
  const o = v && typeof v === 'object' ? ((v as {payload?: unknown}).payload ?? v) : null;
  if (!o || typeof o !== 'object') return null;
  const {id, room, op} = o as Record<string, unknown>;
  if (typeof id !== 'string' || typeof room !== 'string' || !uuidText.safeParse(id).success || !uuidText.safeParse(room).success) return null;
  return {id, room, op: op === 'update' ? 'update' : 'insert'};
}

/** Merges fresh messages into the list kept on screen (by id, oldest first). */
export function mergeChatMessages(list: ChatMessage[], fresh: ChatMessage[]) {
  const map = new Map(list.map((m) => [m.id, m]));
  for (const m of fresh) map.set(m.id, m);
  return [...map.values()].sort((a, b) => Date.parse(a.createdAt) - Date.parse(b.createdAt) || a.id.localeCompare(b.id));
}
