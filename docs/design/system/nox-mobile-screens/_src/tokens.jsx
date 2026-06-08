// ─────────────────────────────────────────────────────────────
// NOX · Design tokens — straight from design-system.md
// M3 ColorScheme (light §2.2 / dark §2.3), brand §2.4, avatars §2.5,
// type scale §3, shape §4, elevation §5.
// ─────────────────────────────────────────────────────────────

// §2.2 Functional scheme — LIGHT
const LIGHT = {
  primary: '#006A6A', onPrimary: '#FFFFFF',
  primaryContainer: '#6FF7F6', onPrimaryContainer: '#002020',
  secondary: '#4A6363', onSecondary: '#FFFFFF',
  secondaryContainer: '#CCE8E7', onSecondaryContainer: '#051F1F',
  tertiary: '#6F5E00', onTertiary: '#FFFFFF',
  tertiaryContainer: '#FAE08A', onTertiaryContainer: '#221B00',
  error: '#BA1A1A', onError: '#FFFFFF',
  errorContainer: '#FFDAD6', onErrorContainer: '#410002',
  surface: '#F4FBFA', onSurface: '#161D1D',
  surfaceVariant: '#DAE5E3', onSurfaceVariant: '#3F4948',
  outline: '#6F7979', outlineVariant: '#BEC9C8',
  surfaceContainerLowest: '#FFFFFF',
  surfaceContainerLow: '#EFF5F4',
  surfaceContainer: '#E9EFEE',
  surfaceContainerHigh: '#E3EAE9',
  surfaceContainerHighest: '#DDE4E3',
  inverseSurface: '#2B3231', onInverseSurface: '#ECF2F1',
  inversePrimary: '#4CDADA',
  surfaceTint: '#006A6A', shadow: '#000000', scrim: '#000000',
  dark: false,
};

// §2.3 Functional scheme — DARK
const DARK = {
  primary: '#4CDADA', onPrimary: '#003737',
  primaryContainer: '#004F4F', onPrimaryContainer: '#6FF7F6',
  secondary: '#B0CCCB', onSecondary: '#1B3534',
  secondaryContainer: '#324B4A', onSecondaryContainer: '#CCE8E7',
  tertiary: '#DEC56B', onTertiary: '#3A2F00',
  tertiaryContainer: '#534619', onTertiaryContainer: '#FAE08A',
  error: '#FFB4AB', onError: '#690005',
  errorContainer: '#93000A', onErrorContainer: '#FFDAD6',
  surface: '#0E1514', onSurface: '#DDE4E3',
  surfaceVariant: '#3F4948', onSurfaceVariant: '#BEC9C8',
  outline: '#899393', outlineVariant: '#4E5B58',
  surfaceContainerLowest: '#0C1312',
  surfaceContainerLow: '#1C2423',
  surfaceContainer: '#222A28',
  surfaceContainerHigh: '#2C3431',
  surfaceContainerHighest: '#37403C',
  inverseSurface: '#DDE4E3', onInverseSurface: '#2B3231',
  inversePrimary: '#006A6A',
  surfaceTint: '#4CDADA', shadow: '#000000', scrim: '#000000',
  dark: true, outlined: true,
};

// §2.4 Brand palette (logo / splash / decorative only)
const BRAND = {
  teal: '#12B4B4', tealDeep: '#0E7C7C',
  gold: '#F4C20C', amber: '#FBB00C', coral: '#FB7A12',
  red: '#E11D1D', lime: '#8FA50C', blue: '#2E6FB0',
  white: '#FAFAFA', canvasDark: '#0C2424', ink: '#0C0C0C',
  qrSurface: '#FFFFFF', qrInk: '#0C0C0C',
};

// §2.5 Generated-avatar palette (contrast-tuned, white initials)
const AVATARS = [
  { bg: '#0E7C7C', hue: 'teal' },
  { bg: '#8A6A00', hue: 'gold-deep' },
  { bg: '#AD4A15', hue: 'coral-deep' },
  { bg: '#5C7300', hue: 'lime-deep' },
  { bg: '#2E6FB0', hue: 'blue' },
  { bg: '#C0392B', hue: 'red' },
  { bg: '#7A4DB3', hue: 'violet' },
  { bg: '#1E7268', hue: 'green' },
];
// deterministic hash → palette index
function avatarFor(name) {
  let h = 0;
  for (let i = 0; i < (name || '').length; i++) h = (h * 31 + name.charCodeAt(i)) >>> 0;
  return AVATARS[h % 8];
}
function initialsFor(name) {
  if (!name) return null;
  const words = name.trim().split(/\s+/).filter(Boolean);
  if (words.length >= 2) {
    const a = words[0][0], b = words[1][0];
    if (/[A-Za-z0-9]/.test(a) && /[A-Za-z0-9]/.test(b)) return (a + b).toUpperCase();
  }
  const m = (name.match(/[A-Za-z0-9]/g) || []).slice(0, 2);
  return m.length ? m.join('').toUpperCase() : null; // null → fallback glyph
}

// §3 Type scale (M3). Family: Roboto (sans), Roboto Mono (mono).
const SANS = "'Roboto', system-ui, sans-serif";
const MONO = "'Roboto Mono', ui-monospace, monospace";
const TYPE = {
  displaySmall:  { fontSize: 36, lineHeight: '44px', fontWeight: 400, letterSpacing: 0 },
  headlineSmall: { fontSize: 24, lineHeight: '32px', fontWeight: 400, letterSpacing: 0 },
  titleLarge:    { fontSize: 22, lineHeight: '28px', fontWeight: 400, letterSpacing: 0 },
  titleMedium:   { fontSize: 16, lineHeight: '24px', fontWeight: 500, letterSpacing: '0.15px' },
  bodyLarge:     { fontSize: 16, lineHeight: '24px', fontWeight: 400, letterSpacing: '0.5px' },
  bodyMedium:    { fontSize: 14, lineHeight: '20px', fontWeight: 400, letterSpacing: '0.25px' },
  labelLarge:    { fontSize: 14, lineHeight: '20px', fontWeight: 500, letterSpacing: '0.1px' },
  labelMedium:   { fontSize: 12, lineHeight: '16px', fontWeight: 500, letterSpacing: '0.5px' },
  labelSmall:    { fontSize: 11, lineHeight: '16px', fontWeight: 500, letterSpacing: '0.5px' },
};
const ty = (token, extra = {}) => ({ fontFamily: SANS, ...TYPE[token], ...extra });

// §4 Shape (corner radius)
const SHAPE = { none: 0, xs: 4, s: 8, m: 12, l: 16, xl: 28, full: 999 };

// §6 Spacing — 4dp base grid. Flutter: EdgeInsets / SizedBox / gap.
const SPACE = { 1: 4, 2: 8, 3: 12, 4: 16, 6: 24, 8: 32 };

// §7 Motion — M3 durations (ms) + easing. Flutter: Durations.* / Easing.* (Curves).
const EASING = {
  standard:             'cubic-bezier(0.2, 0, 0, 1)',
  emphasized:           'cubic-bezier(0.2, 0, 0, 1)',
  emphasizedDecelerate: 'cubic-bezier(0.05, 0.7, 0.1, 1)',
};
const MOTION = {
  splashIn:    { ms: 400, easing: 'emphasizedDecelerate', flutter: 'Easing.emphasizedDecelerate', use: 'Splash reveal' },
  push:        { ms: 300, easing: 'emphasized',           flutter: 'Easing.emphasized',           use: 'Screen push / pop' },
  tabFade:     { ms: 150, easing: 'standard',             flutter: 'Easing.standard',              use: 'Tab switch (IndexedStack fade)' },
  snackbarIn:  { ms: 150, easing: 'standard',             flutter: 'Easing.standard',              use: 'Snackbar in' },
  snackbarOut: { ms: 75,  easing: 'standard',             flutter: 'Easing.standard',              use: 'Snackbar out' },
  sheet:       { ms: 300, easing: 'emphasizedDecelerate', flutter: 'Easing.emphasizedDecelerate', use: 'Bottom sheet expand' },
};

// §5 Elevation — tonal; we approximate with soft shadows on light, none on dark.
const elev = (level, dark) => {
  if (dark || level === 0) return 'none';
  const map = {
    1: '0 1px 3px rgba(0,0,0,0.10), 0 1px 2px rgba(0,0,0,0.06)',
    2: '0 1px 5px rgba(0,0,0,0.12), 0 1px 2px rgba(0,0,0,0.07)',
    3: '0 4px 8px rgba(0,0,0,0.12), 0 1px 3px rgba(0,0,0,0.08)',
    5: '0 8px 24px rgba(0,0,0,0.16), 0 2px 6px rgba(0,0,0,0.10)',
  };
  return map[level] || 'none';
};

Object.assign(window, {
  LIGHT, DARK, BRAND, AVATARS, avatarFor, initialsFor,
  SANS, MONO, TYPE, ty, SHAPE, SPACE, MOTION, EASING, elev,
});
