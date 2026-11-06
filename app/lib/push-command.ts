// Shape check for the push panel API, using the rules shared with the panel form and Vinha Equipe.
// The database repeats every rule; this answers early and names the field to fix.
import {parsePushCommand, type PushCommand} from '../../shared/contract/push.ts';
import {validationBody, type ApiErrorBody} from '../../shared/contract/errors.ts';

export type {PushCommand};

export function pushCommand(v: unknown): PushCommand | null {
  const r = parsePushCommand(v);
  return r.ok ? r.value : null;
}

/** Same as pushCommand, with the error body to send when refused. */
export function pushCommandResult(v: unknown): {ok: true; value: PushCommand} | {ok: false; body: ApiErrorBody} {
  const r = parsePushCommand(v);
  if (r.ok) return r;
  return {
    ok: false,
    body: r.scope === 'data' ? validationBody(r.error, 'Revise os campos da campanha.') : {error: 'Revise os campos da campanha.', code: 'validation'},
  };
}
