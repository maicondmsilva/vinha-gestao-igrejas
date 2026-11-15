// Área Kids da família: idade em texto e a reserva que importa agora para cada criança.
import type {FamilyBooking} from './member-family';

/** "6 anos", "1 ano", "8 meses". */
export function childAge(birth: string, today = new Date()) {
  const b = new Date(birth + 'T12:00:00');
  if (!Number.isFinite(b.getTime())) return '';
  let months = (today.getFullYear() - b.getFullYear()) * 12 + today.getMonth() - b.getMonth();
  if (today.getDate() < b.getDate()) months--;
  if (months < 12) return Math.max(0, months) + (months === 1 ? ' mês' : ' meses');
  const y = Math.floor(months / 12);
  return y + (y === 1 ? ' ano' : ' anos');
}

/** Reserva em andamento da criança: na sala agora > próxima reservada > nenhuma. */
export function childNextBooking(list: FamilyBooking[], child: string, now = Date.now()) {
  const mine = list.filter((r) => r.profile_id === child && r.status === 'reserved' && Date.parse(r.ends_at) > now && r.attendance !== 'out');
  return mine.find((r) => r.attendance === 'present') || mine.sort((a, b) => Date.parse(a.starts_at) - Date.parse(b.starts_at))[0] || null;
}
