// ─────────────────────────────────────────────────────────────
// NOX · Chats-flow screens (4.1 / 5.1 / 5.2 / 5.3 / 5.4 / 6.1)
// Verbatim EN microcopy from screen specs.
// ─────────────────────────────────────────────────────────────

const CHATS = [
  { name: 'Night Owls', preview: 'Anyone up for a late session?', time: '2 min', unread: 12 },
  { name: 'Aria', preview: 'On my way.', time: '14 min', unread: 3 },
  { name: 'Deep Work', preview: 'Shared focus.pdf', time: '1 h', unread: 0 },
  { name: 'Backstage', preview: 'see you there', time: '3 h', unread: 128 },
  { name: 'Red Room', preview: 'Let\u2019s keep it here.', time: 'Yesterday', unread: 0 },
  { name: 'Greenhouse', preview: 'watering-schedule.xlsx', time: '12 May', unread: 1 },
  { name: 'Velvet', preview: 'thanks!', time: '12 May', unread: 0 },
];

// ── 5.1 Chats list ───────────────────────────────────────────
// state: 'filled' | 'loading' | 'empty' | 'search' | 'search-empty' | 'offline' | 'inline-error'
// snack: optional { text, action, error } → transient Snackbar above the bottom bar
const ChatsListScreen = ({ t, state = 'filled', snack = null }) => {
  // search opens as a full search view (tapping the persistent SearchBar)
  if (state === 'search' || state === 'search-empty') {
    const empty = state === 'search-empty';
    return <SearchView t={t} query={empty ? 'xyz' : 'night'} empty={empty} results={CHATS.filter(c => c.name.toLowerCase().includes('night'))} />;
  }
  return (
    <>
      <AppBar t={t} wordmark />
      <SearchBar t={t} placeholder="Search" />
      {state === 'offline' && <MaterialBanner t={t} text="No connection" />}
      {state === 'inline-error' && <MaterialBanner t={t} icon="error_outline" text="Could not load chats. Pull to refresh." />}
      <div style={{ flex: 1, minHeight: 0, overflow: 'hidden', display: 'flex', flexDirection: 'column', position: 'relative' }}>
        {state === 'loading' ? (
          <div style={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center' }}><Spinner size={40} color={t.primary} /></div>
        ) : state === 'empty' ? (
          <EmptyState t={t} glyph="forum" title="No chats yet" message="Tap + to create the first one." />
        ) : (
          <div>
            {CHATS.map((c, i) => <ChatListItem key={i} t={t} {...c} />)}
          </div>
        )}
        {snack && (
          <div style={{ position: 'absolute', left: 16, right: 16, bottom: 88, zIndex: 5 }}>
            <Snackbar t={t} {...snack} />
          </div>
        )}
      </div>
      <BottomBar t={t} active="chats" />
    </>
  );
};

// ── 4.1 shell · bottom-bar studies ───────────────────────────
const ShellBarStudy = ({ t, active }) => (
  <div style={{ width: 393, background: t.surface, borderRadius: 16, overflow: 'hidden', boxShadow: elev(1, t.dark) }}>
    <div style={{ height: 56, display: 'flex', alignItems: 'center', justifyContent: 'center', ...ty('labelMedium'), color: t.onSurfaceVariant, background: t.surfaceContainerLow }}>
      body = {active === 'chats' ? '5.1 Chats' : '7.1 Settings'}
    </div>
    <BottomBar t={t} active={active} />
  </div>
);

// ── 5.2 Chat thread ──────────────────────────────────────────
// state: 'filled' | 'empty' | 'offline' | 'attachment'
const ChatThreadScreen = ({ t, state = 'filled', bubble = 'neutral' }) => {
  const op = bubblePreset(t, bubble);
  return (
  <>
    <AppBar t={t} leading="back" title="Night Owls" />
    {state === 'offline' && <MaterialBanner t={t} text="No connection" />}
    <div style={{ flex: 1, minHeight: 0, overflow: 'hidden', display: 'flex', flexDirection: 'column', padding: '8px 12px 4px' }}>
      <SystemLine t={t} text="Chat created by Aria" />
      {state === 'empty' ? (
        <EmptyState t={t} glyph="chat_bubble_outline" title="No messages yet" message="Send the first one." />
      ) : (
        <div style={{ flex: 1, display: 'flex', flexDirection: 'column', justifyContent: 'flex-end' }}>
          <DateSep t={t} label="Today" />
          <AuthorHeader t={t} name="Aria" />
          <MsgBubble t={t} text="Anyone around tonight?" time="22:01" />
          <MsgBubble t={t} text="I’m setting up the room." time="22:01" last />
          <div style={{ height: 12 }} />
          <MsgBubble t={t} mine ownPreset={op} text="On my way." time="22:03" status="sent" />
          <MsgBubble t={t} mine ownPreset={op} file={{ type: 'pdf', name: 'set-list.pdf', size: '240 KB' }} time="22:03" status="sent" last />
          <div style={{ height: 12 }} />
          <AuthorHeader t={t} name="Mox" />
          <MsgBubble t={t} text="Nice. Saving us a spot." time="22:05" last />
          <div style={{ height: 12 }} />
          {state === 'offline'
            ? <MsgBubble t={t} mine ownPreset={op} text="Two minutes." time="22:06" status="pending" last />
            : <MsgBubble t={t} mine ownPreset={op} text="Couldn’t send this one." time="22:06" status="error" last />}
        </div>
      )}
    </div>
    <Composer
      t={t}
      value={state === 'attachment' ? 'Here\u2019s the set list' : (state === 'filled' ? 'Two minutes' : null)}
      attachment={state === 'attachment' ? { type: 'pdf', name: 'set-list.pdf', size: '240 KB' } : null}
      sendActive={state === 'filled' || state === 'attachment'}
    />
  </>
  );
};

// ── 5.3 File view ────────────────────────────────────────────
// state: 'loaded' | 'loading'
const FileViewScreen = ({ t, state = 'loaded' }) => (
  <>
    <AppBar t={t} leading="back" title="quarterly-report.pdf" actions={['download']} onColor={t.onSurface} />
    {state === 'loading' && (
      <div style={{ height: 4, background: t.surfaceVariant }}>
        <div style={{ width: '64%', height: '100%', background: t.primary }} />
      </div>
    )}
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 18, padding: '0 32px' }}>
      <Icon name="picture_as_pdf" size={72} color={fileColor('pdf')} style={{ width: 128, height: 128, borderRadius: 28, background: hexA(fileColor('pdf'), 0.14) }} />
      <div style={{ ...ty('titleLarge'), color: t.onSurface, textAlign: 'center', wordBreak: 'break-word' }}>quarterly-report.pdf</div>
      <div style={{ ...ty('bodyMedium'), color: t.onSurfaceVariant }}>{state === 'loading' ? 'Downloading\u2026 64%' : '2.4 MB'}</div>
    </div>
  </>
);

const FILES = [
  { type: 'pdf', name: 'set-list.pdf', size: '240 KB' },
  { type: 'image', name: 'stage-plan.png', size: '1.8 MB' },
  { type: 'sheet', name: 'budget.xlsx', size: '54 KB' },
  { type: 'audio', name: 'soundcheck.m4a', size: '6.2 MB' },
  { type: 'doc', name: 'rider.docx', size: '88 KB' },
  { type: 'archive', name: 'samples.zip', size: '124 MB' },
];

// ── 5.4 Chat card ────────────────────────────────────────────
// view: 'list' | 'grid' | 'empty'
const ChatCardScreen = ({ t, view = 'list' }) => (
  <>
    <AppBar t={t} leading="back" title="Night Owls" />
    <div style={{ flex: 1, minHeight: 0, overflow: 'hidden', display: 'flex', flexDirection: 'column' }}>
      <div style={{ padding: '8px 16px 16px', display: 'flex', alignItems: 'center', gap: 16 }}>
        <div style={{ borderRadius: '50%', boxShadow: `0 0 0 2px ${hexA(t.onSurface, 0.06)}` }}>
          <Avatar name="Night Owls" size={56} />
        </div>
        <div style={{ ...ty('headlineSmall'), color: t.onSurface }}>Night Owls</div>
      </div>
      <div style={{ padding: '0 16px 12px', display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
        <span style={{ ...ty('titleMedium'), color: t.onSurface }}>Files</span>
        {view !== 'empty' && <Segmented t={t} options={['List', 'Grid']} value={view === 'grid' ? 'Grid' : 'List'} />}
      </div>
      {view === 'empty' ? (
        <EmptyState t={t} glyph="folder_open" title="No files yet" message="Files sent in this chat will appear here." />
      ) : view === 'grid' ? (
        <div style={{ padding: '0 16px', display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 8 }}>
          {FILES.map((f, i) => (
            <div key={i} style={{ aspectRatio: '1', background: t.surfaceContainerHigh, borderRadius: SHAPE.m, padding: 12, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 8, textAlign: 'center' }}>
              <FileGlyph type={f.type} size={26} box={48} />
              <div style={{ ...ty('labelMedium'), color: t.onSurface, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', maxWidth: '100%' }}>{f.name}</div>
              <div style={{ ...ty('labelSmall'), color: t.onSurfaceVariant }}>{f.size}</div>
            </div>
          ))}
        </div>
      ) : (
        <div>
          {FILES.map((f, i) => (
            <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 16, padding: '10px 16px' }}>
              <FileGlyph type={f.type} size={24} box={44} />
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ ...ty('titleMedium'), color: t.onSurface, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{f.name}</div>
                <div style={{ ...ty('bodyMedium'), color: t.onSurfaceVariant }}>{f.size}</div>
              </div>
              <Icon name="chevron_right" size={22} color={t.onSurfaceVariant} />
            </div>
          ))}
        </div>
      )}
    </div>
  </>
);

// ── 6.1 Create chat ──────────────────────────────────────────
// state: 'valid' | 'taken' | 'checking' | 'loading' | 'empty'
const CreateChatScreen = ({ t, state = 'valid' }) => {
  const value = state === 'empty' ? '' : (state === 'taken' ? 'Night Owls' : 'Midnight Jazz');
  const error = state === 'taken' ? 'This name is taken' : null;
  const focused = state !== 'empty';
  const suffix = state === 'checking' ? <div style={{ width: 24, height: 24 }}><Spinner size={20} color={t.onSurfaceVariant} /></div> : null;
  const createEnabled = state === 'valid';
  return (
    <>
      <AppBar t={t} leading="back" title="New chat" />
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', padding: '8px 16px 24px', minHeight: 0 }}>
        <div style={{ marginTop: 12 }}>
          <TextField
            t={t} label="Chat name" value={value}
            placeholder="e.g. Random thoughts"
            focused={focused} error={error}
            counter={`${value.length}/64`} suffix={suffix}
          />
        </div>
        <div style={{ flex: 1 }} />
        <FilledButton t={t} label="Create" full disabled={!createEnabled || state === 'loading'} loading={state === 'loading'} />
      </div>
    </>
  );
};

Object.assign(window, {
  CHATS, ChatsListScreen, ShellBarStudy, ChatThreadScreen,
  FileViewScreen, FILES, ChatCardScreen, CreateChatScreen,
});
