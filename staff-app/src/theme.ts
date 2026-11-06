import {StyleSheet} from 'react-native';

// Vinha identity: deep vine green, warm gold accents, calm neutral surfaces.
export const colors = {
  brand: '#285c45',
  brandDark: '#183d2c',
  gold: '#c9a227',
  bg: '#f4f7f5',
  surface: '#ffffff',
  line: '#dce6df',
  text: '#183d2c',
  muted: '#5f6f64',
  ok: '#1f7a4d',
  warn: '#b26a00',
  danger: '#b42318',
};

export const ui = StyleSheet.create({
  screen: {flex: 1, backgroundColor: colors.bg},
  pad: {padding: 20, gap: 14},
  over: {fontSize: 12, letterSpacing: 1.2, color: colors.muted, fontWeight: '700'},
  h1: {fontSize: 26, fontWeight: '800', color: colors.text},
  h2: {fontSize: 18, fontWeight: '700', color: colors.text},
  copy: {fontSize: 15, lineHeight: 21, color: colors.muted},
  card: {backgroundColor: colors.surface, borderColor: colors.line, borderWidth: 1, borderRadius: 18, padding: 18, gap: 8},
  input: {backgroundColor: colors.surface, borderColor: colors.line, borderWidth: 1, borderRadius: 12, minHeight: 50, paddingHorizontal: 14, fontSize: 16, color: colors.text},
  label: {fontSize: 14, fontWeight: '600', color: colors.text},
  primary: {backgroundColor: colors.brand, borderRadius: 12, minHeight: 52, alignItems: 'center', justifyContent: 'center', paddingHorizontal: 20},
  primaryText: {color: '#fff', fontWeight: '700', fontSize: 16},
  ghost: {borderColor: colors.line, borderWidth: 1, borderRadius: 12, minHeight: 48, alignItems: 'center', justifyContent: 'center', paddingHorizontal: 16, backgroundColor: colors.surface},
  ghostText: {color: colors.text, fontWeight: '600', fontSize: 15},
  error: {color: colors.danger, fontSize: 14},
  chip: {borderColor: colors.line, borderWidth: 1, borderRadius: 999, paddingVertical: 8, paddingHorizontal: 14, backgroundColor: colors.surface},
  chipOn: {backgroundColor: colors.brand, borderColor: colors.brand},
});
