// ─────────────────────────────────────────────────────────────
// NOX · Chats-flow shared parts (4.1 / 5.x / 6.1)
// ─────────────────────────────────────────────────────────────

// file-type → Material Symbol (overview / Файлы)
function fileIcon(type) {
  return ({
    image: 'image', video: 'videocam', audio: 'audiotrack', pdf: 'picture_as_pdf',
    doc: 'description', sheet: 'table_chart', text: 'article', archive: 'folder_zip',
  })[type] || 'insert_drive_file';
}

// file-type → decorative brand color (used in 5.3 / 5.4 file cells)
function fileColor(type) {
  return ({
    image: BRAND.blue, video: BRAND.coral, audio: BRAND.amber, pdf: BRAND.red,
    doc: BRAND.tealDeep, sheet: BRAND.lime, text: BRAND.teal, archive: BRAND.gold,
  })[type] || BRAND.tealDeep;
}

// type icon inside a soft tinted rounded container (5.4 list, 5.3)
const FileGlyph = ({ type, size = 24, box = 44 }) => {
  const col = fileColor(type);
  return (
    <div style={{ width: box, height: box, borderRadius: box * 0.27, background: hexA(col, 0.14), display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
      <Icon name={fileIcon(type)} size={size} color={col} />
    </div>
  );
};

// Bottom bar with circular notch + docked FAB (4.1 §9.1)
// Bar is a real SVG shape with a circular notch; the FAB cradles into it.
const BottomBar = ({ t, active = 'chats' }) => {
  const W = 393, H = 64, cx = W / 2, R = 36; // notch radius = FAB radius (28) + 8 margin
  const notch = `M0,16 Q0,0 16,0 H${cx - R} A ${R} ${R} 0 0 1 ${cx + R},0 H${W - 16} Q${W},0 ${W},16 V${H} H0 Z`;
  const tab = (icon, label, key) => {
    const sel = active === key;
    return (
      <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 3 }}>
        <Icon name={icon} size={24} color={sel ? t.primary : t.onSurfaceVariant} fill={sel ? 1 : 0} />
        <span style={{ ...ty('labelMedium'), color: sel ? t.primary : t.onSurfaceVariant }}>{label}</span>
      </div>
    );
  };
  return (
    <div style={{ position: 'relative', flexShrink: 0, height: H, overflow: 'visible' }}>
      <svg width={W} height={H} viewBox={`0 0 ${W} ${H}`} style={{ position: 'absolute', bottom: 0, left: 0, display: 'block', filter: t.dark ? 'none' : 'drop-shadow(0 -1px 3px rgba(0,0,0,0.12))' }}>
        <path d={notch} fill={t.surfaceContainer} />
      </svg>
      <div style={{ position: 'absolute', bottom: 0, left: 0, width: W, height: H, display: 'flex', alignItems: 'center' }}>
        <div style={{ flex: 1, display: 'flex', justifyContent: 'center' }}>{tab('forum', 'Chats', 'chats')}</div>
        <div style={{ width: R * 2 }} />
        <div style={{ flex: 1, display: 'flex', justifyContent: 'center' }}>{tab('settings', 'Settings', 'settings')}</div>
      </div>
      {/* docked FAB, cradled in the notch */}
      <div style={{ position: 'absolute', left: cx - 28, top: -28, width: 56, height: 56, borderRadius: '50%', background: t.primaryContainer, display: 'flex', alignItems: 'center', justifyContent: 'center', boxShadow: elev(3, t.dark) }}>
        <Icon name="add" size={26} color={t.onPrimaryContainer} />
      </div>
    </div>
  );
};

// M3 SearchBar (persistent) — brand-teal search icon (C direction)
const SearchBar = ({ t, value, placeholder = 'Search' }) => (
  <div style={{ margin: '0 16px 8px', height: 56, borderRadius: SHAPE.full, background: t.surfaceContainerHigh, boxShadow: elev(2, t.dark), display: 'flex', alignItems: 'center', gap: 12, padding: '0 16px' }}>
    <Icon name="search" size={24} color={BRAND.teal} />
    {value
      ? <span style={{ ...ty('bodyLarge'), color: t.onSurface }}>{value}</span>
      : <span style={{ ...ty('bodyLarge'), color: t.onSurfaceVariant }}>{placeholder}</span>}
  </div>
);

// M3 expanded Search View — opened from a search icon in the app bar.
// Full-width field with leading back, typed query + caret, trailing clear; results below.
const SearchView = ({ t, query, results = [], empty = false }) => (
  <>
    <div style={{ height: 64, flexShrink: 0, display: 'flex', alignItems: 'center', gap: 4, padding: '0 4px', background: t.surface }}>
      <div style={{ width: 48, height: 48, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
        <Icon name="arrow_back" size={24} color={t.onSurfaceVariant} />
      </div>
      <div style={{ flex: 1, minWidth: 0, display: 'flex', alignItems: 'center' }}>
        {query
          ? <span style={{ ...ty('bodyLarge'), color: t.onSurface }}>{query}</span>
          : <span style={{ ...ty('bodyLarge'), color: t.onSurfaceVariant }}>Search</span>}
        <span style={{ display: 'inline-block', width: 2, height: 22, background: t.primary, marginLeft: 1, animation: 'noxCaret 1s steps(1) infinite' }} />
      </div>
      {query && (
        <div style={{ width: 48, height: 48, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <Icon name="close" size={22} color={t.onSurfaceVariant} />
        </div>
      )}
    </div>
    <div style={{ height: 1, background: t.outlineVariant, flexShrink: 0 }} />
    <div style={{ flex: 1, minHeight: 0, overflow: 'hidden' }}>
      {empty
        ? <div style={{ paddingTop: 48, textAlign: 'center' }}><span style={{ ...ty('bodyMedium'), color: t.onSurfaceVariant }}>No chats found</span></div>
        : results.map((c, i) => <ChatListItem key={i} t={t} {...c} />)}
    </div>
  </>
);

// MaterialBanner (persistent / offline / inline-error) — top
const MaterialBanner = ({ t, text, action, icon = 'wifi_off' }) => (
  <div style={{ background: t.surfaceContainer, boxShadow: elev(3, t.dark), padding: '12px 16px', display: 'flex', alignItems: 'center', gap: 12, flexShrink: 0 }}>
    <Icon name={icon} size={22} color={t.onSurfaceVariant} />
    <span style={{ ...ty('bodyMedium'), color: t.onSurface, flex: 1 }}>{text}</span>
    {action && <span style={{ ...ty('labelLarge'), color: t.primary }}>{action}</span>}
  </div>
);

// Snackbar (transient feedback) — §9.11. neutral = inverseSurface; error = errorContainer.
// Sits above the bottom bar / FAB; single optional action.
const Snackbar = ({ t, text, action, error = false }) => {
  const bg = error ? t.errorContainer : t.inverseSurface;
  const fg = error ? t.onErrorContainer : t.onInverseSurface;
  const act = error ? t.onErrorContainer : t.inversePrimary;
  return (
    <div style={{ background: bg, color: fg, borderRadius: SHAPE.xs, boxShadow: elev(3, t.dark), padding: '6px 8px 6px 16px', display: 'flex', alignItems: 'center', gap: 8, minHeight: 48, boxSizing: 'border-box' }}>
      <span style={{ ...ty('bodyMedium'), color: fg, flex: 1 }}>{text}</span>
      {action && <span style={{ ...ty('labelLarge'), color: act, padding: '8px 12px', whiteSpace: 'nowrap' }}>{action}</span>}
    </div>
  );
};

// Chat list item (5.1 §9.3) — C direction: avatar ring + unread emphasis
const ChatListItem = ({ t, name, preview, time, unread }) => (
  <div style={{ display: 'flex', alignItems: 'center', gap: 16, padding: '12px 16px', minHeight: 72, boxSizing: 'border-box' }}>
    <div style={{ borderRadius: '50%', boxShadow: `0 0 0 2px ${hexA(t.onSurface, 0.06)}` }}>
      <Avatar name={name} size={40} />
    </div>
    <div style={{ flex: 1, minWidth: 0 }}>
      <div style={{ ...ty('titleMedium'), color: t.onSurface, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', fontWeight: unread > 0 ? 600 : 500 }}>{name}</div>
      <div style={{ ...ty('bodyMedium'), color: unread > 0 ? t.onSurface : t.onSurfaceVariant, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{preview}</div>
    </div>
    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-end', gap: 6, flexShrink: 0, minWidth: 44 }}>
      <span style={{ ...ty('labelSmall'), color: unread > 0 ? t.primary : t.onSurfaceVariant, whiteSpace: 'nowrap' }}>{time}</span>
      {unread > 0 && (
        <span style={{ minWidth: 20, height: 20, borderRadius: SHAPE.full, background: t.primary, color: t.onPrimary, ...ty('labelSmall'), display: 'flex', alignItems: 'center', justifyContent: 'center', padding: '0 6px', boxSizing: 'border-box' }}>
          {unread > 99 ? '99+' : unread}
        </span>
      )}
    </div>
  </div>
);

// Empty state (illustration placeholder + title + message)
const EmptyState = ({ t, glyph, title, message }) => (
  <div style={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', textAlign: 'center', padding: '0 40px', gap: 14 }}>
    {/* illustration placeholder: thin outline + brand accents, per §10 */}
    <div style={{ width: 132, height: 132, borderRadius: 20, border: `1.5px solid ${t.outlineVariant}`, position: 'relative', display: 'flex', alignItems: 'center', justifyContent: 'center', overflow: 'hidden' }}>
      <Icon name={glyph} size={56} color={t.onSurfaceVariant} />
      <div style={{ position: 'absolute', top: 18, right: 20, width: 14, height: 14, borderRadius: '50%', background: BRAND.teal }} />
      <div style={{ position: 'absolute', bottom: 22, left: 22, width: 10, height: 10, borderRadius: '50%', background: BRAND.gold }} />
    </div>
    <div style={{ ...ty('headlineSmall'), color: t.onSurface }}>{title}</div>
    <div style={{ ...ty('bodyMedium'), color: t.onSurfaceVariant, maxWidth: 260 }}>{message}</div>
  </div>
);

// File-chip (§9.7). inBubble → tint derived from onColor (bubble text color).
const FileChip = ({ t, type, name, size, mine = false, inBubble = false, removable = false, onColor }) => {
  const oc = onColor || t.onPrimaryContainer;
  const bg = inBubble ? hexA(oc, 0.12) : t.surfaceContainerHighest;
  const fg = inBubble ? oc : t.onSurface;
  const sub = inBubble ? hexA(oc, 0.7) : t.onSurfaceVariant;
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 12, background: bg, borderRadius: SHAPE.xs, padding: '10px 12px', minWidth: 200, maxWidth: 260 }}>
      <Icon name={fileIcon(type)} size={28} color={sub} />
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ ...ty('titleMedium'), color: fg, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{name}</div>
        <div style={{ ...ty('bodyMedium'), color: sub }}>{size}</div>
      </div>
      {removable && (
        <div style={{ width: 32, height: 32, display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
          <Icon name="close" size={20} color={t.onSurfaceVariant} />
        </div>
      )}
    </div>
  );
};

// Date separator (5.2)
const DateSep = ({ t, label }) => (
  <div style={{ display: 'flex', justifyContent: 'center', margin: '12px 0' }}>
    <span style={{ ...ty('labelMedium'), color: t.onSurfaceVariant, background: t.surfaceContainer, borderRadius: SHAPE.full, padding: '4px 12px' }}>{label}</span>
  </div>
);

// system event line (5.2)
const SystemLine = ({ t, text }) => (
  <div style={{ display: 'flex', justifyContent: 'center', margin: '8px 0' }}>
    <span style={{ ...ty('bodyMedium'), color: t.onSurfaceVariant, textAlign: 'center', maxWidth: 280 }}>{text}</span>
  </div>
);

const AuthorHeader = ({ t, name }) => (
  <div style={{ ...ty('titleMedium'), color: t.onSurfaceVariant, margin: '0 0 2px 4px' }}>{name}</div>
);

// own-bubble color presets (explored directions)
function bubblePreset(t, key) {
  switch (key) {
    case 'neutral': return { bg: t.surfaceContainerHighest, fg: t.onSurface, meta: t.onSurfaceVariant };
    case 'warm':    return { bg: t.tertiaryContainer, fg: t.onTertiaryContainer, meta: hexA(t.onTertiaryContainer, 0.7) };
    case 'bold':    return { bg: t.primary, fg: t.onPrimary, meta: hexA(t.onPrimary, 0.7) };
    default:        return { bg: t.primaryContainer, fg: t.onPrimaryContainer, meta: hexA(t.onPrimaryContainer, 0.7) };
  }
}

// Message bubble (5.2 §9.2). children for file chips. status for own.
const MsgBubble = ({ t, mine, text, time, status, file, last, ownPreset }) => {
  const own = ownPreset || bubblePreset(t, 'current');
  const bg = mine ? own.bg : t.surfaceContainerHigh;
  const fg = mine ? own.fg : t.onSurface;
  const meta = mine ? own.meta : t.onSurfaceVariant;
  const statusColor = status === 'error' ? t.error : meta;
  return (
    <div style={{ display: 'flex', justifyContent: mine ? 'flex-end' : 'flex-start', marginBottom: last ? 0 : 2 }}>
      <div style={{
        maxWidth: '80%', background: bg, color: fg,
        borderRadius: SHAPE.l,
        borderBottomRightRadius: mine ? SHAPE.xs : SHAPE.l,
        borderBottomLeftRadius: mine ? SHAPE.l : SHAPE.xs,
        padding: file && !text ? 8 : '8px 12px',
      }}>
        {file && <div style={{ marginBottom: text ? 8 : 0 }}><FileChip t={t} {...file} mine={mine} inBubble onColor={fg} /></div>}
        {text && <div style={{ ...ty('bodyLarge') }}>{text}</div>}
        <div style={{ display: 'flex', alignItems: 'center', gap: 4, justifyContent: 'flex-end', marginTop: 2 }}>
          <span style={{ ...ty('labelSmall'), color: meta }}>{time}</span>
          {mine && status && <Icon name={status === 'pending' ? 'schedule' : status === 'sent' ? 'check' : 'error_outline'} size={14} color={statusColor} />}
        </div>
      </div>
    </div>
  );
};

// Composer (5.2 §9.8)
const Composer = ({ t, value, attachment, sendActive }) => (
  <div style={{ flexShrink: 0, background: t.surfaceContainer, borderTop: `1px solid ${t.outlineVariant}` }}>
    {attachment && (
      <div style={{ padding: '8px 12px 0' }}>
        <FileChip t={t} {...attachment} removable />
      </div>
    )}
    <div style={{ display: 'flex', alignItems: 'flex-end', gap: 4, padding: '8px 8px' }}>
      <div style={{ width: 48, height: 48, display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
        <Icon name="attach_file" size={24} color={t.onSurfaceVariant} />
      </div>
      <div style={{ flex: 1, minHeight: 48, display: 'flex', alignItems: 'center', padding: '0 4px' }}>
        {value
          ? <span style={{ ...ty('bodyLarge'), color: t.onSurface }}>{value}</span>
          : <span style={{ ...ty('bodyLarge'), color: t.onSurfaceVariant }}>Message</span>}
      </div>
      <div style={{ width: 48, height: 48, display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
        <Icon name="send" size={24} color={sendActive ? t.primary : hexA(t.onSurface, 0.38)} fill={sendActive ? 1 : 0} />
      </div>
    </div>
  </div>
);

// SegmentedButton (single-select)
const Segmented = ({ t, options, value }) => (
  <div style={{ display: 'flex', borderRadius: SHAPE.full, overflow: 'hidden', border: `1px solid ${t.outline}`, width: 'fit-content' }}>
    {options.map((o, i) => {
      const sel = o === value;
      return (
        <div key={o} style={{ padding: '8px 16px', background: sel ? t.secondaryContainer : 'transparent', display: 'flex', alignItems: 'center', gap: 6, borderLeft: i ? `1px solid ${t.outline}` : 'none' }}>
          {sel && <Icon name="check" size={18} color={t.onSecondaryContainer} />}
          <span style={{ ...ty('labelLarge'), color: sel ? t.onSecondaryContainer : t.onSurface }}>{o}</span>
        </div>
      );
    })}
  </div>
);

Object.assign(window, {
  fileIcon, fileColor, FileGlyph, BottomBar, SearchBar, SearchView, MaterialBanner, ChatListItem, EmptyState,
  FileChip, DateSep, SystemLine, AuthorHeader, MsgBubble, bubblePreset, Composer, Segmented, Snackbar,
});
