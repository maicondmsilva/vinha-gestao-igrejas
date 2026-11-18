import {centralRoute, OperationError, requireValue, uuid} from '../../../../lib/supabase/operations';
import {supabaseAdminClient} from '../../../../lib/supabase/server-admin';
import {boundedBody} from '../../../../lib/private-files';
import {iconOk} from '../../../../lib/app-icon';

// Central › Aplicativos › Identidade: nome no app, cores, logo, abertura (foto/vídeo) e ícone do celular.
// Só a equipe da Vinha altera (o banco confere operador com segundo fator e papel de administração).
// Arquivos grandes vão direto do navegador para o armazenamento por um link de envio assinado e de uso único.
const BUCKET = 'vinha-app-assets';
const uploads = {
  'opening-image': {types: ['image/jpeg', 'image/png', 'image/webp'], max: 5 * 1024 * 1024},
  'opening-video': {types: ['video/mp4'], max: 50 * 1024 * 1024},
  icon: {types: ['image/png'], max: 1024 * 1024},
} as const;
const ext: Record<string, string> = {'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp', 'video/mp4': 'mp4'};
const reasons: Record<string, [string, number]> = {
  identity_changed: ['Outro operador alterou esta identidade. Atualize antes de salvar.', 409],
  invalid_logo: ['A logo deve ser PNG de até 250 KB e até 2.000 pixels por lado.', 400],
  app_not_released: ['Libere o aplicativo antes de enviar o ícone.', 400],
  platform_operator_required: ['Somente a administração da Vinha altera a identidade dos apps.', 403],
  organization_not_found: ['Ministério não encontrado.', 404],
};
function fail(message = ''): never {
  const hit = Object.entries(reasons).find(([k]) => message.includes(k));
  if (hit) throw new OperationError(hit[1][0], hit[1][1]);
  if (message.includes('invalid_identity') || message.includes('check constraint'))
    throw new OperationError('Revise os dados: nome de 2 a 60 letras, cores no formato #RRGGBB, abertura com imagem ou vídeo MP4 de 1 a 15 segundos.', 400);
  throw new OperationError('Não foi possível concluir. Tente novamente.', 503);
}
async function body<T>(request: Request, limit: number): Promise<T> {
  requireValue(request.headers.get('origin') === new URL(request.url).origin, 'Origem inválida.', 403);
  try {
    return JSON.parse(new TextDecoder().decode(await boundedBody(request, limit))) as T;
  } catch {
    throw new OperationError('Formato inválido.', 400);
  }
}
export const GET = centralRoute(async (request, client) => {
  const org = new URL(request.url).searchParams.get('org');
  requireValue(uuid(org), 'Ministério inválido.');
  const r = await client.rpc('platform_app_identity', {p_action: 'get', p_org: org, p_data: {}});
  if (r.error) fail(r.error.message);
  return r.data as Record<string, unknown>;
});

// POST: pede um link de envio para foto/vídeo de abertura ou ícone.
export const POST = centralRoute(async (request, client) => {
  const b = await body<{organizationId?: unknown; kind?: unknown; contentType?: unknown; size?: unknown}>(request, 1000);
  const rule = uploads[b.kind as keyof typeof uploads];
  requireValue(uuid(b.organizationId) && rule, 'Dados inválidos.');
  requireValue(
    (rule.types as readonly string[]).includes(String(b.contentType)),
    b.kind === 'icon' ? 'O ícone deve ser PNG.' : b.kind === 'opening-video' ? 'O vídeo deve ser MP4.' : 'Use imagem JPG, PNG ou WebP.',
  );
  requireValue(typeof b.size === 'number' && b.size > 0 && b.size <= rule.max, `Arquivo acima do limite de ${Math.round(rule.max / 1048576)} MB.`);
  // Confere operador e ministério antes de emitir o link.
  const check = await client.rpc('platform_app_identity', {p_action: 'get', p_org: b.organizationId, p_data: {}});
  if (check.error) fail(check.error.message);
  requireValue((check.data as {canEdit?: boolean}).canEdit === true, 'Somente a administração da Vinha altera a identidade dos apps.', 403);
  const path = `${b.organizationId}/${b.kind === 'icon' ? 'icon' : 'opening'}-${crypto.randomUUID()}.${ext[String(b.contentType)]}`;
  const storage = supabaseAdminClient().storage.from(BUCKET);
  const signed = await storage.createSignedUploadUrl(path);
  if (signed.error || !signed.data) throw new OperationError('Envio de arquivos indisponível no momento.', 503);
  return {path, token: signed.data.token, publicUrl: storage.getPublicUrl(path).data.publicUrl};
});

// PATCH: salva nome/cores, logo, abertura ou ícone.
export const PATCH = centralRoute(async (request, client) => {
  const b = await body<{organizationId?: unknown; action?: unknown; data?: unknown}>(request, 360000);
  requireValue(
    uuid(b.organizationId) &&
      ['identity', 'logo', 'opening', 'icon'].includes(String(b.action)) &&
      b.data &&
      typeof b.data === 'object' &&
      !Array.isArray(b.data),
    'Dados inválidos.',
  );
  const data = b.data as Record<string, unknown>;
  if (b.action === 'icon' && data.url) {
    const url = String(data.url),
      prefix = supabaseAdminClient().storage.from(BUCKET).getPublicUrl(`${b.organizationId}/`).data.publicUrl;
    requireValue(url.startsWith(prefix) && /\/icon-[0-9a-f-]{36}\.png$/.test(url), 'Ícone inválido.');
    const file = await supabaseAdminClient()
      .storage.from(BUCKET)
      .download(url.slice(prefix.length - `${b.organizationId}/`.length));
    if (file.error || !file.data) throw new OperationError('Ícone não encontrado. Envie novamente.', 400);
    requireValue(iconOk(new Uint8Array(await file.data.arrayBuffer())), 'O ícone deve ser PNG quadrado de 1024 × 1024 pixels e até 1 MB.');
  }
  const r = await client.rpc('platform_app_identity', {p_action: b.action, p_org: b.organizationId, p_data: data});
  if (r.error) fail(r.error.message);
  return r.data as Record<string, unknown>;
});
