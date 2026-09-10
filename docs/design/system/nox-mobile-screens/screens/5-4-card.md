# 5.4 · Chat card

> **Shell & Chats** · mobile (iOS / Android) · Material 3

**Purpose.** Chat header + its shared files.

## Anatomy
App bar (back + chat name). Header: avatar (56) + name (headlineSmall). **“People”** section: one row — the person this machine belongs to — then a disabled **Invite a person** button with the caption below it. Hairline, then the “Files” section with a List/Grid segmented toggle and file rows or a grid.
> **Изменено 2026-09-10 (фаза 037).** Клиент-бэкенд обслуживает одного человека; общение с другими людьми уходит на relay, которого ещё нет. Приглашение присутствует как выключенный шов — место, к которому relay прирастёт.


## States
- `list` — Files · list
- `grid` — Files · grid
- `empty` — Empty

## Behavior
- The People section renders only once the card has loaded. While files are still coming, and on the embedded error screen, it is absent: a person and a disabled button stacked over a spinner or over an error say nothing true about either.
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

## Design-system components
- AppBar (title)
- Avatar (56)
- Segmented
- FileGlyph
- EmptyState

---
Live design: open `index.html` → 5.4 Chat card (switch states with the chips). Components are rendered from the shared design system (`_src/`).
