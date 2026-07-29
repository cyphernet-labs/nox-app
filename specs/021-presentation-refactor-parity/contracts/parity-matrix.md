# Contract: паритет-матрица responsive-экранов

**Phase 1.** Контракт для SC-005: по каждому responsive-файлу (`_narrow`/`_wide` развилка) — требуемый паритет
действий/аффордансов/состояний и текущий статус. Приёмка фазы P ⇔ все строки `gap` закрыты (либо ✅ clean,
либо ✔ confirmed-intentional).

| # | Файл (responsive) | Паритет-контракт (что MUST быть на обеих ветках) | Текущий статус | Задача |
|---|---|---|---|---|
| 1 | `error_page.dart` | `ErrorPageMode` соблюдается на ОБЕИХ: blocking → неотменяем; embedded → back | ❌ gap: `_wide` игнорит `_mode` (fatal escapable) | R1 |
| 2 | `app_message_bubble_widget.dart` | own/other «коридор» (max-width от локальной панели) на обеих | ❌ gap: width от окна → на desktop коридор пропадает | R2 |
| 3 | `tab_bar_shell_widget.dart` | заголовок/подпись активного таба, локализованные, на обеих | ❌ gap: desktop titlebar `'Chats'` захардкожен, не per-tab | R3 |
| 4 | `app_navigation_rail_widget.dart` | a11y-роль (button+selected) на пунктах навигации на обеих | ❌ gap: desktop-rail без `Semantics` | R4 |
| 5 | `create_chat_page.dart` | блокировка отмены во время submit на обеих | ❌ gap: mobile отменяем in-flight | R5 |
| 6 | `chats_list_page.dart` | hairline под header списка на обеих | ❌ gap: desktop pane-header без hairline | R6 |
| 7 | `qr_scan_page.dart` | камерные контролы (torch/switch) | ✔ intentional: mobile-only (desktop webcam) — подтверждено | R7 |
| 8 | `settings_root_page.dart` | account: Copy + Show-QR на обеих (базовый паритет) | ✔ intentional: reveal-ID(mobile)/inline-QR(desktop) split — Принцип I | R8 |
| 9 | `app_shell.dart` | shell-контейнер (rail/bottom-bar по ширине) | ✅ clean | — |
| 10 | `chat_card_page.dart` | header (name+avatar+pencil), files, scenarios | ✅ clean (после edit-chat-name — оба layout reactive) | — |
| 11 | `chat_thread_page.dart` | title→card, composer, states | ✅ clean | — |
| 12 | `file_view_page.dart` | download/save/preview на обеих | ✅ clean (adaptive mobile push / desktop dialog) | — |
| 13 | `image_viewer_page.dart` | full-screen / lightbox viewer | ✅ clean | — |
| 14 | `set_username_page.dart` | id-field + actions на обеих | ✅ clean (делит `_idField`/`_actions`) | — |
| 15 | `app_detail_scaffold_widget.dart` | master-detail scaffold | ✅ clean | — |
| 16 | `app_thread_view_widget.dart` | thread body + header (desktop) + composer | ✅ clean (reactive header) | — |

## Приёмка контракта

- **P-фаза завершена** ⇔ строки 1–6 переведены в ✅ (gap закрыт + fail-first-тест) и строки 7–8 отмечены
  ✔ confirmed-intentional (кода нет).
- Строки 9–16 уже ✅ — их голдены (mobile+desktop) не должны поехать от E/O-задач (regression guard).
- Любой НОВЫЙ responsive-файл, добавленный в ходе выносов (напр. `AppOnboardingScaffoldWidget`), наследует
  этот контракт: обе ветки — идентичный набор действий/состояний.
