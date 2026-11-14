import {db} from '../../../lib/supabase/operations';
import {supabaseAdminClient} from '../../../lib/supabase/server-admin';
import {consentPdf, type ConsentDoc} from '../../../lib/consent-pdf';

const fail = (status: number, msg: string) =>
  new Response(msg, {status, headers: {'Content-Type': 'text/plain; charset=utf-8', 'Cache-Control': 'private, no-store'}});

/**
 * PDF de um termo assinado. Duas formas de acesso:
 * ?t=TOKEN — link de uso único (10 min) gerado no app por quem assinou; conferido no servidor.
 * ?code=VNH-… — com a sessão do painel: quem assinou ou quem pode ver o cadastro da pessoa.
 */
export async function GET(request: Request) {
  try {
    const q = new URL(request.url).searchParams,
      token = q.get('t'),
      code = (q.get('code') || '').toUpperCase();
    let r: {data: unknown; error: unknown};
    if (token) {
      if (!/^[0-9a-f-]{36}$/i.test(token)) return fail(400, 'Link inválido.');
      r = await supabaseAdminClient().rpc('consent_document', {p_code: null, p_token: token});
    } else {
      if (!/^VNH-[A-Z2-9]{4}-[A-Z2-9]{4}$/.test(code)) return fail(400, 'Código inválido.');
      r = await db(request).rpc('consent_document', {p_code: code, p_token: null});
    }
    if (r.error || !r.data) return fail(403, 'Este link expirou ou você não tem acesso a este termo. Gere um novo link no aplicativo.');
    const d = r.data as ConsentDoc;
    const bytes = await consentPdf(d, new URL('/verificar/', request.url).toString());
    return new Response(new Blob([bytes as Uint8Array<ArrayBuffer>], {type: 'application/pdf'}), {
      headers: {
        'Content-Type': 'application/pdf',
        'Content-Disposition': `inline; filename="termo-${d.code}.pdf"`,
        'Cache-Control': 'private, no-store',
        'Referrer-Policy': 'no-referrer',
      },
    });
  } catch {
    return fail(503, 'Não foi possível gerar o documento agora.');
  }
}
