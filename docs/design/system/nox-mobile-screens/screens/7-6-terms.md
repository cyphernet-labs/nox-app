# 7.6 · Terms

> **Settings** · mobile (iOS / Android) · Material 3

**Purpose.** Static Terms of Service text.

## Anatomy
App bar (back + Terms). Scrollable titled sections + version line. Body is shared verbatim with the desktop Terms detail pane (TermsBody).

## States
- `default` — Terms

## Behavior
- Read-only legal copy. The exact same TermsBody renders on mobile and desktop — one source.

## Navigation
- Back → Settings (7.1).

## Copy (EN)
- Heading: Terms of Service
- Sections: Acceptance · Your identity · Content · Privacy
- Footer: Version 1.2.3

## Design-system components
- AppBar (title)
- TermsBody (shared)

---
Live design: open `index.html` → 7.6 Terms (switch states with the chips). Components are rendered from the shared design system (`_src/`).
