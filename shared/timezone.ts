// Church time zones: the database stores instants (timestamptz) and interprets "local" inputs in the unit's zone
// (private.unit_timezone). The panel and the apps show and edit times in that same zone.

export const defaultTimezone = 'America/Sao_Paulo';

/** Zones offered in the settings (Brazil first, then common mission fields). Any valid IANA name is accepted by the database. */
export const churchTimezones: readonly (readonly [string, string])[] = [
  ['America/Sao_Paulo', 'Brasília (SP, RJ, MG, Sul, GO, DF, BA, Nordeste)'],
  ['America/Noronha', 'Fernando de Noronha'],
  ['America/Manaus', 'Amazonas (Manaus)'],
  ['America/Cuiaba', 'Mato Grosso (Cuiabá)'],
  ['America/Campo_Grande', 'Mato Grosso do Sul (Campo Grande)'],
  ['America/Porto_Velho', 'Rondônia (Porto Velho)'],
  ['America/Boa_Vista', 'Roraima (Boa Vista)'],
  ['America/Rio_Branco', 'Acre (Rio Branco)'],
  ['Europe/Lisbon', 'Portugal (Lisboa)'],
  ['America/New_York', 'Estados Unidos (Leste)'],
  ['America/Chicago', 'Estados Unidos (Central)'],
  ['America/Los_Angeles', 'Estados Unidos (Pacífico)'],
  ['Europe/London', 'Reino Unido (Londres)'],
  ['Asia/Tokyo', 'Japão (Tóquio)'],
];

export function timezoneValid(tz: string) {
  if (!/^[A-Za-z]+(\/[A-Za-z0-9_+-]+){1,2}$/.test(tz)) return false;
  try {
    new Intl.DateTimeFormat('en-US', {timeZone: tz});
    return true;
  } catch {
    return false;
  }
}

const safe = (tz: string | undefined | null) => (tz && timezoneValid(tz) ? tz : defaultTimezone);

function parts(date: Date, tz: string) {
  const p = new Intl.DateTimeFormat('en-CA', {
    timeZone: tz,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hourCycle: 'h23',
  }).formatToParts(date);
  const get = (t: string) => p.find((x) => x.type === t)?.value || '00';
  return {year: get('year'), month: get('month'), day: get('day'), hour: get('hour'), minute: get('minute'), second: get('second')};
}

/** Minutes the zone is ahead of UTC at that instant (Brasília: -180). */
export function offsetMinutes(date: Date, tz: string) {
  const x = parts(date, safe(tz));
  return Math.round((Date.UTC(+x.year, +x.month - 1, +x.day, +x.hour, +x.minute, +x.second) - Math.floor(date.getTime() / 1000) * 1000) / 60000);
}

/** `YYYY-MM-DDTHH:mm` of an instant in the zone (value for <input type="datetime-local">). */
export function toLocalInput(value: string | Date, tz?: string | null) {
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return '';
  const x = parts(d, safe(tz));
  return `${x.year}-${x.month}-${x.day}T${x.hour}:${x.minute}`;
}

/** `YYYY-MM-DD` of an instant in the zone. */
export const toLocalDay = (value: string | Date, tz?: string | null) => toLocalInput(value, tz).slice(0, 10);

/** Instant (ms) of a local wall time in the zone; NaN when invalid. */
export function fromLocal(local: string, tz?: string | null) {
  const m = /^(\d{4})-(\d{2})-(\d{2})(?:T(\d{2}):(\d{2}))?$/.exec(local || '');
  if (!m) return NaN;
  const zone = safe(tz),
    wall = Date.UTC(+m[1], +m[2] - 1, +m[3], +(m[4] || 0), +(m[5] || 0));
  // Two passes settle the offset across daylight-saving changes.
  let t = wall - offsetMinutes(new Date(wall), zone) * 60000;
  t = wall - offsetMinutes(new Date(t), zone) * 60000;
  return t;
}

export function formatInZone(value: string | Date, tz?: string | null, options: Intl.DateTimeFormatOptions = {dateStyle: 'short', timeStyle: 'short'}) {
  const d = new Date(value);
  return Number.isNaN(d.getTime()) ? '' : d.toLocaleString('pt-BR', {...options, timeZone: safe(tz)});
}

/** Short label for the zone in the form ("horário de Manaus"). */
export function timezoneLabel(tz?: string | null) {
  const zone = safe(tz);
  if (zone === defaultTimezone) return 'horário de Brasília';
  const city = zone.split('/').pop()!.replace(/_/g, ' ');
  return `horário de ${city}`;
}

// The panel works on one church at a time; screens of that church read its zone from here.
let panelZone = defaultTimezone;
export const panelTimezone = () => panelZone;
export function setPanelTimezone(tz: string | null | undefined) {
  panelZone = safe(tz);
}
