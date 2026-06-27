# 01 · Chats

> **01 · Chats** · desktop (Windows / Linux / macOS) · Material 3 · window 1440×900

**Purpose.** Primary workspace: a two-pane list-detail of all chats (left) and the open thread (right).

**Adaptation from mobile.** mobile BottomBar → NavigationRail · full screens (5.1 + 5.2) → list-detail panes

## Anatomy
NavigationRail (80) + chat list pane (360, with pane header + SearchBar) + thread pane (header, message stream capped to a ≤980 reading column, composer). The mobile bottom bar becomes the rail; full-screen list/thread become side-by-side panes. The rail's leading is the `+` create FAB; its **trailing is the account avatar** (size 36, generated initials + hashed color + subtle ring) pinned to the bottom.

## States
- `filled` — Selected
- `no-selection` — No selection
- `thread-empty` — Thread empty
- `attachment` — Attachment
- `offline` — Offline
- `loading` — Loading
- `search` — Search
- `search-empty` — Search empty
- `snack` — Snackbar

## Behavior
- Selecting a row highlights it (secondaryContainer) and loads the thread on the right — no navigation push.
- No-selection: the thread pane shows a “Select a chat” placeholder; the “+” lives on the rail.
- Thread header is persistent (avatar, members, search/folder/info actions) — a desktop affordance the mobile thread lacks.
- Offline: “No connection” banner appears in both panes. Loading: spinner in the list pane.
- Search filters the list pane in place; no match → “No chats found”.
- Transient feedback floats as a Snackbar centered over the thread pane.

## Navigation
- Row → loads thread in right pane.
- Rail + → Create chat dialog (04).
- Rail account avatar (bottom) → Settings, landing on the Account section (NOX has no separate profile screen).
- Thread folder/info → Chat info drawer (04).
- Attachment / file bubble → File view lightbox (04).

## Copy (EN)
- Pane titles: Chats
- No-selection: Select a chat / Choose a conversation on the left, or press + to start a new one.
- Thread sub: Aria, Mox and you

## Design-system components
- NavRail
- PaneHeader
- SearchBar
- ChatListItem (selectable ChatRow)
- ThreadHeader
- MsgBubble / DateSep / AuthorHeader
- Composer
- MaterialBanner
- EmptyState
- Snackbar

---
Live design: open `index.html` → 01 Chats (switch states with the chips). The desktop shell re-arranges the SAME widgets as mobile — only the wrapper differs.
