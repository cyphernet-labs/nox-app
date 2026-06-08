# 4.1 · Navigation shell

> **Shell & Chats** · mobile (iOS / Android) · Material 3

**Purpose.** Top-level scaffold hosting the two destinations + the create action.

## Anatomy
BottomAppBar (surfaceContainer, elev 2) with a circular notch; two tabs (Chats forum / Settings settings); a docked “+” FAB (primaryContainer, elev 3) cradled in the notch.

## States
- `chats` — Chats tab
- `settings` — Settings tab

## Behavior
- Two destinations switch via an IndexedStack with a ≤150ms fade (tabFade); state is preserved per tab.
- Selected tab → primary + filled icon; unselected → onSurfaceVariant + outlined icon.
- The “+” is an action (create chat), NOT a third tab — it is visible on both tabs.

## Navigation
- Chats tab → 5.1.
- Settings tab → 7.1.
- + → Create chat (6.1).

## Copy (EN)
- Tabs: Chats · Settings

## Design-system components
- BottomBar (notch + docked FAB)
- Icon: forum / settings / add
- Motion: tabFade 150ms

---
Live design: open `index.html` → 4.1 Navigation shell (switch states with the chips). Components are rendered from the shared design system (`_src/`).
