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
