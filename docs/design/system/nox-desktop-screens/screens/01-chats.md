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
- Thread header is persistent (avatar + chat name + **two** actions) — a desktop affordance the mobile thread lacks. Tapping the avatar/name opens the chat card; the info action (folder-open icon) opens Chat info; the second action is **Invite a person, permanently disabled** (phase 037) — inviting anybody at all goes through a relay whose protocol does not exist yet, so the seam is shown honestly rather than hidden. Pressing it does nothing: no screen, no snackbar, no error. It carries a text name for screen readers and is announced unavailable.
- The header shows **no member list, no per-chat search, no folders**. No members because a chat has no roster to show: the server belongs to one person and serves only their own devices. Search and folders are out of scope. Source of truth: `docs/design/spec/screens/chat.md` §Десктоп.

> **Changed 2026-09-10 (phase 037).** This file used to describe the header as carrying a *single* info action, and justified the missing member list by the "open shared space" model. Both statements are superseded: there are two actions now, and the reason for no members is that the machine holds one person. The corpus follows the owner's decision, not the other way round. The live screen in `_src/` draws it too: this header composes `IconButton`, which takes an explicit `color`, so the seam is dimmed to the M3 disabled 38% exactly as the app dims it. The excuse first written here — "the corpus AppBar has no disabled variant" — was about a widget this screen does not use. Per-chat search and folders went at the same time (never in the spec), and so did the `Aria, Mox and you` subtitle: a chat has no roster.
- Offline: “No connection” banner appears in both panes. Loading: spinner in the list pane.
- Search filters the list pane in place; no match → “No chats found”.
- Transient feedback floats as a Snackbar centered over the thread pane.

## Navigation
- Row → loads thread in right pane.
- Rail + → Create chat dialog (04).
- Rail account avatar (bottom) → Settings, landing on the Account section (NOX has no separate profile screen).
- Thread header (avatar / chat name / info action) → Chat card / Chat info (04).
- Thread header invite action → nowhere: it is disabled and stays disabled.
- Attachment / file bubble → File view lightbox (04).

## Copy (EN)
- Pane titles: Chats
- No-selection: Select a chat / Choose a conversation on the left, or press + to start a new one.
- Invite action: Invite a person (always disabled)

> The thread subtitle that named members ("Aria, Mox and you") was corpus drift before phase 037 and wrong outright after it — a chat has no roster. Removed from the live screen with the rest of this revision; the header shows the chat name and nothing under it.

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
