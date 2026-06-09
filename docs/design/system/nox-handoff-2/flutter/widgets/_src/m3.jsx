// ─────────────────────────────────────────────────────────────
// NOX · M3 component primitives + phone frame
// Every component takes a theme `t` (LIGHT or DARK ColorScheme).
// Icons use the Material Symbols Rounded webfont (authoritative set per §8).
// ─────────────────────────────────────────────────────────────

// Material Symbols Rounded glyph
const Icon = ({ name, size = 24, color = 'inherit', fill = 0, weight = 400, style }) => (
  <span className="msr" style={{
    fontSize: size, color, lineHeight: 1, userSelect: 'none',
    fontVariationSettings: `'FILL' ${fill}, 'wght' ${weight}, 'GRAD' 0, 'opsz' 24`,
    display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
    width: size, height: size, ...style,
  }}>{name}</span>
);

// Status bar — tinted to theme onSurface (or override)
const StatusBar = ({ color, bg }) => (
  <div style={{
    height: 36, flexShrink: 0, display: 'flex', alignItems: 'center',
    justifyContent: 'space-between', padding: '0 20px 0 24px',
    background: bg || 'transparent', fontFamily: SANS,
  }}>
    <span style={{ fontSize: 14, fontWeight: 500, letterSpacing: 0.2, color }}>9:30</span>
    <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
      {/* signal */}
      <svg width="17" height="13" viewBox="0 0 17 13"><path d="M8.5 12.5L.8 4.4a11 11 0 0115.4 0L8.5 12.5z" fill={color}/></svg>
      {/* wifi */}
      <svg width="16" height="13" viewBox="0 0 16 13"><path d="M15.3 12.8V.5L1 12.8h14.3z" fill={color}/></svg>
      {/* battery */}
      <svg width="24" height="13" viewBox="0 0 24 13">
        <rect x="1" y="1.5" width="19" height="10" rx="2.5" fill="none" stroke={color} strokeWidth="1.2" opacity="0.55"/>
        <rect x="2.6" y="3" width="13" height="7" rx="1.2" fill={color}/>
        <rect x="21" y="4.3" width="1.6" height="4.4" rx="0.8" fill={color} opacity="0.55"/>
      </svg>
    </div>
  </div>
);

const GestureNav = ({ color }) => (
  <div style={{ height: 24, flexShrink: 0, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
    <div style={{ width: 120, height: 4, borderRadius: 2, background: color, opacity: 0.85 }} />
  </div>
);

// Phone frame. interior = 393 × 852 (status bar + content + gesture nav).
// surface: screen background (defaults to t.surface). statusColor / navColor override.
const Phone = ({ t, surface, statusColor, navColor, children, noNav = false, bezel = true }) => {
  const bg = surface || t.surface;
  const sc = statusColor || t.onSurface;
  return (
    <div style={{
      width: 393 + (bezel ? 16 : 0), height: 852 + (bezel ? 16 : 0),
      borderRadius: bezel ? 44 : 0, overflow: 'hidden',
      background: '#0a0a0a',
      padding: bezel ? 8 : 0, boxSizing: 'border-box',
      boxShadow: bezel ? '0 24px 70px -16px rgba(0,0,0,0.55)' : 'none',
    }}>
      <div style={{
        width: 393, height: 852, borderRadius: bezel ? 36 : 0, overflow: 'hidden',
        background: bg, display: 'flex', flexDirection: 'column', position: 'relative',
        fontFamily: SANS,
      }}>
        <StatusBar color={sc} />
        <div style={{ flex: 1, minHeight: 0, display: 'flex', flexDirection: 'column', position: 'relative' }}>
          {children}
        </div>
        {!noNav && <GestureNav color={navColor || t.onSurface} />}
      </div>
    </div>
  );
};

// M3 small top app bar. leading: 'back' | null. actions: array of icon names. wordmark renders NOX.
const AppBar = ({ t, title, wordmark = false, leading = null, actions = [], onColor, splash = true }) => {
  const fg = onColor || t.onSurface;
  return (
    <div style={{ flexShrink: 0, background: t.surface, paddingBottom: splash ? 14 : 0 }}>
    <div style={{
      height: 64, display: 'flex', alignItems: 'center',
      padding: '0 4px', background: t.surface,
    }}>
      <div style={{ width: 48, height: 48, display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
        {leading === 'back' && <Icon name="arrow_back" size={24} color={fg} />}
      </div>
      <div style={{ flex: 1, minWidth: 0 }}>
        {wordmark ? (
          <span style={{ fontFamily: SANS, fontSize: 22, fontWeight: 700, letterSpacing: '0.12em', color: fg }}>NOX</span>
        ) : title ? (
          <span style={{ ...ty('titleLarge'), color: fg, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', display: 'block' }}>{title}</span>
        ) : null}
      </div>
      {actions.map((a, i) => (
        <div key={i} style={{ width: 48, height: 48, display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
          <Icon name={a} size={24} color={t.onSurfaceVariant} />
        </div>
      ))}
    </div>
    {/* brand-splash hairline — the C direction's signature */}
    {splash && <div style={{ height: 3, margin: '0 16px', borderRadius: 2, background: `linear-gradient(90deg, ${BRAND.teal}, ${BRAND.lime}, ${BRAND.gold}, ${BRAND.coral}, ${BRAND.red})` }} />}
    </div>
  );
};

// FilledButton (primary). disabled → onSurface @12% bg / @38% text. loading → spinner.
const FilledButton = ({ t, label, full = false, disabled = false, loading = false, icon }) => {
  const bg = disabled ? hexA(t.onSurface, 0.12) : t.primary;
  const fg = disabled ? hexA(t.onSurface, 0.38) : t.onPrimary;
  return (
    <div style={{
      height: 40, borderRadius: SHAPE.full, background: bg,
      display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8,
      padding: '0 24px', width: full ? '100%' : 'auto', boxSizing: 'border-box',
      cursor: disabled ? 'default' : 'pointer',
    }}>
      {loading
        ? <Spinner size={18} color={t.onPrimary} />
        : <>
            {icon && <Icon name={icon} size={18} color={fg} />}
            <span style={{ ...ty('labelLarge'), color: fg }}>{label}</span>
          </>}
    </div>
  );
};

// TextButton (secondary)
const TextButton = ({ t, label, color, icon, disabled = false }) => {
  const fg = disabled ? hexA(t.onSurface, 0.38) : (color || t.primary);
  return (
    <div style={{
      height: 40, borderRadius: SHAPE.full, padding: '0 12px',
      display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 8,
      cursor: disabled ? 'default' : 'pointer',
    }}>
      {icon && <Icon name={icon} size={18} color={fg} />}
      <span style={{ ...ty('labelLarge'), color: fg }}>{label}</span>
    </div>
  );
};

const IconButton = ({ t, name, color, size = 24 }) => (
  <div style={{ width: 48, height: 48, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
    <Icon name={name} size={size} color={color || t.onSurfaceVariant} />
  </div>
);

// Outlined TextField. states via props: focused, error, value, label floats when value/focused.
const TextField = ({
  t, label, value, placeholder, helper, error, counter, suffix, leading,
  focused = false, multiline = false, mono = false, minHeight,
}) => {
  const borderColor = error ? t.error : (focused ? t.primary : t.outline);
  const borderW = (focused || error) ? 2 : 1;
  const labelColor = error ? t.error : (focused ? t.primary : t.onSurfaceVariant);
  const float = focused || (value != null && value !== '');
  // M3: placeholder appears only once the label has floated (focus/value), never under a resting label
  const showPlaceholder = float && (value == null || value === '') && placeholder;
  return (
    <div>
      <div style={{
        position: 'relative', borderRadius: SHAPE.xs,
        border: `${borderW}px solid ${borderColor}`,
        minHeight: minHeight || (multiline ? 120 : 56),
        display: 'flex', alignItems: multiline ? 'flex-start' : 'center',
        padding: multiline ? '16px' : '0 16px', boxSizing: 'border-box',
        background: 'transparent',
      }}>
        {/* floating label */}
        {label && (
          <span style={{
            position: 'absolute', left: float ? 12 : 16,
            top: float ? -8 : (multiline ? 16 : '50%'),
            transform: float ? 'none' : (multiline ? 'none' : 'translateY(-50%)'),
            background: t.surface, padding: float ? '0 4px' : 0,
            ...(float ? ty('bodyMedium') : ty('bodyLarge')),
            fontSize: float ? 12 : 16,
            color: labelColor, pointerEvents: 'none', transition: 'all .15s', whiteSpace: 'nowrap',
          }}>{label}</span>
        )}
        <div style={{ flex: 1, minWidth: 0, paddingTop: multiline ? 0 : 0 }}>
          {value != null && value !== '' ? (
            <span style={{ ...(mono ? { fontFamily: MONO, fontSize: 16, lineHeight: '24px' } : ty('bodyLarge')), color: t.onSurface, wordBreak: mono ? 'break-all' : 'normal' }}>{value}</span>
          ) : showPlaceholder ? (
            <span style={{ ...ty('bodyLarge'), color: t.onSurfaceVariant }}>{placeholder}</span>
          ) : null}
          {focused && <span style={{ display: 'inline-block', width: 2, height: 20, background: t.primary, verticalAlign: 'middle', marginLeft: 1, animation: 'noxCaret 1s steps(1) infinite' }} />}
        </div>
        {suffix && <div style={{ marginLeft: 8, flexShrink: 0, alignSelf: multiline ? 'flex-start' : 'center' }}>{suffix}</div>}
      </div>
      {(helper || error || counter) && (
        <div style={{ display: 'flex', justifyContent: 'space-between', padding: '4px 16px 0', gap: 12 }}>
          <span style={{ ...ty('bodyMedium'), color: error ? t.error : t.onSurfaceVariant }}>{error || helper || ''}</span>
          {counter && <span style={{ ...ty('bodyMedium'), color: t.onSurfaceVariant, flexShrink: 0 }}>{counter}</span>}
        </div>
      )}
    </div>
  );
};

// Indeterminate circular progress
const Spinner = ({ size = 24, color = '#000', width = 3 }) => (
  <div style={{
    width: size, height: size, borderRadius: '50%',
    border: `${width}px solid ${hexA(color, 0.25)}`,
    borderTopColor: color, animation: 'noxSpin 0.9s linear infinite',
  }} />
);

// Generated chat avatar
const Avatar = ({ name, size = 40 }) => {
  const pal = avatarFor(name);
  const ini = initialsFor(name);
  return (
    <div style={{
      width: size, height: size, borderRadius: '50%', background: pal.bg,
      display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0,
    }}>
      {ini
        ? <span style={{ fontFamily: SANS, fontWeight: 500, fontSize: size * 0.4, color: '#FFFFFF' }}>{ini}</span>
        : <Icon name="forum" size={size * 0.5} color="#FFFFFF" fill={1} />}
    </div>
  );
};

// hex + alpha → rgba
function hexA(hex, a) {
  const h = hex.replace('#', '');
  const r = parseInt(h.substring(0, 2), 16);
  const g = parseInt(h.substring(2, 4), 16);
  const b = parseInt(h.substring(4, 6), 16);
  return `rgba(${r},${g},${b},${a})`;
}

Object.assign(window, {
  Icon, StatusBar, GestureNav, Phone, AppBar,
  FilledButton, TextButton, IconButton, TextField, Spinner, Avatar, hexA,
});
