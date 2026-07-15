# Contract: Onboarding navigation (app-state spine)

Заменяем `RoutePlaceholderPage`-заглушки реальной навигацией через существующий app-state spine (фича 009): `AppRoot` слушает `AppStateRepository` и подменяет корневой роут.

| Переход | Триггер | Механизм |
|---|---|---|
| `2.1 Login → 2.3 Set username` | вход с новым (незарегистрированным) id (`LoginStatus.navNewId`) | BLoC/репозиторий переводит app-state в `registrationPending` → `AppRoot` swap на `SetUsernamePage`. Убрать `RoutePlaceholderPage.push` |
| `2.1 Login → 4.1 Shell` | вход с зарегистрированным id (`LoginStatus.navRegistered`) | app-state → `authorized` → `AppRoot` swap на `TabBarShell`. Убрать `RoutePlaceholderPage.push` |
| `2.3 Set username → 4.1 Shell` | завершение/Skip (`UsernameStatus.navSuccess`) | app-state → `authorized` → `AppRoot` swap на `TabBarShell`. Убрать `RoutePlaceholderPage.push` |
| `2.1 ↔ 2.2 QR` | Scan QR / назад | push/pop `QrScanPage` внутри Login; результат id → sign-in путь (010, уже работает) |

Вне scope: `create_chat_page` (→ chat thread dev-переход) и `splash_page` (gallery standalone) `RoutePlaceholderPage` — не трогаем.

## Acceptance

- FR-007..FR-010, SC-002/SC-003. Проверка: онбординг-флоу без заглушек; возврат с QR сохраняет id.
