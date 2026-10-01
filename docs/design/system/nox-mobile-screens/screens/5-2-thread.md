# 5.2 · Chat thread

> **Shell & Chats** · mobile (iOS / Android) · Material 3

**Purpose.** Read and send messages + files within one chat.

## Anatomy
App bar (back + chat name + a disabled **Invite a person** action). Message stream with date separators, author headers and bubbles. Composer pinned at bottom.
> **Changed 2026-09-10 (phase 037).** The client backend serves one person; talking to anybody else moves to a relay that does not exist yet. The invite is present as a disabled seam — the place the relay will attach to. The live screen in `_src/` draws it too. It did not at first, and the excuse written here — "the corpus AppBar has no disabled variant" — was wrong three times over: the blocker was one hardcoded colour in `m3.jsx`'s `actions.map`, while `IconButton` in the same shared file had always taken a `color`. `AppBar` actions now accept `{name, color}`, and the seam is dimmed to the M3 disabled 38% exactly as the app dims it.


## States
- `filled` — Filled
- `empty` — Empty
- `attachment` — Attachment
- `connecting` — Connecting (corner)
- `tor` — Through Tor (corner badge)
- `offline` — Offline
- `server-mismatch` — Wrong server

Connection corner (phase 040): the same rule as 5.1 — only deviations, right of the app bar before the invite action: a `Tor` badge on the Tor path, “Connecting…” (with the badge on Tor) while the path comes up. A message sent meanwhile waits as `pending`, it does not fail. “No connection” appears only after a whole round of path finding found nothing. The wrong-server banner is for the onion address only.

## Behavior
- Messages group by author; an AuthorHeader precedes each group (no per-message avatars in the feed).
- Own bubbles = primaryContainer (right, bottom-right corner clipped); others = surfaceContainerHigh (left, bottom-left clipped).
- Own message status: pending (schedule) → sent (check) → error (error, tinted error; tap to retry). An own message that came from the server is sent, including one typed on another device of the same person (contract §5).
- A message with a file shows how far its bytes have got while they go up: a picture carries a ring on a dark disc over its middle (the disc keeps the ring legible over any photo); any other file swaps its size line for “Sending… 45%” over a bar. Before the first byte moves — the server is still issuing the upload pass, which takes seconds through Tor — the ring spins and the bar runs without a percent. The ring stays until the server has accepted the message itself and leaves with the clock. A text has no indicator of its own: clock → tick is its whole journey.
- Date separators: Today / Yesterday / 12 May. A system line marks chat creation.
- Empty: chat_bubble_outline empty-state. Offline: top banner + queued messages show pending.
- Wrong server (036, narrowed by 040): the server reached through its ONION address presented a key the pairing link did not name. Another key at a direct address is “not home”, never this state. A persistent banner “This isn't the server you paired with” with a “Try again” action, INSTEAD of the offline one — something answered, so “No connection” would be false — and with the error glyph rather than wifi_off. Nothing local is thrown away, and nothing on screen is cleared: the banner sits over what was already there. It does not pass on its own; the action is the only way out. A message written in this state waits as `pending` exactly as it does offline, and must never show as an error: the server never saw it, so the failure is not the person's.
- Composer: attach + text + send. Send enables when there is text or an attachment; attachment shows a removable chip above the row.
- The invite action is permanently disabled and raises nothing when tapped: a missing control answers «how do I add somebody?» with silence, an error answers it with a fault, and the truth is that the relay it needs does not exist yet. Its screen-reader name is the action alone — a disabled control is already announced as unavailable, and the caption that says it comes later lives under the button in 5.4, where there is room for it.
- Attachments in the feed, in THREE states rather than two (owner revision, 2026-09-20): an image with a real local file renders an inline thumbnail (rounded, bubble-bounded); an image whose bytes have not arrived yet takes the same box with a picture glyph and a spinner - it used to draw the same chip an unopenable file draws, so nothing said the fetch already running was running, and people tapped and started a second download of the same bytes; every other type - and an image that will never be a thumbnail, such as an svg - renders the type-icon chip (owner-revised F4). A composer draft never gets the placeholder: its file is on disk and nobody is fetching it. While the bytes of a received picture come in, the placeholder's spinner becomes a ring that fills with them. The fetch starts when the thread loads, on every refresh of it (a picture that arrives while the thread is open comes in this way) and when the connection returns.

## Navigation
- Back → Chats list (5.1).
- Attachment chip / file bubble → File view (5.3); an image thumbnail → full-screen image viewer (zoom / close) (F4).
- Tapping the chat name in the app bar opens the chat card (5.4).
- Invite action → nowhere: it is disabled and stays disabled until a relay exists.

## Copy (EN)
- System: Chat created by Aria
- Composer placeholder: Message
- Invite action (screen-reader name): Invite a person
- Corner: Connecting… · Tor

## Design-system components
- AppBar (title)
- MsgBubble (+status)
- FileChip (in-bubble)
- DateSep / AuthorHeader / SystemLine
- Composer
- MaterialBanner
- EmptyState

---
Live design: open `index.html` → 5.2 Chat thread (switch states with the chips). Components are rendered from the shared design system (`_src/`).
