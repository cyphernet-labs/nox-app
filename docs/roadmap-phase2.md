# Дорожная карта NOX — Фаза 2 (сборка приложения + бэкенд)

> Живой документ для отслеживания фазы 2. Фаза 1 (UI, 17 экранов на мок-данных) **закрыта** — её трекер заархивирован: [`docs/archive/roadmap-phase1.md`](archive/roadmap-phase1.md).
>
> **Фаза 2 — сборка продукта.** Связываем готовые экраны в реальный флоу, добавляем платформенные плагины, l10n, персистентность и (когда выберут протокол) реальный транспорт/сервер.
>
> Создан: 2026-06-25. Источник: независимый аудит реализации (поэкранный DoD-чек 17/17 + инвентарь заглушек + оценка готовности к сборке), реальный код `lib/`, блюпринт `docs/blueprints/mobile/`.

---

## 0. Статус на входе в фазу 2

- ✅ **17/17 экранов реализованы**, мультиплатформенно (мобайл/десктоп, width-driven), на дизайн-токенах. Галерея экранов — 17/17 wired, ноль `Coming soon`.
- ✅ **`make gate` зелёный** (296 тестов). Чат-стек `5.1 → 5.2 → 5.3/5.4` связан реальной навигацией.
- ⚠️ **Хвост DoD фазы 1** (закрыть в начале фазы 2, см. §2): 4 экрана без screen-level golden (`4.1`/`5.1`/`5.2`/`5.4`); 3 настройки без spec-состояния `Inline-error` (`7.2`/`7.3`/`7.4`) — отложено до реального сохранения.
- 🔒 **Бэкенд/протокол не выбран** — блюпринты `04`/`14`/`15`/`16` остаются TBD-плейсхолдерами. Всё, что зависит от сервера (§4), заблокировано; всё остальное (§1–§3) можно делать сейчас на мок-слое.

---

## 1. Иконки приложения — все платформы  ⟵ **ПЕРВЫЙ ПУНКТ**

Обновить лаунчер-иконку приложения на всех целевых платформах (iOS, Android, macOS, Windows, Linux; web вне scope).

**Текущее состояние (по факту):**
- Иконки — **дефолтные флаттеровские** на iOS / Android / macOS / Windows; на Linux иконка не настроена.
- `flutter_launcher_icons` **не подключён** (нет dev-зависимости и конфига).
- **Блокер по исходнику:** единственный логотип в репозитории — `assets/png/logo.png` **200×200**; все копии в дизайн-корпусе (`docs/design/system/.../logo.png`, `logo-reference.png`) — тоже 200×200. Вектора нет. Для лаунчер-иконок нужен мастер **≥1024×1024** (лучше SVG/вектор) — апскейл 200→1024 даст видимое мыло.

**Решения к принятию (до генерации):**
- **Исходный мастер** ≥1024 / вектор — откуда берём (файл от владельца / Figma / др.).
- **Фон и форма:** iOS/macOS требуют **непрозрачную** квадратную иконку (система сама скругляет). Рекомендация — тёмный canvas `#0C2424` (`NoxBrand.canvasDark`, как у splash) под тил-маркой; альтернативы — белый/светлый или бренд-тил (seed).
- **Android adaptive icon:** разделение на `foreground` (марка с safe-zone паддингом) + `background` (сплошной цвет).

**План:**
1. Получить мастер-артворк и зафиксировать фон (см. решения выше).
2. Добавить `flutter_launcher_icons` (dev) + конфиг для `ios`/`android`/`macos`/`windows` (adaptive для Android).
3. Сгенерировать: `dart run flutter_launcher_icons`.
4. **Linux** — `flutter_launcher_icons` его не поддерживает: положить PNG вручную и прокинуть в `linux/` runner (CMake/`.desktop`).
5. Проверка: `mise run build:<platform>:stage` (compile-smoke по 5 таргетам) + визуальная проверка иконок.

---

## 2. Хвост фазы 1 (cleanup перед сборкой)

- [ ] **4 экранных golden** — `4.1` Tab-bar shell, `5.1` Chats list, `5.2` Chat thread, `5.4` Chat card (по DoD: light+dark, `@Tags(['golden'])`).
  > **Заметка о детерминизме (важно):** `get_chats_api.dart:32` и `get_messages_api.dart:40` используют `DateTime.now()`, а лента/список рендерят относительное время (`DateFormatter.relative`) — без фиксации часов golden недетерминирован (вероятная причина, почему попытки забросили: остались `failures/` артефакты для `chats_list`/`shell`). Решение: пинить «now» (инъекция опорной даты) или сид мок-данных под фиксированную дату перед снимком.
- [ ] **Inline-error** (`7.2`/`7.3`/`7.4`) — snackbar `Could not save. Try again.` + строка в `TextConstants`. **Отложено:** сейчас сохранения нет (тема — in-memory, язык/уведомления — session-local), падать нечему. Делаем вместе с персистентностью (§3).

---

## 3. Сборка флоу (без бэкенда — можно делать сейчас)

Роутер **не нужен**: блюпринт `05 §6` канонизирует одно-оконный `Navigator` + `GlobalKey<NavigatorState>` с подменой корневого роута. `AppRoot` уже держит `_navigatorKey`; `flutter_secure_storage` и `shared_preferences` уже в `pubspec`.

1. [x] **Auth/local-state репозиторий** *(Feature-009: `SessionRepository`/`AppStateRepository`/`AuthRepository`; identifier через `flutter_secure_storage`, флаги через `shared_preferences`; общий settings-store — TBD)* — чтение/хранение идентификатора через `flutter_secure_storage` (работает локально и без сервера). Регистрация через injectable DI (как `AppConfigRepository`).
2. [x] **`AppRootState` + bootstrap-фаза** *(Feature-009)* — `AppRootBloc._onInitialize` резолвит сессию (`unauthorized`/`registrationPending`/`authorized`) через подписку на `watchAppState()`; персист темы (сохранённая тема / `_onSetTheme`) — TBD.
3. [x] **Splash — реальная точка входа** *(Feature-009)* (`main.dart`/`AppRoot`); галерея остаётся только как debug-лаунчер (`kDebugMode`-вход из Settings).
4. [x] **Подмена корневого роута** *(Feature-009, `05 §6.1`)*: `BlocListener<AppRootBloc>` → `pushReplacement` (первый переход) / `pushAndRemoveUntil` (последующие) для `Splash → Login` (нет id) / `Splash → Set username` (новый id) / `Splash → TabBarShell` (есть id).
5. [ ] **Онбординг-цепочка реальными роутами** — заменить заглушки `RoutePlaceholderPage` на реальные переходы: `2.1 ↔ 2.2` (round-trip), `2.1 → 2.3` (новый id), `2.3 → 4.1` (успех).
6. [ ] **Персистентность настроек** — тема/язык/уведомления на `shared_preferences`; закрыть `Inline-error` (§2).
7. [ ] **l10n (EN + UK)** — `flutter_localizations` + `l10n.yaml` + `.arb`, миграция `TextConstants`; `LocaleController` для живого переключения языка (`7.4`); `MaterialApp.localizationsDelegates`/`supportedLocales`/`locale`.

---

## 4. Бэкенд (заблокировано выбором протокола)

Подключается после выбора транспорта/сервера. Сейчас весь data-слой мокается.

- [ ] **Транспорт/протокол** — заменить TBD-плейсхолдеры (`04`/`14`/`15`/`16`); токен-источник `api_client`.
- [ ] **Репозитории cache-first** — заменить network-only мок-обёртки реальным транспортом + Sembast cache-first watch + реальная курсорная/поисковая пагинация (`GetMessagesConfig`/`GetChatsConfig`); реализовать `clean()`.
- [ ] **Серверная уникальность / sign-in** — заменить `OnboardingMockData`/`UsernameRules.isTaken` (case-sensitive `Set.contains`) реальными эндпоинтами; добавить клиентскую валидацию формата ID (FR-011).
- [ ] **Реальная отправка** — `SendMessageApi` → реальный POST с серверным id/timestamp; снять оптимистичную симуляцию статусов.

**Мок-API на замену:** `GetChatsApi`, `GetMessagesApi`, `SendMessageApi`, `GetChatFilesApi` (+ верификационный `GetItemsApi`). **Мок-репо:** `ChatRepositoryImpl`, `MessageRepositoryImpl` (+ `ItemRepositoryImpl`). **Мок-identity:** `IdentityMockData` (`currentUserId='me'`), `OnboardingMockData`.

---

## 5. Плагины фазы 2

| Назначение | Пакет | Статус в `pubspec` |
|---|---|---|
| QR-камера / decode (`2.2`) | `mobile_scanner` + `permission_handler` + `app_settings` | `permission_handler` закомментирован; остальных нет |
| Отрисовка QR (identity card) | `qr_flutter` | нет |
| Выбор файла (вложения `5.2`) | `file_picker` | закомментирован |
| Сохранение в Downloads (`5.3`) | `path_provider` / `file_saver` | `path_provider` есть; `file_saver` нет |
| l10n | `flutter_localizations` | нет |
| Хранилище идентификатора / настроек | `flutter_secure_storage` / `shared_preferences` | **есть** (нужна только проводка) |
| Десктоп-чром окна (опц.) | `window_manager` | нет |
| Push (mobile-only) | `firebase_core` / `firebase_messaging` | закомментированы |

**No-op действия на замену плагинами:** attach-picker (synth `photo.jpg`), download/save (fake progress + snackbar), QR torch/switch/permission/decode, fake-QR `_FakeQrPainter`, logout local-wipe, copy-ID (mock id), notifications open-settings.

---

## 6. Как обновлять

- Чекбоксы `[ ]`/`[~]`/`[x]` по факту работы.
- Закрытые решения по иконкам (§1) — фиксируем здесь же.
- Новые направления фазы 2 — добавляем разделом.
