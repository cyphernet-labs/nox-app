# Feature Specification: Auth token + apiUrl seam (S5)

**Feature Branch**: `019-auth-apiurl-seam`

**Created**: 2026-07-26

**Status**: Draft

**Input**: User description: S5 — `AppConfig.apiUrl`, `getUserAuthIdToken`, `ApiClient` auth-interceptor, `401→logout(forced)`. Mock/TBD-плейсхолдер, реальный бэкенд-контракт не изобретаем.

## Контекст и цель

NOX сознательно **не выбрал** транспорт/протокол/сервер. Сегодня транспортный seam **фактически отсутствует**: `ApiClient` — голый `Dio` без baseUrl/interceptor и **никуда не инъектится**; в `AppConfig` нет `apiUrl`; нет источника токена; `AuthRepository.logout(forced:)` существует, но **401-триггер отложен** (док-коммент: «401 trigger deferred»).

Задача — сформировать **auth/transport seam** так, чтобы интеграция бэкенда стала локализованной: (1) `AppConfig` несёт `apiUrl` (nullable TBD-плейсхолдер), (2) `AppConfigRepository` отдаёт токен (`getUserAuthIdToken`) + флаг тест-окружения, (3) `ApiClient` умеет `initBase()` + auth-interceptor, который прикрепляет токен и на **401** дёргает `authRepository.logout(forced:true)`. Всё **инертно** без реального `apiUrl` (реальных запросов в UI-фазе нет), но клиентское поведение (attach-token, 401→logout) — настоящее и покрыто тестами против синтетического 401. Формы `apiUrl`/токена — **example/TBD**, заменяются реальным контрактом при выборе бэкенда (зеркалит блюпринты 14/15/16).

**«Пользователь» фичи — разработчик/будущая интеграция бэкенда**; у фичи нет user-facing поведения (0 изменений UI), кроме one-shot `sessionExpired`-флага, который УЖЕ существует и УЖЕ ведёт на Login при forced-logout (S5 лишь добавляет 401 как ещё один триггер того же пути).

## Clarifications

### Session 2026-07-26

- Q: Откуда `getUserAuthIdToken` берёт токен в mock-фазе? → A: **Из `flutter_secure_storage` рядом с identifier (feature 009), ключ `auth_id_token`.** Реального sign-in, пишущего токен, ещё нет → метод возвращает `null` (TBD-плейсхолдер); плумбинг существует, значение появится с реальным бэкендом. Секьюр-стор уже в проекте.
- Q: Как избежать циклической DI (ApiClient→interceptor→AuthRepository, а AuthRepository→Chat/Message-репо)? → A: **Ленивое разрешение `AuthRepository` в момент 401** (через `getIt`/top-level alias `authRepository`), а не constructor-инъекция в interceptor. Разрывает потенциальный цикл и совпадает с существующим паттерном `global_aliases`.
- Q: Заворачивать ли `initBase()`/interceptor в реальные запросы сейчас? → A: **Нет — инертно.** `apiUrl == null` (TBD) → `initBase()` не ставит baseUrl (или ставит пустой), реальных вызовов нет; interceptor существует и тестируется прямым вызовом `onRequest`/`onError` с синтетическим 401. `ApiClient` остаётся не-инъектируемым в data-source'ы (моки его не используют) — это фиксируется как TBD до выбора бэкенда.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — `AppConfig` несёт apiUrl + контракт токена (Priority: P1)

`AppConfig` получает nullable `apiUrl`; `AppConfigRepository` — `getUserAuthIdToken()` (читает `auth_id_token` из secure storage, сейчас `null`) и `isTestEnvironment`.

**Why this priority**: Фундамент — без места под `apiUrl`/токен interceptor нечего прикреплять и некуда целиться.

**Independent Test**: `AppConfigRepository.initialize(flavor)` → `config.apiUrl` == TBD-значение (null по умолчанию); `getUserAuthIdToken()` → `null` без записанного токена, и == записанное значение, если положить `auth_id_token` в secure storage.

**Acceptance Scenarios**:

1. **Given** инициализированный `AppConfigRepository`, **When** читают `config.apiUrl`, **Then** возвращается TBD-плейсхолдер (`null` — реальный запрос без него не строится).
2. **Given** пустой secure storage, **When** `getUserAuthIdToken()`, **Then** `null` (нет токена в mock-фазе).
3. **Given** записанный `auth_id_token`, **When** `getUserAuthIdToken()`, **Then** это значение (плумбинг работает end-to-end).

---

### User Story 2 — `ApiClient` auth-interceptor прикрепляет токен (Priority: P1)

`ApiClient.initBase()` конфигурирует baseUrl из `apiUrl` (если задан) и ставит auth-interceptor, который на каждом запросе прикрепляет `Authorization: Bearer <token>`, если `getUserAuthIdToken()` вернул непустой токен; иначе заголовок не ставится.

**Why this priority**: Основное клиентское поведение auth-seam'а; проверяемо без сервера (прямой вызов `onRequest`).

**Independent Test**: С замоканным токеном interceptor.`onRequest` добавляет `Authorization`-заголовок; без токена (`null`) — не добавляет.

**Acceptance Scenarios**:

1. **Given** `getUserAuthIdToken()` → `'abc'`, **When** interceptor обрабатывает запрос, **Then** в заголовках `Authorization: Bearer abc`.
2. **Given** `getUserAuthIdToken()` → `null`, **When** interceptor обрабатывает запрос, **Then** заголовка `Authorization` нет (аноним/до-sign-in).
3. **Given** `apiUrl == null` (TBD), **When** `initBase()`, **Then** baseUrl не задан (или пуст) — реальные запросы не строятся, но interceptor уже установлен.

---

### User Story 3 — 401 → forced logout (Priority: P1)

Auth-interceptor на ответе со статусом **401** дёргает `authRepository.logout(forced:true)` (лениво разрешая `AuthRepository`), после чего пробрасывает ошибку дальше. Это замыкает существующий forced-logout-путь (спина → `sessionExpired` → Login).

**Why this priority**: Ключевая цель S5 — закрыть отложенный «401 trigger». Проверяемо синтетическим 401 против мок-`AuthRepository`.

**Independent Test**: interceptor.`onError` с `DioException`(response 401) вызывает `logout(forced:true)` ровно один раз; не-401 (напр. 500) — не вызывает.

**Acceptance Scenarios**:

1. **Given** `DioException` с `response.statusCode == 401`, **When** interceptor.`onError`, **Then** `authRepository.logout(forced:true)` вызван один раз, ошибка проброшена (`handler.next`/`reject`).
2. **Given** `DioException` с 500 (или без response), **When** interceptor.`onError`, **Then** `logout` НЕ вызван, ошибка проброшена без изменений.
3. **Given** 401 во время уже идущего logout, **When** повторный 401, **Then** повторный `logout(forced:true)` идемпотентен (forced-logout — full wipe; повторный вызов на уже-очищенной сессии безопасен — существующее поведение).

---

### Edge Cases

- **`apiUrl == null`** — `initBase()` инертен (baseUrl не задаётся), приложение работает на локальной Sembast-БД как прежде; interceptor установлен, но без реальных запросов не срабатывает.
- **Пустой/whitespace токен** — трактуется как отсутствие (`Authorization` не ставится).
- **401 без тела/without response** — только `statusCode == 401` триггерит logout; `type == connectionError` и пр. — нет.
- **Циклическая DI** — interceptor разрешает `AuthRepository` лениво (в момент 401), не в конструкторе.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: `AppConfig` MUST нести `apiUrl` (nullable) — TBD-плейсхолдер; при `null` реальный запрос не строится.
- **FR-002**: `AppConfigRepository` MUST предоставлять `getUserAuthIdToken()` (читает `auth_id_token` из `flutter_secure_storage`, `null` при отсутствии) и `isTestEnvironment`.
- **FR-003**: `ApiClient` MUST иметь `initBase()`, задающий baseUrl из `apiUrl` (если непуст) и устанавливающий auth-interceptor **идемпотентно** (повторный `initBase()` не дублирует interceptor).
- **FR-004**: Auth-interceptor MUST на `onRequest` прикреплять `Authorization: Bearer <token>` при непустом токене; при `null`/пустом — не ставить заголовок.
- **FR-005**: Auth-interceptor MUST на `onError` при `response.statusCode == 401` вызвать `authRepository.logout(forced:true)` (лениво разрешая `AuthRepository`) ровно один раз и пробросить ошибку; при не-401 — не трогать logout.
- **FR-006**: 401→logout MUST переиспользовать существующий forced-logout-путь (никакой новой навигации/UI — спина уже ведёт на Login по `sessionExpired`).
- **FR-007**: Всё MUST быть инертно без реального `apiUrl` (0 реальных сетевых вызовов в UI-фазе); `ApiClient` не обязателен к инъекции в data-source'ы (моки его не используют) — TBD до бэкенда.
- **FR-008**: Формы `apiUrl`/токена/заголовка MUST быть документированы как example/**TBD**, заменяемые реальным контрактом; existing поведение (мок-репо, Sembast, UI/BLoC) не меняется.

### Key Entities *(include if feature involves data)*

- **AppConfig** *(существует)* — flavor + **новый** nullable `apiUrl`.
- **AppConfigRepository** *(существует)* — + `getUserAuthIdToken()` + `isTestEnvironment`.
- **ApiClient** *(существует, голый Dio)* — + `initBase()` + auth-interceptor.
- **AuthInterceptor** *(новый)* — Dio `Interceptor`: attach-token (onRequest) + 401→forced-logout (onError).
- **AuthRepository** *(существует)* — `logout(forced:true)` — цель 401-триггера (закрывает «401 trigger deferred»).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: `getUserAuthIdToken()` возвращает `null` без токена и записанное значение с ним — плумбинг проверяем end-to-end.
- **SC-002**: interceptor прикрепляет `Authorization` при токене и не прикрепляет при `null` — 2 покрытых ветки.
- **SC-003**: 401 → `logout(forced:true)` ровно раз; не-401 → 0 вызовов — обе ветки покрыты синтетическим `DioException`.
- **SC-004**: `apiUrl == null` → 0 реальных запросов, приложение работает как прежде (существующая suite без правок).
- **SC-005**: 0 изменений UI, 0 новых голденов; `make gate` + `make golden-verify` зелёные.
- **SC-006**: Флип-на-бэкенд — задать реальный `apiUrl` + записывать токен на sign-in + (при необходимости) инъектить `ApiClient` в data-source'ы; репо/DAO/мапперы/UI не трогаются — задокументировано.

## Assumptions

- Токен-ключ `auth_id_token` в `flutter_secure_storage` (рядом с identifier, feature 009); `MacOsOptions(usesDataProtectionKeychain:false)` как у identifier (совместимость keychain, feature 009).
- `apiUrl` по умолчанию `null` (TBD); per-flavor реальный URL появится с бэкендом (config/<flavor>.json уже есть, но `apiUrl` туда не кладём в этой фиче — только плумбинг в `AppConfig`).
- `Authorization: Bearer <token>` — example-схема (заменяемо HMAC/иным при выборе протокола).
- `isTestEnvironment` выводится из flavor/`Environment` (для будущего обхода auth в тестах).

## Out of Scope

- Реальный транспорт/сервер, реальный sign-in, пишущий токен, реальные endpoints/DTO (S4 закрыл конверт для read-боундери; wire-контракт — TBD).
- Инъекция `ApiClient` в data-source'ы и перевод моков на реальные запросы (флип-на-бэкенд).
- HMAC/security-заголовки, refresh-токены, retry-на-401 (только logout).
- Изменение UI/BLoC/навигации (401 переиспользует существующий forced-logout-путь).
