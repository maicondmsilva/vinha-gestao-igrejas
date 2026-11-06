// Event and sale checkout (with or without an account): same rules on the public page, the apps and /api/event-orders.
// Stock, limits per CPF, coupons and required questions stay with the database (event_ticket_checkout).
import {z} from 'zod';
import {cpfValid, emailText} from './primitives.ts';
import {validationBody} from './errors.ts';

const text = (max: number, label: string) => z.string({error: label}).max(max, label);
const optionalEmail = z.union([z.literal(''), emailText('E-mail do participante')]);

export const ticketParticipantSchema = z.strictObject({
  type: text(36, 'Escolha o ingresso.').min(1, 'Escolha o ingresso.'),
  name: text(160, 'Nome: use até 160 caracteres.').refine((s) => s.trim().length >= 2, 'Informe o nome do participante.'),
  email: optionalEmail,
  cpf: text(18, 'CPF inválido.').refine((s) => !s.trim() || cpfValid(s), 'Confira o CPF: os dígitos não conferem.'),
  phone: text(22, 'Telefone: use até 22 caracteres.'),
  answers: z.record(z.string(), text(1000, 'Resposta: use até 1000 caracteres.')).refine((a) => Object.keys(a).length <= 30, 'Respostas demais.'),
});

export const ticketCheckoutSchema = z
  .strictObject({
    buyerName: text(160, 'Nome: use até 160 caracteres.').refine((s) => s.trim().length >= 2, 'Informe seu nome completo.'),
    buyerEmail: emailText('E-mail'),
    emailConfirmation: text(254, 'Confirme o e-mail.'),
    coupon: text(40, 'Cupom: use até 40 caracteres.'),
    intent: z.enum(['pay', 'reserve'], {error: 'Escolha pagar agora ou reservar.'}),
    expectedTotal: z.unknown().optional(),
    revision: z.unknown().optional(),
    emailConsent: z.boolean().optional(),
    items: z
      .array(ticketParticipantSchema, {error: 'Escolha ao menos um ingresso.'})
      .min(1, 'Escolha ao menos um ingresso.')
      .max(20, 'Até 20 ingressos por pedido.'),
  })
  .refine((v) => v.emailConfirmation.trim().toLowerCase() === v.buyerEmail.trim().toLowerCase(), {
    message: 'Os e-mails não conferem.',
    path: ['emailConfirmation'],
  });

export type TicketCheckoutInput = z.infer<typeof ticketCheckoutSchema>;

/** Null when the buyer form is acceptable; otherwise the error body naming the fields to fix. */
export function ticketBuyerIssue(v: unknown) {
  const r = ticketCheckoutSchema.safeParse(v);
  return r.success ? null : validationBody(r.error, 'Revise o comprador e os participantes.');
}
