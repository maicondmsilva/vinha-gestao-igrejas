// Imagens do app: capas e banners vêm como endereço HTTPS ou como caminho da plataforma (/api/event-images/…, /api/publishing-images/…).
export const platformOrigin = 'https://app.vinhaigrejas.com.br';
const uuid = '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}';
const platformPath = new RegExp(`^/api/(event-images|publishing-images)/${uuid}$`, 'i');

/** Endereço completo e seguro da imagem, ou null quando não há imagem válida. */
export function appImage(value?: string | null): string | null {
  const v = (value || '').trim();
  if (!v) return null;
  if (platformPath.test(v)) return platformOrigin + v;
  try {
    const u = new URL(v);
    return u.protocol === 'https:' && !u.username && !u.password ? u.toString() : null;
  } catch {
    return null;
  }
}

/** Link do vídeo para abrir no app do provedor (YouTube ou Vimeo) ou compartilhar. */
export function watchLink(source?: string | null): string | null {
  const v = (source || '').trim();
  try {
    const u = new URL(v);
    if (u.protocol !== 'https:') return null;
    const host = u.hostname.replace(/^www\.|^m\./, '');
    if (host === 'youtu.be') return 'https://youtu.be/' + u.pathname.slice(1).split('/')[0];
    if (host === 'youtube.com' || host === 'youtube-nocookie.com') {
      const id = u.searchParams.get('v') || u.pathname.match(/\/(?:embed|live|shorts)\/([\w-]{6,})/)?.[1];
      return id ? 'https://www.youtube.com/watch?v=' + id : null;
    }
    if (host === 'vimeo.com' || host === 'player.vimeo.com') {
      const id = u.pathname.match(/(\d{5,})/)?.[1];
      return id ? 'https://vimeo.com/' + id : null;
    }
    return u.toString();
  } catch {
    return null;
  }
}
