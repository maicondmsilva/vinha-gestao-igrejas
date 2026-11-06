import {StyleSheet} from 'react-native';

import {vinhaColors as v, vinhaRadius as r, vinhaTouch} from '../../shared/design-tokens.ts';

// Vinha identity from shared/design-tokens.ts: the same green, gold and neutrals as the panel.
export const colors = {
  brand: v.brand,
  brandDark: v.brandDark,
  gold: v.gold,
  bg: v.bg,
  surface: v.surface,
  line: v.line,
  text: v.ink,
  muted: v.muted,
  ok: v.ok,
  warn: v.warn,
  danger: v.danger,
};

export const ui = StyleSheet.create({
  screen: {flex: 1, backgroundColor: colors.bg},
  pad: {padding: 20, gap: 14},
  over: {fontSize: 12, letterSpacing: 1.2, color: colors.muted, fontWeight: '700'},
  h1: {fontSize: 26, fontWeight: '800', color: colors.text},
  h2: {fontSize: 18, fontWeight: '700', color: colors.text},
  copy: {fontSize: 15, lineHeight: 21, color: colors.muted},
  card: {backgroundColor: colors.surface, borderColor: colors.line, borderWidth: 1, borderRadius: r.lg, padding: 18, gap: 8},
  input: {
    backgroundColor: colors.surface,
    borderColor: colors.line,
    borderWidth: 1,
    borderRadius: r.md,
    minHeight: 50,
    paddingHorizontal: 14,
    fontSize: 16,
    color: colors.text,
  },
  label: {fontSize: 14, fontWeight: '600', color: colors.text},
  primary: {backgroundColor: colors.brand, borderRadius: r.md, minHeight: 52, alignItems: 'center', justifyContent: 'center', paddingHorizontal: 20},
  primaryText: {color: v.onBrand, fontWeight: '700', fontSize: 16},
  ghost: {
    borderColor: colors.line,
    borderWidth: 1,
    borderRadius: r.md,
    minHeight: vinhaTouch,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 16,
    backgroundColor: colors.surface,
  },
  ghostText: {color: colors.text, fontWeight: '600', fontSize: 15},
  error: {color: colors.danger, fontSize: 14},
  fieldError: {color: colors.danger, fontSize: 13, fontWeight: '600'},
  inputInvalid: {borderColor: colors.danger},
  chip: {borderColor: colors.line, borderWidth: 1, borderRadius: r.pill, paddingVertical: 8, paddingHorizontal: 14, backgroundColor: colors.surface},
  chipOn: {backgroundColor: colors.brand, borderColor: colors.brand},
});
