# Contract: паритет-матрица responsive-экранов

**Phase 1.** Контракт для SC-005: по каждому responsive-файлу (`_narrow`/`_wide` развилка) — требуемый паритет
действий/аффордансов/состояний и текущий статус. Приёмка фазы P ⇔ все строки `gap` закрыты (либо ✅ clean,
либо ✔ confirmed-intentional).

| # | Файл (responsive) | Паритет-контракт (что MUST быть на обеих ветках) | Текущий статус | Задача |
|---|---|---|---|---|
| 1 | `error_page.dart` | `ErrorPageMode` соблюдается на ОБЕИХ: blocking → неотменяем; embedded → back | ✅ clean (T002: `_wide` ветвится по `_mode`, blocking→PopScope, embedded→back) | R1 |
| 2 | `app_message_bubble_widget.dart` | own/other «коридор» (max-width от локальной панели) на обеих | ✅ clean (T003: `LayoutBuilder` → локальная ширина; narrow-pane golden) | R2 |
| 3 | `tab_bar_shell_widget.dart` | заголовок/подпись активного таба, локализованные, на обеих | ✅ clean (T004: subtitle per-tab через `context.l10n`; Settings-golden) | R3 |
| 4 | `app_navigation_rail_widget.dart` | a11y-роль (button+selected) на пунктах навигации на обеих | ✅ clean (T005: `Semantics(button,selected,label)` как у bottom bar) | R4 |
| 5 | `create_chat_page.dart` | блокировка отмены во время submit на обеих | ✅ clean (T006: mobile `PopScope(canPop:!submitting)` + back disabled) | R5 |
| 6 | `chats_list_page.dart` | hairline под header списка на обеих | ✔ intentional (T007: сверено — desktop `ChatsListPane` без hairline на pane-header; бренд-hairline живёт под window-titlebar, mobile — под AppBar; Принцип IV) | R6 |
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

- **P-фаза завершена** ⇔ строки 1–5 переведены в ✅ (gap закрыт + fail-first-тест) и строки 6–8 отмечены
  ✔ confirmed-intentional (кода нет). R6 переклассифицирован в ✔ по итогам сверки с корпусом: `desktop-screens.jsx`
  `ChatsListPane` рисует pane-header БЕЗ hairline (бренд-hairline — на уровне window-strip), так что текущий
  desktop уже соответствует дизайну; добавление hairline было бы дивергенцией (Принцип IV).
- Строки 9–16 уже ✅ — их голдены (mobile+desktop) не должны поехать от E/O-задач (regression guard).
- Любой НОВЫЙ responsive-файл, добавленный в ходе выносов (напр. `AppOnboardingScaffoldWidget`), наследует
  этот контракт: обе ветки — идентичный набор действий/состояний.
