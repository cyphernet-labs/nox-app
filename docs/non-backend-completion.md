# NOX — доводка ВСЕЙ реализации, не зависящей от бэкенда (трекер фазы 2)

> **Живой трекинг-документ.** Продолжение `mock-completion-plan.md` (тот бэклог 100% закрыт). Цель: закрыть **абсолютно всё**, что реализуемо **без бэкенда** — реальные device/local-API вместо мок-заглушек, недостающие голдены/тесты (DoD-хвост + 3-golden-categories), доделанные scoped-out ветки, seam-полиш. Составлен 2026-07-26 исчерпывающим многоагентным аудитом кодовой базы (`wf_778e24f6`).
>
> Идём по приоритету P1→P17, по одной задаче. Ритм на каждую: реализация → `make gate` + `make golden-verify` → мультиагентное adversarial-ревью → фикс всех находок → merge `--no-ff` в `develop` (**никогда не push**) → флип статуса + журнал. Крупные (**SpecKit**) — полный Spec Kit. Мелкие (**точечно**) — обычный фич-бранч.

## Бэклог (doable без бэкенда)

| P | ID | Задача | Eff. | Режим | Статус |
|:--:|----|--------|:--:|:---:|:--:|
| 1 | connectivity-thread-card | Реальный `ConnectivityService` в `ChatThreadBloc`+`ChatCardBloc` (F3 parity — сейчас offline-баннер только в списке) | M | точечно | ☑ |
| 2 | composer-draft-thumbnail | Миниатюра image для draft-вложения в композере (не только в отправленных бабблах) | S | точечно | ☑ |
| 3 | inline-error-thread-golden | DoD-хвост: page-golden `Inline-error` (тред, send-error состояние) | S | точечно | ☐ |
| 4 | fileview-skip-timer-local-path | 5.3 File-view: при наличии `localPath` пропустить мок-таймер «download», Save сразу активен | S | точечно | ☐ |
| 5 | notifications-permission-service | Реальный OS-запрос permission уведомлений + `openAppSettings()` (device API, `permission_handler` уже есть) | M | **SpecKit** | ☐ |
| 6 | s4-sendmessage-wire-envelope | `sendMessage` через `ResponseEntity<MessageWireEntity>` (S4-seam полиш, behavior-neutral) | S | точечно | ☐ |
| 7 | heic-thumbnail-platform-aware | HEIC-миниатюры на iOS/macOS (platform-aware, а не глобальное исключение) | S | точечно | ☐ |
| 8 | image-viewer-page-goldens | Голдены `ImageViewerPage` (page-mobile + page-desktop) — 3-golden-categories | M | точечно | ☐ |
| 9 | app-image-attachment-widget-golden | Widget-golden `AppImageAttachmentWidget` (миниатюра + fallback) | S | точечно | ☐ |
| 10 | scenario-goldens-thread-card | Голдены уже-реализованных debug-сценариев треда/карточки (offline/empty/fatal/grid) | M | точечно | ☐ |
| 11 | notice-strip-widget-golden | Widget-golden `AppNoticeStripWidget` (offline/notice-баннер) | S | точечно | ☐ |
| 12 | remaining-appwidget-goldens | Widget-голдены остальных state-bearing `App*Widget` (theme-option/switch-row/logout-dialog/…) | M | точечно | ☐ |
| 14 | desktop-qr-image-decode | Windows/Linux: выбор QR-картинки + локальный декод → тот же sign-in (опц. parity) | M | **SpecKit** | ☐ |
| 15 | desktop-native-window-chrome | Нативный desktop window chrome (`window_manager`: min/max/close, draggable, frameless splash) | L | **SpecKit** | ☐ |
| 17 | linux-packaging | Linux-пакетирование (.deb/AppImage/flatpak + .desktop menu-интеграция) | M | точечно | ☐ |

## Заблокировано НЕ бэкендом, а внешним деливери (не могу породить сам)

- **P13 · terms-real-copy** — реальный юридический текст Terms 7.6 (сейчас placeholder). Не сеть, но нужен **контент от продукта/юриста**. ⏸ до текста.
- **P16 · icon-debt-monochrome-master** — crisp 512/1024 мастер + Android `<monochrome>` themed-icon слой. Не сеть, но нужен **финальный прозрачный векторный логотип** (design-деливери). ⏸ до вектора.

## Реально backend-gated (TBD до выбора бэкенда — НЕ в scope этой фазы)

- Реальный sign-in / auth / issuance токена (`AuthRepositoryImpl.signIn` — заглушка по членству в `OnboardingMockData.registeredIds`).
- Флип моков на реальные запросы (`AppConfig.apiUrl` = null TBD; `ApiClient` не инъектится ни в один data-source; Bearer/HMAC — example).
- Авторитетная **глобальная** уникальность (username / chat name / label) — кросс-юзерная проверка на сервере.
- Реальный ack отправки + подлинный inbound/push (сейчас `SendMessageApi` эхо `srv_<uuid>`; `simulateIncoming` — debug-фабрикация).
- Реальный сетевой **download** байтов файла (5.3 для no-`localPath` вложений).
- Достижимость реальных **сетевых error-состояний** (моки над Sembast не падают → `RepositoryException` members не производятся в реальном флоу).

## Журнал

_(строка на закрытую задачу: `P# id — дата — merge — примечание`)_

- **P2 composer-draft-thumbnail — 2026-07-26 — merge (develop).** Draft-вложение в композере: декодируемое image рендерит компактную removable-миниатюру (тот же `canRender`/`localPath`, что и sent-bubble), прочие типы — чип. `AppImageAttachmentWidget` получил override размера + `onRemove`-×. Ревью: 4 находки исправлены (a11y tap-target ≥48 / dark-контраст через inverseSurface-пару / размер иконки / покрытие). Голдены не тронуты. Гейт: 688 тестов.
- **P1 connectivity-thread-card — 2026-07-26 — merge `5310fe5`.** Реальная device-connectivity ведёт offline-баннер в треде (5.2) и карточке (5.4), не только в списке (F3 parity). Оба блока подписаны на `ConnectivityService.watchOnline()` → `ConnectivityChanged` флипает `isOffline` in-place; тред дополнительно ставит real-offline отправки в `pending` и передоставляет их на reconnect. Adversarial-ревью: 2 бага исправлены — (1) LOW debug-only: `_onSetScenario`-redeliver фаярил на любой выход из offline (empty/fatal тоже) → заскоуплен на `scenario==normal`; (2) MEDIUM dev/prod: несериализованный `_onConnectivityChanged` мог дважды передоставить при флаппинге → `transformer: sequential()` (передоставка ровно раз). Test-env always-online → существующие тесты/голдены не тронуты. Гейт: 687 тестов + 152 голдена.
