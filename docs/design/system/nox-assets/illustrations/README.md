# NOX — Empty-state illustrations

**Status: placeholders.** `empty-chats.svg`, `empty-messages.svg`, `empty-files.svg` here are
striped placeholders so layouts can be wired up. Replace with real art before release. Until then,
screens fall back to a Material icon + text (see icon column below).

## Spec (design-system.md §10)
- Style: light line / "brushstroke" spot illustrations in the logo spirit — thin contour
  (`onSurfaceVariant`) + one or two brand accents (`brand/teal` #12B4B4 + `brand/gold` #F4C20C),
  **transparent** background.
- Size: ~120–160 tall, centered, above the empty-state heading.
- One asset must read on **both** light and dark.
- Format: **SVG**.

## The three
| File | Screen | Fallback icon |
|---|---|---|
| empty-chats.svg | 5.1 no chats | `forum_outlined` |
| empty-messages.svg | 5.2 no messages | `chat_bubble_outline` |
| empty-files.svg | 5.4 no files | `folder_open` |

Fallback icon color: `onSurfaceVariant`.
