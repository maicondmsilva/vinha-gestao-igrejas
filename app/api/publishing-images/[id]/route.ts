import {db} from '../../../lib/supabase/operations';
import {supabaseAdminClient} from '../../../lib/supabase/server-admin';
import {uuidPattern} from '../../../lib/private-files';

// Serves a library image: public when used in a published notice of the same ministry, otherwise only to its publishers.
export async function GET(request: Request) {
  try {
    const id = new URL(request.url).pathname.split('/').pop() || '';
    if (!uuidPattern.test(id)) return new Response(null, {status: 404});
    const r = await db(request).rpc('publishing_image_file', {p_id: id});
    const meta = r.data as {path?: string; mime?: string; public?: boolean} | null;
    if (r.error || !meta?.path || !meta.mime) return new Response(null, {status: 404, headers: {'Cache-Control': 'no-store'}});
    const file = await supabaseAdminClient().storage.from('vinha-publishing-images').download(meta.path);
    if (file.error || !file.data) return new Response(null, {status: 404, headers: {'Cache-Control': 'no-store'}});
    return new Response(await file.data.arrayBuffer(), {
      headers: {
        'Content-Type': meta.mime,
        'X-Content-Type-Options': 'nosniff',
        'Content-Security-Policy': "default-src 'none'",
        // Ids never point to other content; published images can be cached by the apps and the CDN.
        'Cache-Control': meta.public ? 'public, max-age=86400' : 'private, no-store',
      },
    });
  } catch {
    return new Response(null, {status: 503});
  }
}
