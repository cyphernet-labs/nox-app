# 04 · Chat info / Files

> **04 · Flows & dialogs** · desktop (Windows / Linux / macOS) · Material 3 · window 1440×900

**Purpose.** Chat details + shared files — a right-side drawer.

**Adaptation from mobile.** mobile pushed Chat card (5.4) → right details drawer

## Anatomy
Scrim + right drawer (380): Details header, chat avatar/name with the `Rename chat` action (`edit` glyph), **“People”** (one row — the person this machine belongs to — plus a disabled **Invite a person** button and its caption), hairline, then “Files” with List/Grid toggle, file rows or 2-col grid. The body is one scroll.
> **The invite is a disabled seam (phase 037).** The client server serves one person; talking to anybody else goes through a relay that does not exist yet, and the invite button is the place it will attach to. The live screen in `_src/` draws it too, with a PERSON's initials the way the app does (Nyx → N, not NY). There is no subtitle under the chat name: a chat has no roster.


## States
- `list` — Files · list
- `grid` — Files · grid
- `empty` — Empty
- `offline-cause` — Offline, cause known
- `server-mismatch` — Wrong server

## Behavior
- The People section renders only once the card has loaded. While files are still coming, and on the embedded error screen, it is absent: a person and a disabled button stacked over a spinner or over an error say nothing true about either.
- Mobile’s pushed Chat card (5.4) becomes a right drawer over the thread. Segmented switches List ⇄ Grid; empty → folder_open state.
- No connection: the strip at the top of the drawer. As in both chat panes, it says the cause in place of “No connection” whenever the app can tell (feature 045; the five sentences of 01 · Chats, the same `wifi_off` glyph). It carries Try again (phase 042), which restarts the channel: a new attempt starts at once, the strip gives way to Connecting… and comes back if that attempt fails too. For a server that refuses this build the strip has no action - trying again cannot change its answer.
- Rename: as on mobile 5.4 — the rename dialog; a chat the server has is renamed on the server, one still waiting to be created (phase 041) on the device.
- Wrong server: the server reached through its ONION address presented a key the pairing link did not name. Another key at a direct address is “not home”, never this state. A persistent banner “This onion address belongs to a different server.” with a “Try again” action, at the TOP of the drawer — under its own header, above the chat identity — because pushed below the People block it falls off the first fold. INSTEAD of the offline banner, never alongside it: something answered. The files stay listed under it; nothing local is thrown away.

## Navigation
- Opened from the thread header info action (folder-open icon).
- File row / cell → File view lightbox.
- Close / scrim → dismiss.
- Rename chat → the rename dialog (Cancel · Save).

## Copy (EN)
- Title: Details
- Rename action (tooltip) / dialog title: Rename chat
- Section: People
- Person row: the label of the person this machine belongs to
- Button (disabled): Invite a person
- Caption: Available in a future version
- Offline strip: No connection, or its cause when known / Try again
- Wrong-server banner: This onion address belongs to a different server. / Try again
- Section: Files
- Empty: No files yet / Files sent in this chat will appear here.

## Design-system components
- ChatsDesktop (base)
- ChatInfoDrawer
- Avatar (72)
- Segmented
- FileGlyph
- EmptyState

---
Live design: open `index.html` → 04 Chat info / Files (switch states with the chips). The desktop shell re-arranges the SAME widgets as mobile — only the wrapper differs.
