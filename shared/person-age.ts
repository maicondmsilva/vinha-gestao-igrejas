// Idade a partir da data de nascimento (aaaa-mm-dd): número de anos ou null.
export function personAge(birth: string | null | undefined, today = new Date()): number | null {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(birth || '');
  if (!m) return null;
  const y = Number(m[1]), mo = Number(m[2]), d = Number(m[3]);
  let age = today.getFullYear() - y;
  if (today.getMonth() + 1 < mo || (today.getMonth() + 1 === mo && today.getDate() < d)) age--;
  return age >= 0 && age < 130 ? age : null;
}
/** "6 anos", "1 ano", "8 meses" (abaixo de 1 ano). */
export function personAgeLabel(birth: string | null | undefined, today = new Date()) {
  const a = personAge(birth, today);
  if (a === null) return '';
  if (a >= 1) return a + (a === 1 ? ' ano' : ' anos');
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(birth || '')!;
  let months = (today.getFullYear() - Number(m[1])) * 12 + today.getMonth() + 1 - Number(m[2]);
  if (today.getDate() < Number(m[3])) months--;
  months = Math.max(0, months);
  return months + (months === 1 ? ' mês' : ' meses');
}
/** aaaa-mm-dd → dd/mm/aaaa (vazio se não for data). */
export const brDate = (iso: string | null | undefined) => (/^\d{4}-\d{2}-\d{2}/.test(iso || '') ? iso!.slice(0, 10).split('-').reverse().join('/') : '');
