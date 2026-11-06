import {z} from 'zod';

// Ids come from Postgres (gen_random_uuid or md5-derived in tests), so accept any hex UUID layout, not only RFC 4122 versions.
export const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export const uuidText = z.string().regex(uuidPattern, 'Identificador inválido.');

const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
export const emailText = (label = 'E-mail') =>
  z.string().max(254, `${label}: use até 254 caracteres.`).regex(emailPattern, `${label}: informe um e-mail válido.`);

/** CPF check digits (accepts with or without punctuation). */
export function cpfValid(value: string) {
  const d = value.replace(/\D/g, '');
  if (d.length !== 11 || /^(\d)\1{10}$/.test(d)) return false;
  const digit = (n: number) => {
    let s = 0;
    for (let i = 0; i < n; i++) s += Number(d[i]) * (n + 1 - i);
    const r = (s * 10) % 11;
    return r === 10 ? 0 : r;
  };
  return digit(9) === Number(d[9]) && digit(10) === Number(d[10]);
}

/** Brazilian phone with area code: 10 or 11 digits, optional +55. */
export const phoneValid = (value: string) => /^(55)?\d{10,11}$/.test(value.replace(/\D/g, ''));
