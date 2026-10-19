# NOX — Empty-state sketches

**Status: corpus sketches only.** `empty-chats.svg`, `empty-messages.svg` and `empty-files.svg` stay
here as sketches of the design corpus. No illustration is ordered and none ships in the app bundle:
the art of an empty state is the `NoxEmptyState` composition (`AppEmptyContentWidget` in the app) —
the glyph below (`onSurfaceVariant`, 56) in a 132 outlined box (radius 20, 1.5 `outlineVariant`)
with two brand dots inside it (`brand/teal` 14 top-right, `brand/gold` 10 bottom-left), over the
heading and the message. See `design-system.md` §10 and `../../nox-handoff-2/spec/primitives.md`.

## The three
| File | Screen | Glyph the app draws in the composition |
|---|---|---|
| empty-chats.svg | 5.1 no chats (and the empty thread pane on desktop) | `forum` (outlined) |
| empty-messages.svg | 5.2 no messages | `chat_bubble` (outlined) |
| empty-files.svg | 5.4 no files | `folder_open` |

Glyph color: `onSurfaceVariant`.
