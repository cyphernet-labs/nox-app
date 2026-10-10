# 5.4 · Chat card

> **Shell & Chats** · mobile (iOS / Android) · Material 3

**Purpose.** Chat header + its shared files.

## Anatomy
App bar (back + chat name). Header: avatar (56) + name (headlineSmall). **“People”** section: one row — the person this machine belongs to — then a disabled **Invite a person** button with the caption below it. Hairline, then the “Files” section with a List/Grid segmented toggle and file rows or a grid. The body is one scroll.
> **Changed 2026-09-10 (phase 037).** The client backend serves one person; talking to anybody else moves to a relay that does not exist yet. The invite is present as a disabled seam — the place the relay will attach to. The live screen in `_src/` draws it too: `Avatar` gained an `initials` override so the corpus can show a PERSON the way the app does (Nyx → N, not NY), and the disabled `FilledButton` was already there.


## States
- `list` — Files · list
- `grid` — Files · grid
- `empty` — Empty
- `offline-cause` — Offline, cause known
- `server-mismatch` — Wrong server

## Behavior
- The People section renders only once the card has loaded. While files are still coming, and on the embedded error screen, it is absent: a person and a disabled button stacked over a spinner or over an error say nothing true about either.
- Wrong server (036, narrowed by 040): the server reached through its ONION address presented a key the pairing link did not name. Another key at a direct address is “not home”, never this state. A persistent banner “This onion address belongs to a different server.” with a “Try again” action, INSTEAD of the offline one — something answered, so “No connection” would be false — and with the error glyph rather than wifi_off. Nothing local is thrown away, and nothing on screen is cleared: the banner sits over what was already there. It does not pass on its own; the action is the only way out. It sits at the TOP of the card, above the header: pushed below the People block it lands ~150dp down and can fall off the first fold on a phone at a large text scale.
- No connection: the strip at the top, as in the thread — and, as there, it says the cause in place of “No connection” whenever the app can tell (feature 045; the five sentences of 5.1, the same no-signal glyph). It carries Try again (phase 042), which restarts the channel: a new attempt starts at once, the strip gives way to Connecting… and comes back if that attempt fails too. For a server that refuses this build the strip has no action - trying again cannot change its answer.
- List rows: file glyph + name (ellipsis) + size + chevron. Grid: square type cells.
- Segmented control switches List ⇄ Grid (single-select).
- Empty: folder_open empty-state.

## Navigation
- Back → thread (5.2).
- File row / cell → File view (5.3).

## Copy (EN)
- Section: People
- Person row: the label of whoever owns this machine
- Button (disabled): Invite a person
- Caption: Available in a future version
- Section: Files
- Empty: No files yet / Files sent in this chat will appear here.
- Offline strip: No connection, or its cause when known (as 5.1) · Try again
- Wrong-server strip: This onion address belongs to a different server. · Try again

## Design-system components
- AppBar (title)
- Avatar (56)
- Segmented
- FileGlyph
- EmptyState

---
Live design: open `index.html` → 5.4 Chat card (switch states with the chips). Components are rendered from the shared design system (`_src/`).
