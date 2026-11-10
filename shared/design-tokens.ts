// Vinha identity, in one place for the panel (Tailwind theme in app/vinha-tokens.css) and the apps (React Native styles).
// Ministry apps keep each ministry's own primary color; these tokens are the Vinha brand used by the panel and Vinha Equipe.
// After changing a value run `node --experimental-strip-types scripts/build-tokens.mjs` — the CI fails if the CSS is out of date.

export const vinhaColors = {
  brand: '#285c45', // vine green: primary actions, active navigation
  brandDark: '#163d2f', // sidebar, headings on light backgrounds
  brandSoft: '#e5eee8', // selected rows, soft badges
  gold: '#dbbb70', // warm accent: highlights, avatars
  goldDeep: '#7f6420', // gold text on light backgrounds (AA contrast)
  bg: '#f5f6f2', // page background
  surface: '#ffffff',
  line: '#dce6df',
  ink: '#1f2a22', // body text
  muted: '#5f6f64', // secondary text (AA on bg and surface)
  ok: '#1f7a4d',
  warn: '#9a5b00',
  danger: '#b42318',
  onBrand: '#ffffff',
} as const;

export const vinhaRadius = {sm: 8, md: 12, lg: 18, pill: 999} as const;
export const vinhaSpace = {xs: 4, sm: 8, md: 14, lg: 20, xl: 28} as const;
export const vinhaType = {
  over: {size: 12, weight: '700', tracking: 1.2},
  h1: {size: 26, weight: '800'},
  h2: {size: 18, weight: '700'},
  body: {size: 15, lineHeight: 21, weight: '400'},
  label: {size: 14, weight: '600'},
} as const;
/** Minimum touch target on phones and kiosk tablets. */
export const vinhaTouch = 48;

export type VinhaColor = keyof typeof vinhaColors;
const kebab = (s: string) => s.replace(/[A-Z]/g, (c) => '-' + c.toLowerCase());

/** Tailwind v4 theme block generated from the tokens (`bg-vinha-brand`, `rounded-vinha-md`, …). */
export function tokensCss() {
  const lines = [
    '/* Gerado por scripts/build-tokens.mjs a partir de shared/design-tokens.ts. Não edite à mão. */',
    '@theme {',
    ...Object.entries(vinhaColors).map(([k, v]) => `  --color-vinha-${kebab(k)}: ${v};`),
    ...Object.entries(vinhaRadius).map(([k, v]) => `  --radius-vinha-${k}: ${v}px;`),
    '}',
    '',
  ];
  return lines.join('\n');
}

/** WCAG relative-luminance contrast ratio between two #rrggbb colors. */
export function contrast(a: string, b: string) {
  const lum = (hex: string) => {
    const [r, g, bl] = [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16) / 255).map((v) => (v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4));
    return 0.2126 * r + 0.7152 * g + 0.0722 * bl;
  };
  const [x, y] = [lum(a), lum(b)].sort((p, q) => q - p);
  return (x + 0.05) / (y + 0.05);
}
