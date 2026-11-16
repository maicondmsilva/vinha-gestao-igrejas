// Contribua no app: cartões de contribuição (painel e app do membro).

export type GivingCard = {id: string; purpose: string; title: string; subtitle: string; image: string; color: string; amounts: number[]};
export type GivingAdminCard = {
  id: string;
  title: string;
  subtitle: string;
  image: string;
  color: string;
  amounts: number[];
  position: number;
  active: boolean;
  version: number;
  category: string;
  ready: boolean;
};
export type GivingAdminPage = {
  primary: {provider: string; methods: string[]; holder: string} | null;
  cards: GivingAdminCard[];
  categories: {id: string; name: string}[];
};

/** Paleta Vinha para os cartões (o administrador também escolhe qualquer cor). */
export const givingPresets = ['#285c45', '#1b4a3b', '#7a5c1e', '#b8741a', '#5b3a6e', '#1f4e79', '#8c2f39', '#2f6b6b'];

/** Sugestões para começar (a igreja edita tudo depois). */
export const givingSuggestions: {title: string; subtitle: string; color: string}[] = [
  {title: 'Dízimo', subtitle: 'Fidelidade que sustenta a obra', color: '#285c45'},
  {title: 'Oferta', subtitle: 'Gratidão em cada culto', color: '#b8741a'},
  {title: 'Missões', subtitle: 'Levando o Evangelho além', color: '#1f4e79'},
  {title: 'Ação social', subtitle: 'Cuidar de quem precisa', color: '#8c2f39'},
];

/** "20, 50, 100" → [2000, 5000, 10000] (centavos); "12,50" é decimal. null se inválido. */
export function givingAmountsFromText(text: string): number[] | null {
  const parts = text
    .split(/;|,\s+|\s+/)
    .map((x) => x.trim())
    .filter(Boolean);
  if (parts.length > 6) return null;
  const out: number[] = [];
  for (const p of parts) {
    const n = Number(p.replace(/\./g, '').replace(',', '.'));
    if (!Number.isFinite(n) || n < 1 || n > 100000) return null;
    out.push(Math.round(n * 100));
  }
  return [...new Set(out)].sort((a, b) => a - b);
}
export const givingAmountsText = (cents: number[]) => cents.map((c) => (c % 100 ? (c / 100).toFixed(2).replace('.', ',') : String(c / 100))).join(', ');
/** R$ 50 · R$ 12,50 */
export const givingMoney = (cents: number) => 'R$ ' + (cents % 100 ? (cents / 100).toFixed(2).replace('.', ',') : String(cents / 100));
/** Cor do texto sobre o cartão (branco ou escuro), pela luminância. */
export function givingInk(hex: string) {
  const m = /^#?([0-9a-f]{6})$/i.exec(hex);
  if (!m) return '#ffffff';
  const n = parseInt(m[1]!, 16),
    l = (0.299 * ((n >> 16) & 255) + 0.587 * ((n >> 8) & 255) + 0.114 * (n & 255)) / 255;
  return l > 0.62 ? '#14211b' : '#ffffff';
}
