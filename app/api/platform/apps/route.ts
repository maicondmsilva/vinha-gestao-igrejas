import {centralRoute, OperationError, requireValue, uuid} from '../../../lib/supabase/operations';
import {boundedBody} from '../../../lib/private-files';

// Central › Aplicativos: GET lista os ministérios com app contratado; PATCH salva a liberação e a personalização.
// O banco (platform_apps) confere operador com segundo fator e só deixa a administração salvar.
const reasons: Record<string, [string, number]> = {
  platform_apps_conflict: ['Outro operador alterou este app. Atualize a lista antes de salvar.', 409],
  platform_apps_store_ids: ['Para marcar como “na loja” ou “publicado”, informe o identificador Android ou iOS.', 400],
  platform_operator_required: ['Somente a administração da Vinha altera aplicativos.', 403],
  organization_not_found: ['Ministério não encontrado.', 404],
};
function fail(message = ''): never {
  const hit = Object.entries(reasons).find(([k]) => message.includes(k));
  if (hit) throw new OperationError(hit[1][0], hit[1][1]);
  if (message.includes('check constraint') || message.includes('invalid_platform_apps')) throw new OperationError('Revise o nome (até 30 letras) e os identificadores de loja.', 400);
  throw new OperationError('Não foi possível concluir. Tente novamente.', 503);
}
export const GET = centralRoute(async (_request, client) => {
  const r = await client.rpc('platform_apps', {p_action: 'list', p_org: null, p_data: {}});
  if (r.error) fail(r.error.message);
  return r.data as Record<string, unknown>;
});
export const PATCH = centralRoute(async (request, client) => {
  requireValue(request.headers.get('origin') === new URL(request.url).origin, 'Origem inválida.', 403);
  let body: {organizationId?: unknown; data?: unknown};
  try {
    body = JSON.parse(new TextDecoder().decode(await boundedBody(request, 6000)));
  } catch {
    throw new OperationError('Formato inválido.', 400);
  }
  requireValue(uuid(body.organizationId) && body.data && typeof body.data === 'object' && !Array.isArray(body.data), 'Dados inválidos.');
  const r = await client.rpc('platform_apps', {p_action: 'save', p_org: body.organizationId, p_data: body.data});
  if (r.error) fail(r.error.message);
  return r.data as Record<string, unknown>;
});
