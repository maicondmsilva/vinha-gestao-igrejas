// Push campaigns: the same rules for the panel form, the Vinha Equipe composer and the API.
// The database repeats every rule (private.push_admin); these give each input its own message first.
import {z} from 'zod';
import {uuidText} from './primitives.ts';

export const pushScreens = ['inbox', 'agenda', 'event', 'notice', 'media', 'live', 'giving', 'services'] as const;
export const pushScreensWithId = ['event', 'notice', 'media', 'live'] as const;
export const pushRoles = ['owner', 'pastor', 'admin', 'secretary', 'finance', 'leader', 'member', 'viewer'] as const;
export const pushModes = ['draft', 'now', 'schedule'] as const;
export const pushRecurrences = ['none', 'daily', 'weekly', 'monthly'] as const;
export const pushLimits = {title: 65, body: 240, targets: 200} as const;

const trimmed = (min: number, max: number, message: string) =>
  z.string({error: message}).refine((s) => s.trim().length >= min && s.trim().length <= max, {message});
const age = z
  .number({error: 'Idade: use um número de 0 a 120.'})
  .int('Idade: use um número inteiro.')
  .min(0, 'Idade: use um número de 0 a 120.')
  .max(120, 'Idade: use um número de 0 a 120.');
const ids = (max: number, label: string) => z.array(uuidText, {error: label}).min(1, label).max(max, label);
const words = (label: string) => z.array(z.string().min(1, label).max(80, label), {error: label}).min(1, label).max(30, label);

export const pushAudienceSchema = z
  .strictObject(
    {
      roles: z.array(z.enum(pushRoles), {error: 'Escolha funções válidas.'}).min(1).max(8).optional(),
      cells: ids(100, 'Escolha até 100 células.').optional(),
      groups: ids(100, 'Escolha até 100 ministérios ou departamentos.').optional(),
      ageMin: age.optional(),
      ageMax: age.optional(),
      gender: z.string().min(1).max(30, 'Gênero inválido.').optional(),
      journey: words('Escolha até 30 etapas da jornada.').optional(),
      tags: words('Escolha até 30 marcadores.').optional(),
      baptized: z.boolean().optional(),
      event: uuidText.optional(),
      birthdayToday: z.boolean().optional(),
    },
    {error: 'Filtro de público desconhecido.'},
  )
  .refine((a) => a.ageMin === undefined || a.ageMax === undefined || a.ageMin <= a.ageMax, {
    message: 'A idade máxima precisa ser maior ou igual à mínima.',
    path: ['ageMax'],
  });

export const pushLinkSchema = z
  .strictObject(
    {screen: z.enum(pushScreens, {error: 'Escolha a tela que abre ao tocar.'}), id: uuidText.optional()},
    {error: 'Escolha a tela que abre ao tocar.'},
  )
  .refine((l) => !(pushScreensWithId as readonly string[]).includes(l.screen) || !!l.id, {message: 'Escolha qual item abre ao tocar.', path: ['id']});

const targets = z
  .array(uuidText, {error: 'Escolha ao menos uma igreja.'})
  .min(1, 'Escolha ao menos uma igreja.')
  .max(pushLimits.targets, `Escolha no máximo ${pushLimits.targets} igrejas.`);

export const pushPreviewSchema = z.strictObject({targets, audience: pushAudienceSchema.optional()});

const instant = (s: string | undefined) => (s ? Date.parse(s) : NaN);

/** Campaign fields as the panel and the app send them on create or edit. */
export const pushCampaignSchema = z
  .strictObject({
    title: trimmed(2, pushLimits.title, `Título: use de 2 a ${pushLimits.title} caracteres.`),
    body: trimmed(2, pushLimits.body, `Mensagem: use de 2 a ${pushLimits.body} caracteres.`),
    link: pushLinkSchema.optional(),
    targets,
    audience: pushAudienceSchema.optional(),
    mode: z.enum(pushModes, {error: 'Escolha quando enviar.'}).optional(),
    sendAt: z.string().optional(),
    recurrence: z.enum(pushRecurrences, {error: 'Escolha a repetição.'}).optional(),
    recurrenceUntil: z.string().optional(),
    request: uuidText.optional(),
  })
  .superRefine((c, ctx) => {
    const now = Date.now(),
      at = c.mode === 'now' ? now : instant(c.sendAt);
    if (c.mode === 'schedule' && (!Number.isFinite(at) || at < now - 60_000 || at > now + 366 * 86_400_000))
      ctx.addIssue({code: 'custom', path: ['sendAt'], message: 'Escolha uma data e hora futura, em até um ano.'});
    if (c.sendAt && c.mode !== 'now' && !Number.isFinite(instant(c.sendAt)))
      ctx.addIssue({code: 'custom', path: ['sendAt'], message: 'Data e hora inválidas.'});
    if ((c.recurrence || 'none') !== 'none' && c.recurrenceUntil) {
      const until = instant(c.recurrenceUntil);
      if (!Number.isFinite(until) || !Number.isFinite(at) || until <= at || until > at + 366 * 86_400_000)
        ctx.addIssue({code: 'custom', path: ['recurrenceUntil'], message: 'O fim da repetição precisa ser depois do primeiro envio, em até um ano.'});
    }
  });

export type PushAudience = z.infer<typeof pushAudienceSchema>;
export type PushLink = z.infer<typeof pushLinkSchema>;
export type PushCampaignInput = z.infer<typeof pushCampaignSchema>;

/** Reach shown before sending. */
export type PushReach = {devices: number; people: number};
/** Destinations the server lets this person publish to (`GET /api/push/campaigns?options=1`). */
export type PushOptions = {
  units: {id: string; name: string}[];
  cells: {id: string; name: string; unit: string}[];
  groups: {id: string; name: string; kind?: string; unit: string}[];
  events?: {id: string; title: string; startsAt: string}[];
  journey?: string[];
  tags?: string[];
  genders?: string[];
};

// ── API command (POST /api/push/campaigns) ───────────────────────────────────
export const pushActions = ['list', 'detail', 'options', 'preview', 'create', 'edit', 'cancel'] as const;
export type PushAction = (typeof pushActions)[number];
export type PushCommand = {unit: string; action: PushAction; id: string | null; version: number | null; data: Record<string, unknown>};

const commandSchema = z
  .strictObject({
    unit: uuidText,
    action: z.enum(pushActions),
    id: z.union([uuidText, z.literal(''), z.null()]).optional(),
    version: z.union([z.number().int().positive(), z.null()]).optional(),
    data: z.record(z.string(), z.unknown()).optional(),
  })
  .superRefine((c, ctx) => {
    if (['detail', 'edit', 'cancel'].includes(c.action) && !c.id) ctx.addIssue({code: 'custom', path: ['id'], message: 'Campanha não informada.'});
    if (['edit', 'cancel'].includes(c.action) && !c.version) ctx.addIssue({code: 'custom', path: ['version'], message: 'Atualize a campanha antes de salvar.'});
  });

/** Parses a push command; `fields` names what to fix (paths relative to the campaign form). */
export function parsePushCommand(v: unknown): {ok: true; value: PushCommand} | {ok: false; error: z.ZodError; scope: 'command' | 'data'} {
  const c = commandSchema.safeParse(v);
  if (!c.success) return {ok: false, error: c.error, scope: 'command'};
  const data = c.data.data ?? {};
  const value: PushCommand = {unit: c.data.unit, action: c.data.action, id: c.data.id || null, version: c.data.version ?? null, data};
  if (value.action === 'preview') {
    const p = pushPreviewSchema.safeParse(data);
    if (!p.success) return {ok: false, error: p.error, scope: 'data'};
  }
  if (value.action === 'create' || value.action === 'edit') {
    const p = pushCampaignSchema
      .refine((d) => value.action !== 'create' || !!d.request, {message: 'Abra o formulário novamente antes de enviar.', path: ['request']})
      .safeParse(data);
    if (!p.success) return {ok: false, error: p.error, scope: 'data'};
  }
  return {ok: true, value};
}
