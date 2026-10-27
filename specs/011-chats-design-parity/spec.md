# Feature Specification: Chats list — сверка с дизайном и golden-покрытие (mobile + desktop)

**Feature Branch**: `011-chats-design-parity`

**Created**: 2026-06-27

**Status**: Draft

**Input**: User description: "Проверить экраны Chats list на соответствие дизайну — отдельно для мобилки и десктопа; после правок закрыть весь функционал экранов golden-тестами (и mobile, и desktop). Дизайны: `NOX - Desktop.html` и `NOX - Mobile.html` (claude_design project `d9e022e3-07fb-4fae-9147-226210933448`). Для десктопа добавить иконку пользователя в нижнем-левом углу: первые буквы имени и фамилии (или одна буква для одного слова), по нажатию — переход в настройки аккаунта."

## Контекст

Задача — **аудит соответствия дизайну** уже реализованного экрана **5.1 Chats list** (`lib/presentation/pages/chats_list_page/chats_list_page.dart`) против двух авторитетных макетов:

- **mobile** (узкая ветка `_narrow`) → `NOX - Mobile.html`;
- **desktop** (широкая ветка `_wide`, list-detail) → `NOX - Desktop.html`.

NOX — это **одно** приложение для mobile и desktop, поэтому экран должен быть сверен и приведён в соответствие **в обеих** ветках (parity-правило: правка не считается завершённой, пока десктопная `_wide`-ветка не совпадает с десктопным макетом так же, как мобильная — с мобильным). Экран host-ится shell-ом (`TabBarShell`): на узком окне — `AppBottomBarWidget` + докнутый `+` FAB; на широком — `AppNavigationRailWidget` (rail) + window-titlebar.

Новое поведение в этой фиче — **аккаунт-аватар в десктопном rail** (нижний-левый угол), которого сейчас нет. После приведения экрана к дизайну весь его функционал должен быть зафиксирован golden-тестами в **двух** категориях: **page — mobile** и **page — desktop**.

## Clarifications

### Session 2026-06-27

- Q: Куда ведёт нажатие на аккаунт-аватар в desktop-rail? → A: Переключить активный destination shell-а на `Settings` **и** приземлиться на секцию `Account` (показывает `Your ID` / username / `Show QR`) — отдельного profile-экрана не вводим.
- Q: Как выводить инициалы из NOX-label (charset `[A-Za-z0-9._-]`, без пробелов)? → A: Токенизация по пробелам и разделителям `.` `_` `-`; первая заглавная буква первого и последнего токена (2 буквы), один токен → одна буква (`john.doe`→`JD`, `User7421`→`U`).
- Q: Визуальный стиль аккаунт-аватара? → A: Переиспользовать генерацию `AppAvatarWidget` — инициалы + цвет по хэшу из фиксированной палитры (консистентно с аватарами чатов).

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Chats list соответствует мобильному дизайну (Priority: P1)

Пользователь на узком экране (iOS / Android / узкое окно) открывает вкладку Chats и видит экран ровно таким, как в `NOX - Mobile.html`: AppBar с wordmark `NOX` и брендовым spectrum-hairline под ним, постоянное поле `Search`, прокручиваемый список строк чатов (аватар с кольцом + имя + превью последнего сообщения + относительное время + бейдж непрочитанных), снизу — bottom bar (`Chats` / докнутый `+` FAB / `Settings`). Светлая и тёмная темы совпадают с макетом.

**Why this priority**: Это основной экран приложения и первая из двух платформенных вёрсток; без его соответствия дизайну фича не имеет ценности.

**Independent Test**: Запустить приложение на узкой поверхности (360–420 dp), открыть Chats, визуально сверить каждое состояние (`filled`, `loading`, `empty`, `offline`, `inline-error`, `search`, `search-empty`) со светлым и тёмным `NOX - Mobile.html`.

**Acceptance Scenarios**:

1. **Given** узкое окно и непустой список чатов, **When** открыт экран Chats, **Then** показаны wordmark `NOX`, spectrum-hairline, поле `Search`, список строк и bottom bar с докнутым `+` — раскладка и отступы совпадают с `NOX - Mobile.html`.
2. **Given** строка с непрочитанными сообщениями, **When** она отрендерена, **Then** имя имеет усиленный вес, превью — `onSurface`, время — акцентный (`primary`) цвет, бейдж виден (`99+` как потолок); прочитанная строка — приглушённая, без бейджа.
3. **Given** пустой список, **When** экран загружен, **Then** показан empty-state (`No chats yet` / `Tap + to create the first one.`) как в макете.
4. **Given** оффлайн или ошибка загрузки, **When** экран загружен, **Then** показан соответствующий баннер (`No connection` / `Could not load chats. Pull to refresh.`).

---

### User Story 2 — Chats list соответствует десктопному дизайну (Priority: P1)

Пользователь на широком окне (Windows / Linux / macOS / широкое окно) видит two-pane list-detail ровно как в `NOX - Desktop.html`: window-titlebar (wordmark `NOX` + субтитул `· Chats` + brand-hairline), слева — navigation rail (`+` FAB как leading, `Chats`, `Settings`), панель списка (заголовок `Chats` + `Search` + строки), справа — detail-панель с no-selection empty-state (`Select a chat` / `Choose a conversation on the left, or press + to start a new one.`). Светлая и тёмная темы совпадают с макетом.

**Why this priority**: Вторая обязательная платформенная вёрстка (multi-platform parity); десктоп — целевая платформа, и его раскладка не достигается на мобильной поверхности.

**Independent Test**: Запустить приложение на широкой поверхности (≥ 1280 dp), открыть Chats, сверить состояния (`filled`/`selected`, `no-selection`, `loading`, `offline`, `search`, `search-empty`) со светлым и тёмным `NOX - Desktop.html`.

**Acceptance Scenarios**:

1. **Given** широкое окно без выбранного чата, **When** открыт экран Chats, **Then** показаны titlebar `NOX · Chats`, rail, панель списка с заголовком `Chats` и поиском, и detail-панель с empty-state `Select a chat` — совпадает с `NOX - Desktop.html`.
2. **Given** широкое окно, **When** выбрана строка чата, **Then** строка подсвечена inset-пилюлей (`secondaryContainer`), а в detail-панели загружается тред **без navigation push** (parity сохранена).
3. **Given** светлая и тёмная темы, **When** экран отрендерен на широкой поверхности, **Then** обе темы визуально совпадают с соответствующими вариантами макета.

---

### User Story 3 — Аккаунт-аватар в десктопном rail (Priority: P2)

На широком окне в нижнем-левом углу navigation rail пользователь видит аватар своего аккаунта с инициалами (в стиле сгенерированных аватаров чатов — инициалы + цвет по хэшу). По нажатию открываются настройки аккаунта: активный destination переключается на `Settings` с приземлением на секцию `Account` (`Your ID` / username / `Show QR`). Инициалы выводятся из отображаемого имени (label): первая буква первого и последнего токена (две буквы), либо одна буква, если токен один.

**Why this priority**: Единственное чисто новое поведение фичи; ценно как desktop-аффорданс быстрого доступа к аккаунту, но вторично по отношению к самому соответствию экрана дизайну.

**Independent Test**: На широкой поверхности проверить, что аватар закреплён внизу rail, показывает корректные инициалы для одно- и многословного label, и нажатие переключает активный destination на `Settings`. На узкой поверхности аватара нет.

**Acceptance Scenarios**:

1. **Given** широкое окно и label из одного токена (например `User7421`), **When** rail отрендерен, **Then** аватар внизу-слева показывает одну заглавную букву (`U`).
2. **Given** широкое окно и label из нескольких токенов (например `john.doe`), **When** rail отрендерен, **Then** аватар показывает две заглавные буквы первого и последнего токена (`JD`).
3. **Given** широкое окно, **When** пользователь нажимает аватар, **Then** активный destination shell-а переключается на `Settings` и выбрана секция `Account` (`Your ID` / username / `Show QR`) — без отдельного push-экрана профиля.
4. **Given** узкое окно (bottom bar), **When** shell отрендерен, **Then** аккаунт-аватар не показывается.

---

### User Story 4 — Golden-фиксация функционала экрана (mobile + desktop) (Priority: P2)

Сопровождающий имеет golden-покрытие, фиксирующее визуальный вид всех состояний экрана Chats в **обеих** вёрстках, чтобы любая будущая регрессия ловилась локальным гейтом. Покрытие добавляется **после** правок US1–US3 (это финальный обязательный шаг приёмки, несмотря на приоритет P2 — он зависит от завершённости US1–US3).

**Why this priority**: Это страховочная сеть поверх приведённого к дизайну экрана; требует, чтобы US1–US3 были сделаны раньше, поэтому идёт последней, но является обязательным критерием готовности.

**Independent Test**: Прогнать `make golden-verify` — все новые/обновлённые baseline проходят; намеренная визуальная регрессия (например, сдвиг отступа) ловится тестом; `make gate` остаётся зелёным.

**Acceptance Scenarios**:

1. **Given** приведённый к дизайну экран, **When** добавлены golden-тесты, **Then** существует **page — mobile** golden-покрытие (`goldenTest`, поверхность 360, light + dark) для `ChatsListPage`.
2. **Given** приведённый к дизайну экран, **When** добавлены golden-тесты, **Then** существует **page — desktop** golden-покрытие (`goldenTestDesktop`, поверхность 1280×800, light + dark) для `ChatsListPage`.
3. **Given** все ключевые состояния экрана, **When** прогоняется `make golden-verify`, **Then** baseline покрывают `filled`, `empty`, `loading`, `offline`, `inline-error`, `search`/`search-empty`, а на desktop дополнительно `no-selection` и `selected` detail-панель.
4. **Given** новый аккаунт-аватар, **When** добавлены golden-тесты, **Then** он зафиксирован golden-baseline (на уровне widget и/или page).

---

### Edge Cases

- **Длинное имя/превью чата** — усечение многоточием (`ellipsis`), без переноса и наезда на время/бейдж.
- **Непрочитанные > 99** — бейдж показывает `99+`; ровно `0` — бейдж скрыт.
- **Label для инициалов с разделителями** — токенизация по пробелам и разделителям `.`, `_`, `-`; пустой/только-разделители label → нейтральный fallback (одна буква по умолчанию, без пустого аватара).
- **Выбранный чат выпал из списка** (например, отфильтрован поиском) на desktop → detail-панель возвращается к no-selection empty-state, а не показывает устаревший тред.
- **Полоса ширины 840–rail** — shell передаёт решение раскладки вниз (`forceWide`), тело не должно «промахиваться» мимо нужной ветки.
- **Аватар на платформе без сессии/label** — деградирует до fallback-инициала, без краша.

## Requirements *(mandatory)*

### Functional Requirements

#### Соответствие дизайну — mobile (`_narrow`)

- **FR-001**: Узкая вёрстка экрана Chats MUST совпадать с `NOX - Mobile.html` в light и dark: AppBar c wordmark `NOX`, brand spectrum-hairline под ним, постоянное поле `Search`, прокручиваемый список строк, bottom bar (`Chats` / докнутый `+` FAB / `Settings`).
- **FR-002**: Строка чата MUST рендерить сгенерированный аватар (с тонким кольцом, инициалы + цвет по хэшу), имя, превью последнего сообщения, относительное время и бейдж непрочитанных.
- **FR-003**: Акцент непрочитанных MUST следовать дизайну: имя — усиленный вес, превью — `onSurface`, время — `primary`, бейдж виден; потолок бейджа `99+`, при `0` скрыт. Прочитанная строка — приглушённая (время/превью `onSurfaceVariant`, без бейджа).
- **FR-004**: Состояния `loading`, `empty`, `offline`, `inline-error`, `search`, `search-empty` MUST совпадать с дизайном по раскладке и по EN-микрокопи (`No chats yet` / `Tap + to create the first one.`, `No connection`, `Could not load chats. Pull to refresh.`, `No chats found`).

#### Соответствие дизайну — desktop (`_wide`)

- **FR-005**: Широкая вёрстка экрана Chats MUST совпадать с `NOX - Desktop.html` в light и dark: window-titlebar (`NOX` + субтитул `· Chats` + brand-hairline), navigation rail (leading `+` FAB, `Chats`, `Settings`), панель списка (заголовок `Chats` + `Search` + строки), detail-панель.
- **FR-006**: No-selection detail-панель MUST показывать empty-state с иллюстрацией и копи `Select a chat` / `Choose a conversation on the left, or press + to start a new one.`
- **FR-007**: Выбранная строка на desktop MUST подсвечиваться inset-пилюлей (`secondaryContainer`), а тред MUST загружаться в detail-панель **без navigation push** (сохранить текущее list-detail поведение).

#### Аккаунт-аватар в desktop rail (новое)

- **FR-008**: Navigation rail (широкая вёрстка) MUST показывать аккаунт-аватар, закреплённый в нижней части rail (нижний-левый угол окна), в визуальном стиле сгенерированных аватаров чатов (`AppAvatarWidget`: инициалы + цвет по хэшу из фиксированной палитры).
- **FR-009**: Аватар MUST выводить инициалы из отображаемого label: токенизация по пробелам и разделителям `.` `_` `-`; первая заглавная буква первого и последнего токена (две буквы); label из одного токена → одна буква; пустой/деградированный label → нейтральный fallback-инициал.
- **FR-010**: Нажатие на аватар MUST переключать активный destination shell-а на `Settings` **и** приземлять на секцию `Account` (`Your ID` / username / `Show QR`); отдельный profile/account-экран НЕ вводится.
- **FR-011**: Аккаунт-аватар MUST присутствовать только в широкой (rail) вёрстке; в узкой (bottom bar) вёрстке его быть не должно. — **SUPERSEDED (N4, owner-override 2026-07-25):** узкая вёрстка теперь ТОЖЕ несёт аккаунт-аватар — в app-bar списка чатов (не в bottom bar), тап → `Settings`/`Account` (тот же `jumpToAccount`, что и у rail). Bottom bar по-прежнему без аватара; FR-010 (тап → Settings/Account) сохраняется на обеих ширинах.

#### Поведенческая parity (сохранить)

- **FR-012**: Тап по строке MUST на mobile открывать тред push-ом (5.2), на desktop — выбирать строку и загружать тред в панель без push.
- **FR-013**: `+` (FAB на mobile / leading в rail на desktop) MUST открывать Create chat (6.1); поле `Search` MUST фильтровать список вживую, при отсутствии совпадений — `No chats found`.

#### Golden-покрытие

- **FR-014**: `ChatsListPage` MUST иметь **page — mobile** golden-покрытие (`goldenTest`, поверхность 360, light + dark).
- **FR-015**: `ChatsListPage` MUST иметь **page — desktop** golden-покрытие (`goldenTestDesktop`, поверхность 1280×800, dpr 2, light + dark).
- **FR-016**: Golden-покрытие MUST охватывать функциональные состояния экрана (`filled`, `empty`, `loading`, `offline`, `inline-error`, `search`/`search-empty`) и на desktop дополнительно `no-selection` + `selected` detail-панель.
- **FR-017**: Аккаунт-аватар MUST быть зафиксирован golden-baseline (widget и/или page уровень).
- **FR-018**: Все новые/обновлённые golden-baseline MUST проходить `make golden-verify`, а `make gate` MUST оставаться зелёным. Файлы тестов MUST следовать проектным правилам именования/тегирования (`*_golden_test.dart` + `@Tags(['golden'])`).

### Key Entities *(include if feature involves data)*

- **Chat row (строка чата)**: имя чата, превью последнего сообщения, относительная метка времени, счётчик непрочитанных, сгенерированный аватар (инициалы + цвет по хэшу). Источник — network-only mock-репозиторий (бэкенд ещё не выбран).
- **User display label (отображаемое имя)**: источник инициалов аккаунт-аватара; берётся из 009 session-spine (`SettingsRootState.name`, дефолт `User7421`); charset `[A-Za-z0-9._-]`, ≤32 симв.
- **Account avatar (аккаунт-аватар)**: производные инициалы (токенизация label по пробелам и `.` `_` `-`) + визуальный стиль `AppAvatarWidget` (инициалы + цвет по хэшу) + цель перехода (`Settings` → секция `Account`); присутствует только в desktop-rail.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% состояний из мобильного макета (`filled`, `loading`, `empty`, `offline`, `inline-error`, `search`, `search-empty`) визуально совпадают с `NOX - Mobile.html` в light и dark.
- **SC-002**: 100% состояний из десктопного макета (`filled`/`selected`, `no-selection`, `loading`, `offline`, `search`, `search-empty`) визуально совпадают с `NOX - Desktop.html` в light и dark.
- **SC-003**: С экрана Chats на desktop пользователь достигает настроек аккаунта в **один** тап по аватару.
- **SC-004**: Аккаунт-аватар показывает корректные инициалы в 100% проверенных случаев и для одно-, и для много-токенного label.
- **SC-005**: Каждое функциональное состояние экрана зафиксировано golden-baseline в обеих категориях (page — mobile + page — desktop); намеренная визуальная регрессия ловится `make golden-verify`.
- **SC-006**: Полный локальный гейт (`make gate` + `make golden-verify`) проходит без единого падения.

## Assumptions

- **«Настройки аккаунта» = `Settings` → секция `Account`** (зафиксировано в Clarifications 2026-06-27). В NOX нет отдельного profile/account-экрана (profile-like элементы — `Your ID`, username, `Show QR` — живут в секции `Account` внутри Settings). Нажатие на desktop-аватар переключает активный destination на `Settings` и выбирает секцию `Account`.
- **Деривация инициалов при NOX-charset без пробелов** (зафиксировано в Clarifications 2026-06-27). Label имеет charset `[A-Za-z0-9._-]` (пробелов нет), поэтому «имя и фамилия» трактуется как токенизация по пробелам и разделителям `.`, `_`, `-`; берётся первая буква первого и последнего токена (в верхнем регистре); один токен → одна буква (частый случай `User7421` → `U`). Пустой/деградированный label → нейтральный fallback-инициал.
- **Визуальный стиль аккаунт-аватара = `AppAvatarWidget`** (зафиксировано в Clarifications 2026-06-27): инициалы + цвет по хэшу из фиксированной палитры, как у аватаров чатов.
- **Авторитетный таргет — пользовательские макеты** `NOX - Desktop.html` и `NOX - Mobile.html` (claude_design проект `d9e022e3-07fb-4fae-9147-226210933448`), сверенные с существующими per-platform корпусами (`docs/design/system/nox-desktop-screens/screens/01-chats.md`, `docs/design/system/nox-mobile-screens/screens/5-1-chats.md`). При расхождении в рамках этого change-set таргетом считается пользовательский HTML.
- **Данные остаются network-only mock** (бэкенд не выбран); экран — это уже существующий `ChatsListPage` (его BLoC и репозиторий не переписываются, меняется визуал и добавляется аватар).
- **Golden-категории по проектному правилу** (widget / page — mobile / page — desktop); исключение для splash здесь не применяется — Chats list является product-страницей и требует обе page-категории.
- **Scope ограничен экраном Chats list (обе вёрстки) + аккаунт-аватаром в rail.** Вне scope: содержимое треда (5.2), Create chat (6.1), внутренности Settings и любые не-Chats экраны; правки в shell-чроме ограничены добавлением аватара в rail.
