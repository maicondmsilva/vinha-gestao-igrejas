import {toLocalInput} from './timezone.ts';
import type {Availability} from './use-volunteer-scales';
export type AvailabilityDraft = {
  id: string;
  version: number;
  kind: 'weekly' | 'unavailable';
  weekday: number;
  startDate: string;
  endDate: string;
  startTime: string;
  endTime: string;
  reason: string;
};
export const minutesText = (n: number) => String(Math.floor(n / 60)).padStart(2, '0') + ':' + String(n % 60).padStart(2, '0');
export function clockMinutes(text: string, end = false) {
  if (!/^\d{2}:\d{2}$/.test(text)) throw Error('Use horas no formato HH:mm.');
  const [h, m] = text.split(':').map(Number);
  if ((h > 23 && !(end && h === 24 && m === 0)) || m > 59) throw Error('Informe um horário válido.');
  return h * 60 + m;
}
function day(text: string) {
  const br = /^(\d{2})\/(\d{2})\/(\d{4})$/.exec(text);
  const value = br ? `${br[3]}-${br[2]}-${br[1]}` : text;
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) throw Error('Informe a data completa.');
  const d = new Date(value + 'T12:00Z');
  if (Number.isNaN(d.getTime()) || d.toISOString().slice(0, 10) !== value) throw Error('Confira o dia, o mês e o ano da data.');
  return value;
}
export function availabilityPayload(f: AvailabilityDraft) {
  const a = clockMinutes(f.startTime),
    b = clockMinutes(f.endTime, f.kind === 'weekly');
  if (f.kind === 'weekly') {
    if (a >= b) throw Error('O fim precisa ser depois do início. Para atravessar a meia-noite, cadastre um período em cada dia.');
    return {id: f.id, version: f.version, kind: f.kind, weekday: f.weekday, startMinute: a, endMinute: b, reason: f.reason, active: true};
  }
  const startsLocal = day(f.startDate) + 'T' + f.startTime,
    endsLocal = day(f.endDate) + 'T' + f.endTime;
  if (endsLocal <= startsLocal) throw Error('O fim da indisponibilidade precisa ser depois do início.');
  return {id: f.id, version: f.version, kind: f.kind, startsLocal, endsLocal, reason: f.reason, active: true};
}
export function availabilityDraft(id: string, zone: string, a?: Availability): AvailabilityDraft {
  const today = toLocalInput(new Date(), zone).slice(0, 10),
    start = a?.starts_at ? toLocalInput(a.starts_at, zone) : '',
    end = a?.ends_at ? toLocalInput(a.ends_at, zone) : '';
  return {
    id: a?.id || id,
    version: a?.version || 0,
    kind: a?.kind || 'weekly',
    weekday: a?.weekday || 0,
    startDate: start.slice(0, 10) || today,
    endDate: end.slice(0, 10) || today,
    startTime: a?.kind === 'weekly' ? minutesText(a.start_minute) : start.slice(11) || '18:00',
    endTime: a?.kind === 'weekly' ? minutesText(a.end_minute) : end.slice(11) || '22:00',
    reason: a?.reason || '',
  };
}
