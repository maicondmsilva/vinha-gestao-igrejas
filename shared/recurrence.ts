// Recurring events: the same rule the database applies (private.programming_repeat_count).
// Occurrences are created up front; "sem término" creates the next 12 months, up to 120 dates.

export const repeatRules = ['none', 'daily', 'weekly', 'monthly', 'yearly'] as const;
export type RepeatRule = (typeof repeatRules)[number];
export const repeatEnds = ['count', 'until', 'never'] as const;
export type RepeatEnd = (typeof repeatEnds)[number];
export const maxOccurrences = 120;
export const repeatLabel: Record<RepeatRule, string> = {none: 'Evento único', daily: 'Diária', weekly: 'Semanal', monthly: 'Mensal', yearly: 'Anual'};

const localPattern = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/,
  dayPattern = /^\d{4}-\d{2}-\d{2}$/;

/** Wall-clock arithmetic in UTC fields (no zone): the database does the same on `timestamp` values. */
function shift(local: string, rule: RepeatRule, i: number) {
  const [d, t] = local.split('T'),
    [y, m, day] = d.split('-').map(Number),
    [h, min] = t.split(':').map(Number);
  if (rule === 'daily') return Date.UTC(y, m - 1, day + i, h, min);
  if (rule === 'weekly') return Date.UTC(y, m - 1, day + 7 * i, h, min);
  // Postgres adds months/years clamping to the month's last day (Jan 31 + 1 month = Feb 28/29).
  const months = rule === 'monthly' ? i : rule === 'yearly' ? 12 * i : 0,
    ty = y + Math.floor((m - 1 + months) / 12),
    tm = (m - 1 + months) % 12,
    last = new Date(Date.UTC(ty, tm + 1, 0)).getUTCDate();
  return Date.UTC(ty, tm, Math.min(day, last), h, min);
}

/** Start of each occurrence (`YYYY-MM-DDTHH:mm`), as the database will create them. */
export function occurrences(startsLocal: string, rule: RepeatRule, count: number) {
  return Array.from({length: count}, (_, i) => new Date(shift(startsLocal, rule, i)).toISOString().slice(0, 16));
}

export type RecurrenceInput = {startsLocal: string; repeat: RepeatRule; ends?: RepeatEnd; count?: number; until?: string; now?: number};
/** The agenda accepts dates up to 2 years ahead (member_agenda_admin). */
export const horizonYears = 2;

/** How many dates the rule creates, or an error message to show next to the field. */
export function recurrenceCount(r: RecurrenceInput): {count: number} | {error: string; field: 'count' | 'until' | 'repeat'} {
  if (!repeatRules.includes(r.repeat)) return {error: 'Escolha como o evento se repete.', field: 'repeat'};
  if (r.repeat === 'none') return {count: 1};
  if (!localPattern.test(r.startsLocal)) return {error: 'Informe o início do primeiro encontro.', field: 'repeat'};
  const ends = r.ends || 'count',
    now = new Date(r.now ?? Date.now()),
    horizon = Date.UTC(now.getUTCFullYear() + horizonYears, now.getUTCMonth(), now.getUTCDate(), now.getUTCHours(), now.getUTCMinutes());
  let n: number;
  if (ends === 'count') {
    n = Number(r.count);
    if (!Number.isInteger(n) || n < 2 || n > maxOccurrences) return {error: `Use de 2 a ${maxOccurrences} encontros.`, field: 'count'};
  } else {
    let limit: number;
    if (ends === 'until') {
      if (!r.until || !dayPattern.test(r.until)) return {error: 'Escolha a data do último encontro.', field: 'until'};
      const [y, m, d] = r.until.split('-').map(Number);
      limit = Date.UTC(y, m - 1, d + 1);
    } else limit = shift(r.startsLocal, 'monthly', 12);
    n = 0;
    while (n <= maxOccurrences && shift(r.startsLocal, r.repeat, n) < limit) n++;
    if (n < 1) return {error: 'A data final precisa ser depois do primeiro encontro.', field: 'until'};
    if (ends === 'until' && n > maxOccurrences)
      return {error: `Essa repetição passa de ${maxOccurrences} encontros. Escolha uma data mais próxima.`, field: 'until'};
    n = Math.min(n, maxOccurrences);
    // "Sem término" stops at the agenda horizon instead of failing.
    if (ends === 'never') while (n > 1 && shift(r.startsLocal, r.repeat, n - 1) > horizon) n--;
  }
  if (shift(r.startsLocal, r.repeat, n - 1) > horizon)
    return {
      error: `A agenda aceita datas até ${horizonYears} anos à frente. Diminua a quantidade ou escolha uma data mais próxima.`,
      field: ends === 'until' ? 'until' : 'count',
    };
  return {count: n};
}

/** Shape check used by the panel API before the database (which repeats every rule). */
export function recurrenceValid(data: Record<string, unknown>) {
  const repeat = String(data.repeat) as RepeatRule;
  if (!repeatRules.includes(repeat)) return false;
  if ('ends' in data && !repeatEnds.includes(data.ends as RepeatEnd)) return false;
  const ends = (data.ends as RepeatEnd | undefined) || 'count';
  if (repeat === 'none') return !('ends' in data && ends !== 'count') && !('until' in data) && data.count === 1;
  if (ends === 'count') return !('until' in data) && Number.isInteger(data.count) && Number(data.count) >= 1 && Number(data.count) <= maxOccurrences;
  if ('count' in data) return false;
  if (ends === 'until') return typeof data.until === 'string' && dayPattern.test(data.until);
  return !('until' in data);
}
