// Shapes the Vinha Equipe app reads from the platform. Change them here and both sides fail to compile together.
import {z} from 'zod';

export type Unit = {id: string; name: string};
/** One ministry from `access_context()` memberships. */
export type Ministry = {
  organization_id: string;
  organization_name: string;
  role: string;
  status: string;
  units: Unit[];
  default_unit_id: string | null;
  primary_color?: string;
};
/** Roles that open the staff app (members and viewers use the ministry app). */
export const staffRoles = ['owner', 'pastor', 'admin', 'secretary', 'finance', 'leader'] as const;
export const staffRoleLabel: Record<string, string> = {
  owner: 'Responsável',
  pastor: 'Pastor(a)',
  admin: 'Administração',
  secretary: 'Secretaria',
  finance: 'Financeiro',
  leader: 'Liderança',
};
export const isStaff = (m: Pick<Ministry, 'role' | 'status'>) => m.status === 'active' && (staffRoles as readonly string[]).includes(m.role);

// Entrance desk (paid tickets: /api/event-tickets-admin; free registrations: /api/programming)
export const ticketCheckinSchema = z.strictObject({
  code: z.string().regex(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/, 'QR Code inválido.'),
});
export type TicketCheckinResult = {ok?: boolean; already?: boolean; name?: string};
export type StaffEvent = {id: string; title: string; starts_at: string; commerce_mode?: string};

const uuidAnywhere = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i;
/** Ticket QR codes carry the ticket code alone or inside a link. */
export const ticketCode = (scanned: string) => uuidAnywhere.exec(scanned || '')?.[0].toLowerCase() || null;

// ── Permissões finas (Etapa 3 · PR 2) ───────────────────────────────────────
/** What a secretary or leader can receive per church. Owners, admins and pastors already do everything. */
export const staffScopes = ['agenda', 'checkin', 'publishing', 'push'] as const;
export type StaffScope = (typeof staffScopes)[number];
export const staffScopeLabel: Record<StaffScope, string> = {
  agenda: 'Agenda e eventos',
  checkin: 'Entrada (QR Code)',
  publishing: 'Avisos e publicações',
  push: 'Push para o app',
};
/** One church in `staff_access('mine')`: what the signed-in person can do there. */
export type StaffUnitAccess = Unit & {
  timezone: string;
  agenda: boolean;
  checkin: boolean;
  publishing: boolean;
  push: boolean;
  /** Kids: coordination, administrative reading or a team assignment in an open or upcoming session. */
  kids?: boolean;
  /** May register and turn off reception stations (Kids coordination or session supervisor). */
  kidsStations?: boolean;
};
export type StaffTeamMember = {user: string; role: string; name: string; email: string; units: string[]; grants: Record<string, StaffScope[]>};
export type StaffAccessList = {
  ok: true;
  timezone: string;
  units: (Unit & {timezone: string; ownTimezone: string | null; autonomy: boolean})[];
  team: StaffTeamMember[];
};

const uuid = z.string().regex(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i, 'Identificador inválido.');
export const staffAccessCommandSchema = z.discriminatedUnion('action', [
  z.strictObject({
    action: z.literal('grant'),
    data: z.strictObject({user: uuid, unit: uuid, scopes: z.array(z.enum(staffScopes, {error: 'Permissão desconhecida.'})).max(4)}),
  }),
  z.strictObject({
    action: z.literal('timezone'),
    data: z.strictObject({
      unit: z.union([uuid, z.literal('')]).optional(),
      timezone: z
        .string()
        .regex(/^([A-Za-z]+(\/[A-Za-z0-9_+-]+){1,2})?$/, 'Escolha um fuso horário válido.')
        .optional(),
    }),
  }),
]);
export type StaffAccessCommand = z.infer<typeof staffAccessCommandSchema>;
