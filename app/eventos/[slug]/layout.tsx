import type {Metadata} from 'next';
import type {ReactNode} from 'react';

const eventPath = /^e-([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$/i;

type PublicEventPage = {
  event?: {title?: string; description?: string; cover_url?: string; starts_at?: string; location?: string; commerce_mode?: string};
  church?: {name?: string; unit_name?: string; logo?: string};
};

/** Reads the same public RPC the page uses (anon role), only for link previews. */
async function publicEvent(id: string): Promise<PublicEventPage | null> {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL,
    key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
  if (!url || !key) return null;
  try {
    const r = await fetch(url + '/rest/v1/rpc/member_event_page', {
      method: 'POST',
      headers: {apikey: key, Authorization: 'Bearer ' + key, 'Content-Type': 'application/json'},
      body: JSON.stringify({p_event: id}),
      signal: AbortSignal.timeout(4000),
      cache: 'no-store',
    });
    if (!r.ok) return null;
    return (await r.json()) as PublicEventPage | null;
  } catch {
    return null;
  }
}

const https = (value?: string) => {
  try {
    return value && new URL(value).protocol === 'https:' ? value : undefined;
  } catch {
    return undefined;
  }
};

export async function generateMetadata({params}: {params: Promise<{slug: string}> | {slug: string}}): Promise<Metadata> {
  const {slug} = await params;
  const id = eventPath.exec(slug || '')?.[1];
  const data = id ? await publicEvent(id) : null;
  if (!data?.event?.title) return {title: 'Encontro · Vinha', robots: {index: false}};
  const e = data.event,
    church = [data.church?.unit_name, data.church?.name].filter(Boolean).join(' · '),
    when = e.starts_at
      ? new Intl.DateTimeFormat('pt-BR', {dateStyle: 'full', timeStyle: 'short', timeZone: 'America/Sao_Paulo'}).format(new Date(e.starts_at))
      : '',
    description =
      [when, e.location].filter(Boolean).join(' · ') +
      (e.description ? ' — ' + e.description.replace(/\s+/g, ' ').slice(0, 160) : ''),
    image = https(e.cover_url) || https(data.church?.logo),
    title = e.title + (church ? ' · ' + church : '');
  return {
    title,
    description,
    openGraph: {
      type: 'website',
      locale: 'pt_BR',
      siteName: 'Vinha',
      title,
      description,
      ...(image ? {images: [{url: image}]} : {}),
    },
    twitter: {card: image ? 'summary_large_image' : 'summary', title, description, ...(image ? {images: [image]} : {})},
  };
}

export default function EventLayout({children}: {children: ReactNode}) {
  return children;
}
