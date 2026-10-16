# NOX — Empty-state illustrations

**Status: placeholders.** `empty-chats.svg`, `empty-messages.svg`, `empty-files.svg` here are
striped placeholders so layouts can be wired up; design-system.md §11 still lists real art as an
order. The app draws none of them: its empty state is the `NoxEmptyState` composition — the icon below
(`onSurfaceVariant`, 56) in a 132 outlined box with two brand accents, over the heading and the
message (`../../nox-handoff-2/spec/primitives.md`). The three SVGs ship in `assets/svg/illustrations/`
and nothing references them.

## Spec (design-system.md §10)
- Style: light line / "brushstroke" spot illustrations in the logo spirit — thin contour
  (`onSurfaceVariant`) + one or two brand accents (`brand/teal` #12B4B4 + `brand/gold` #F4C20C),
  **transparent** background.
- Size: ~120–160 tall, centered, above the empty-state heading.
- One asset must read on **both** light and dark.
- Format: **SVG**.

## The three
| File | Screen | Icon the app draws |
|---|---|---|
| empty-chats.svg | 5.1 no chats | `forum_outlined` |
| empty-messages.svg | 5.2 no messages | `chat_bubble_outline` |
| empty-files.svg | 5.4 no files | `folder_open` |

Icon color: `onSurfaceVariant`.
