# 5.1 · Chats list

> **Shell & Chats** · mobile (iOS / Android) · Material 3

**Purpose.** Browse and search all chats; entry point to threads and create.

## Anatomy
App bar (wordmark + trailing account avatar) + persistent SearchBar + scrollable list of chat rows. Bottom bar + FAB.

## States
- `filled` — Filled
- `loading` — Loading
- `empty` — Empty
- `connecting` — Connecting (corner)
- `tor` — Through Tor (corner badge)
- `tor-obsolete` — Update NOX strip
- `offline` — Offline
- `offline-cause` — Offline, cause known
- `server-mismatch` — Wrong server
- `inline-error` — Load error
- `search` — Search
- `search-empty` — Search empty
- `snack` — Snackbar

## Behavior
- Rows: avatar (with ring) + name + last-message preview + relative time + unread badge.
- Unread emphasis: name w600, preview onSurface, time primary, badge shown (caps 99+, hidden at 0).
- A chat made on this device that the server does not have yet (phase 041) sits in the list at once, ordered like any other by last activity, and says where it stands with the glyphs a message uses for the same thing. Waiting to be created: a clock (`schedule`, onSurfaceVariant, 16) in place of the time, screen-reader name “Waiting to be created”, preview kept. Refused by the server: the error glyph (`error` colour) in place of the time and the reason in place of the preview, in the error colour — “Name already taken” or “Couldn't create”. The row is one node for the screen reader and reads a refusal once, from its words; the glyph beside them is left out. Locked by the goldens `app_chat_item_widget_creation` and `chats_list_page_creation` (no live-design chip yet).
- Loading: the chats already on the device show at once, whatever the connection is doing; the server's page arrives in the background. A centered spinner only when the device holds no chats and the server is being asked — with no connection the empty state shows at once, and the list asks the server again when the connection returns. Empty: forum empty-state.
- Connection corner (phase 040): only deviations show, right of the app bar before the account avatar. Through Tor — a `Tor` badge (`secondaryContainer` / `onSecondaryContainer`). While a path comes up or catches up — “Connecting…” (`onSurfaceVariant`), with the `Tor` badge when that path is Tor. Direct and current — nothing. No percentages or bars: a Tor bring-up can be long and the local chats stay usable meanwhile. Tapping it opens a bottom sheet explaining the path (on iOS also where to allow Local Network access). Screen-reader name: “Connected through Tor” / “Connecting to your server” / “Connecting to your server through Tor”; tap target ≥ 48×48.
- Offline: a persistent MaterialBanner at top, once a whole round of path finding — direct, and through Tor when Use Tor is on — found nothing; the corner is empty then. It says WHY when the app can tell (feature 045), in place of “No connection”, with the same no-signal glyph (`wifi_off`): “No server answers at this onion address. Check the address and that Tor is running on the server.” · “Your server isn't answering through Tor right now. Check that it is running.” · “Can't connect to the Tor network. Check your internet connection.” · “Can't reach the server directly. Turn on Use Tor to connect through Tor.” · “This isn't a valid onion address.” The cause is the last failed round's; a round whose cause cannot be told shows “No connection”, and the next greeting clears it. Locked by the golden `chats_list_page_turn_on_tor` at both widths. Load error: banner “Could not load chats. Pull to refresh.”
- Try again on No connection (phase 042): It carries Try again (phase 042), which restarts the channel: a new attempt starts at once, the strip gives way to Connecting… and comes back if that attempt fails too. For a server that refuses this build the strip has no action - trying again cannot change its answer.
- Update NOX (phase 040): when the Tor network has declared the built-in client obsolete, a notice strip “Update NOX to connect away from home” sits at the top; at home the connection goes direct as usual.
- Wrong server (036, narrowed by 040): the server reached through its ONION address presented a key the pairing link did not name. Another key at a direct address is “not home” and never this state — on another network the same address is somebody else's machine. A persistent banner “This onion address belongs to a different server.” with a “Try again” action, INSTEAD of the offline one — something answered, so “No connection” would be false — and with the error glyph rather than wifi_off. Nothing local is thrown away, and nothing on screen is cleared: the banner sits over what was already there. It does not pass on its own; the action is the only way out.
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
- Corner: Connecting… · Tor
- Update strip: Update NOX to connect away from home
- Offline strip: No connection, or its cause when known (the five sentences under Behavior) · Try again
- Wrong-server strip: This onion address belongs to a different server. · Try again
- Waiting chat, clock (screen-reader name): Waiting to be created
- Refused chat, status line: Name already taken · Couldn't create

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
