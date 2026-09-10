# 04 · Chat info / Files

> **04 · Flows & dialogs** · desktop (Windows / Linux / macOS) · Material 3 · window 1440×900

**Purpose.** Chat details + shared files — a right-side drawer.

**Adaptation from mobile.** mobile pushed Chat card (5.4) → right details drawer

## Anatomy
Scrim + right drawer (380): Details header, chat avatar/name, **“People”** (one row — the person this machine belongs to — plus a disabled **Invite a person** button and its caption), hairline, then “Files” with List/Grid toggle, file rows or 2-col grid.
> **Изменено 2026-09-10 (фаза 037).** Клиент-бэкенд обслуживает одного человека; общение с другими людьми уходит на relay, которого ещё нет. Приглашение присутствует как выключенный шов — место, к которому relay прирастёт.


## States
- `list` — Files · list
- `grid` — Files · grid
- `empty` — Empty

## Behavior
- The People section renders only once the card has loaded. While files are still coming, and on the embedded error screen, it is absent: a person and a disabled button stacked over a spinner or over an error say nothing true about either.
- Mobile’s pushed Chat card (5.4) becomes a right drawer over the thread. Segmented switches List ⇄ Grid; empty → folder_open state.

## Navigation
- Opened from the thread header info/folder action.
- File row / cell → File view lightbox.
- Close / scrim → dismiss.

## Copy (EN)
- Title: Details
- Section: People
- Person row: the label of whoever owns this machine
- Button (disabled): Invite a person
- Caption: Available in a future version
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
