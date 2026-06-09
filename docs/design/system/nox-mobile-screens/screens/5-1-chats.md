# 5.1 · Chats list

> **Shell & Chats** · mobile (iOS / Android) · Material 3

**Purpose.** Browse and search all chats; entry point to threads and create.

## Anatomy
App bar (wordmark) + persistent SearchBar + scrollable list of chat rows. Bottom bar + FAB.

## States
- `filled` — Filled
- `loading` — Loading
- `empty` — Empty
- `offline` — Offline
- `inline-error` — Load error
- `search` — Search
- `search-empty` — Search empty
- `snack` — Snackbar

## Behavior
- Rows: avatar (with ring) + name + last-message preview + relative time + unread badge.
- Unread emphasis: name w600, preview onSurface, time primary, badge shown (caps 99+, hidden at 0).
- Loading: centered spinner. Empty: forum empty-state.
- Offline: persistent “No connection” MaterialBanner at top. Load error: banner “Could not load chats. Pull to refresh.”
- Tapping the SearchBar opens the full search view (back + query + caret, clear); results filter live; no match → “No chats found”.
- Transient one-off feedback appears as a Snackbar floating above the bottom bar.

## Navigation
- Row → Chat thread (5.2).
- + → Create chat (6.1).
- Search → search view (same screen).

## Copy (EN)
- Search hint: Search
- Empty: No chats yet / Tap + to create the first one.
- Load error: Could not load chats. Pull to refresh.
- Search empty: No chats found

## Design-system components
- AppBar (wordmark)
- SearchBar / SearchView
- ChatListItem (unread Badge)
- MaterialBanner
- EmptyState
- Snackbar
- BottomBar

---
Live design: open `index.html` → 5.1 Chats list (switch states with the chips). Components are rendered from the shared design system (`_src/`).
