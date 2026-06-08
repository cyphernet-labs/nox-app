# 5.4 · Chat card

> **Shell & Chats** · mobile (iOS / Android) · Material 3

**Purpose.** Chat header + its shared files.

## Anatomy
App bar (back + chat name). Header: avatar (56) + name (headlineSmall). “Files” section with a List/Grid segmented toggle, then file rows or a grid.

## States
- `list` — Files · list
- `grid` — Files · grid
- `empty` — Empty

## Behavior
- List rows: file glyph + name (ellipsis) + size + chevron. Grid: square type cells.
- Segmented control switches List ⇄ Grid (single-select).
- Empty: folder_open empty-state.

## Navigation
- Back → thread (5.2).
- File row / cell → File view (5.3).

## Copy (EN)
- Section: Files
- Empty: No files yet / Files sent in this chat will appear here.

## Design-system components
- AppBar (title)
- Avatar (56)
- Segmented
- FileGlyph
- EmptyState

---
Live design: open `index.html` → 5.4 Chat card (switch states with the chips). Components are rendered from the shared design system (`_src/`).
