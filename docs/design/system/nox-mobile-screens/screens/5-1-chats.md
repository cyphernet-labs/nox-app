# 5.1 · Chats list

> **Shell & Chats** · mobile (iOS / Android) · Material 3

**Purpose.** Browse and search all chats; entry point to threads and create.

## Anatomy
App bar (wordmark + trailing account avatar) + persistent SearchBar + scrollable list of chat rows. Bottom bar + FAB.

## States
- `filled` — Filled
- `loading` — Loading
- `empty` — Empty
- `offline` — Offline
- `server-mismatch` — Wrong server
- `inline-error` — Load error
- `search` — Search
- `search-empty` — Search empty
- `snack` — Snackbar

## Behavior
- Rows: avatar (with ring) + name + last-message preview + relative time + unread badge.
- Unread emphasis: name w600, preview onSurface, time primary, badge shown (caps 99+, hidden at 0).
- Loading: centered spinner. Empty: forum empty-state.
- Offline: persistent “No connection” MaterialBanner at top. Load error: banner “Could not load chats. Pull to refresh.”
- Wrong server (036): the machine at the paired address presented a key the pairing link did not name. A persistent banner “This isn't the server you paired with” with a “Try again” action, INSTEAD of the offline one — something answered, so “No connection” would be false — and with the error glyph rather than wifi_off. Nothing local is thrown away, and nothing on screen is cleared: the banner sits over what was already there. It does not pass on its own; the action is the only way out.
- Tapping the SearchBar opens the full search view (back + query + caret, clear); results filter live; no match → “No chats found”.
- Transient one-off feedback appears as a Snackbar floating above the bottom bar.

## Navigation
- Row → Chat thread (5.2).
- + → Create chat (6.1).
- Search → search view (same screen).
- Account avatar (trailing, app bar) → Settings tab / Account section (the narrow-branch counterpart to the desktop rail avatar; N4).

## Copy (EN)
- Search hint: Search
- Empty: No chats yet / Tap + to create the first one.
- Load error: Could not load chats. Pull to refresh.
- Search empty: No chats found

## Design-system components
- AppBar (wordmark + account Avatar with ring)
- SearchBar / SearchView
- ChatListItem (unread Badge)
- MaterialBanner
- EmptyState
- Snackbar
- BottomBar

---
Live design: open `index.html` → 5.1 Chats list (switch states with the chips). Components are rendered from the shared design system (`_src/`).
