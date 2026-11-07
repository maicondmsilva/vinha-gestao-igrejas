// iCalendar (RFC 5545) for the church agenda: one event ("Adicionar ao calendário") or a subscription feed.
// Times go out in UTC, so every calendar app shows them right in its own zone.

export type IcsEvent = {
  id: string;
  title: string;
  description?: string | null;
  starts_at: string;
  ends_at: string;
  location?: string | null;
  address?: string | null;
  status?: string;
  version?: number;
  updated_at?: string;
  url?: string;
};

const utc = (v: string | Date) =>
  new Date(v)
    .toISOString()
    .replace(/[-:]/g, '')
    .replace(/\.\d{3}Z$/, 'Z');
/** Escapes TEXT values (backslash, semicolon, comma, newlines) and drops other control characters. */
export const icsText = (v: string) =>
  v
    .replace(/[\u0000-\u0008\u000b-\u001f\u007f]/g, '')
    .replace(/\\/g, '\\\\')
    .replace(/;/g, '\\;')
    .replace(/,/g, '\\,')
    .replace(/\r?\n/g, '\\n');

/** Folds lines at 75 octets (UTF-8), continuation lines start with a space. */
export function icsFold(line: string) {
  const enc = new TextEncoder(),
    out: string[] = [];
  let cur = '',
    size = 0;
  for (const ch of line) {
    const n = enc.encode(ch).length;
    if (size + n > (out.length ? 74 : 75)) {
      out.push(cur);
      cur = '';
      size = 0;
    }
    cur += ch;
    size += n;
  }
  out.push(cur);
  return out.join('\r\n ');
}

export function icsCalendar(opts: {name: string; timezone?: string; events: IcsEvent[]; host?: string; now?: Date}) {
  const host = opts.host || 'vinhaigrejas.com.br',
    stamp = utc(opts.now || new Date());
  const lines = [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//Vinha//Agenda da igreja//PT-BR',
    'CALSCALE:GREGORIAN',
    'METHOD:PUBLISH',
    'X-WR-CALNAME:' + icsText(opts.name),
  ];
  if (opts.timezone) lines.push('X-WR-TIMEZONE:' + opts.timezone);
  lines.push('REFRESH-INTERVAL;VALUE=DURATION:PT6H', 'X-PUBLISHED-TTL:PT6H');
  for (const e of opts.events) {
    if (!Number.isFinite(Date.parse(e.starts_at)) || !Number.isFinite(Date.parse(e.ends_at))) continue;
    const place = [e.location, e.address].filter((x) => x && x.trim()).join(' · ');
    lines.push(
      'BEGIN:VEVENT',
      `UID:${e.id}@${host}`,
      'DTSTAMP:' + stamp,
      'DTSTART:' + utc(e.starts_at),
      'DTEND:' + utc(e.ends_at),
      'SUMMARY:' + icsText(e.title),
      ...(e.description ? ['DESCRIPTION:' + icsText(e.description.slice(0, 4000))] : []),
      ...(place ? ['LOCATION:' + icsText(place)] : []),
      ...(e.url ? ['URL:' + e.url] : []),
      ...(e.updated_at ? ['LAST-MODIFIED:' + utc(e.updated_at)] : []),
      ...(Number.isInteger(e.version) ? ['SEQUENCE:' + e.version] : []),
      'STATUS:' + (e.status === 'cancelled' ? 'CANCELLED' : 'CONFIRMED'),
      'END:VEVENT',
    );
  }
  lines.push('END:VCALENDAR');
  return lines.map(icsFold).join('\r\n') + '\r\n';
}

/** Safe file name for a downloaded event. */
export const icsFileName = (title: string) =>
  (title
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/[^a-zA-Z0-9]+/g, '-')
    .replace(/^-|-$/g, '')
    .toLowerCase()
    .slice(0, 60) || 'evento') + '.ics';
