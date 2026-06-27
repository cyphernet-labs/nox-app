# Research: Chats list — сверка с дизайном и golden-покрытие

Phase 0. Разрешение технических неизвестных перед дизайном. Все пункты ниже — **Resolved** (NEEDS CLARIFICATION не осталось; продуктовые неоднозначности закрыты в `spec.md` → Clarifications 2026-06-27).

---

## R1 — Деривация инициалов аккаунта vs `noxInitials` (правило чатов)

**Decision.** Ввести отдельную pure-util `noxAccountInitials(String label)` рядом с `noxInitials` в `lib/design/theme/nox_brand.dart`. Реализация по уточнённому правилу: токенизация по `RegExp(r'[\s._-]+')`; берётся первая алфавитно-цифровая буква **первого** и **последнего** токена → 2 буквы (uppercase); один токен → **одна** буква; пустой/без-алфавитно-цифровых → `null` (fallback на glyph).

**Rationale.** Существующий `noxInitials` НЕ подходит для account-правила: (1) сплитит только по пробелам, не по `. _ -` → `john.doe` даёт «JO» вместо требуемого «JD»; (2) для одного токена возвращает **два** символа → `User7421` даёт «US» вместо требуемого «U»; (3) для ≥3 слов берёт первое+**второе**, а не первое+последнее. Менять `noxInitials` нельзя — это изменит инициалы аватаров чатов (`Standup`→«ST» станет «S») и сломает существующие goldens. Поэтому правило аккаунта — отдельная функция.

**Alternatives considered.** Обобщить `noxInitials` параметром — отклонено: рискует регрессией аватаров чатов и их goldens. Считать инициалы в виджете — отклонено: pure-util тестируется юнитом и переиспользуется.

**Контрольные примеры (для `nox_account_initials_test.dart`):** `User7421`→`U`; `john.doe`→`JD`; `john_doe_smith`→`JS`; `a-b-c`→`AC`; `Alice`→`A`; `nox.core.team`→`NT`; ``/`...`→`null`.

---

## R2 — Визуальное переиспользование `AppAvatarWidget`

**Decision.** Расширить `AppAvatarWidget` опциональным параметром `final String? initials;`. Если `initials != null` — рисуем его (uppercase, тот же стиль: белый, `size*0.4`), иначе текущая ветка `noxInitials(name)`. Фон по-прежнему `noxAvatarColor(name)`. Аккаунт-аватар вызывается как `AppAvatarWidget(name: label, initials: noxAccountInitials(label), size: …)`.

**Rationale.** Сохраняет визуальную консистентность с аватарами чатов (Q3: «как у чатов») и хэш-цвет по label, но позволяет подать account-инициалы. Минимальная, обратносовместимая правка (существующие вызовы без `initials` не меняются → goldens чатов стабильны).

**Alternatives considered.** Отдельный `AppAccountAvatarWidget` — отклонено как дублирование визуала ради одного отличия (источник инициалов). Передавать в `name` уже «склеенную» строку — отклонено: ломает хэш-цвет (цвет должен зависеть от реального label, а не от инициалов).

---

## R3 — Источник label для rail-аватара (shell без BLoC)

**Decision.** `TabBarShell` (`StatefulWidget`, остаётся BLoC-less) в `initState` делает one-shot `sessionRepository.readSession()`, кладёт `session?.label` в локальное поле `String? _accountLabel` и `setState` по завершении; передаёт `accountLabel` в `AppNavigationRailWidget`. Fallback при null/ошибке — дефолтный display-label (`User7421`, как в `SettingsRootState.name`), чтобы аватар не был пустым в UI-first фазе.

**Rationale.** Display-only чтение из cache-only репозитория — тривиальное состояние; по carve-out блюпринта 05 §5.1 (UI-first фаза) чисто презентационный shell без мутаций/пагинации/домен-состояния остаётся `StatefulWidget` без BLoC. Полноценный BLoC у shell появится в backend-фазе вместе с реактивной сессией.

**Alternatives considered.** `FutureBuilder` прямо в rail — отклонено: дёргал бы репозиторий на каждый rebuild rail (а shell ребилдит тело каждый кадр). Завести BLoC у shell сейчас — отклонено как преждевременно (нет реактивных данных; противоречит зафиксированному carve-out). Брать label из `SettingsRootBloc` — отклонено: связывает shell с внутренним bloc вкладки.

---

## R4 — «Приземлиться на секцию Account» при сохранённом состоянии вкладки Settings

**Decision.** Добавить в `SettingsRootPage` опциональный `final ValueListenable<int>? jumpToAccount;` (по образцу `ChatsListPage.scrollToTop`). `TabBarShell` владеет `ValueNotifier<int> _settingsJumpToAccount`; по тапу аккаунт-аватара: `setState(_active = AppTab.settings)` **и** `_settingsJumpToAccount.value++`. `SettingsRootPage` слушает и по бампу делает `setState(_selected = _Section.account)` (desktop), на mobile — гарантирует показ корня/идентити-карточки. Дефолт уже `_Section.account`, поэтому при первом заходе сигнал избыточен, но он покрывает кейс «пользователь ранее ушёл в Appearance, состояние вкладки сохранено».

**Rationale.** Вкладки в shell держатся живыми (`IgnorePointer`+`AnimatedOpacity`), поэтому `_selected` переживает переключения — без сигнала возврат на Settings показал бы последнюю секцию, а не Account. Паттерн `ValueNotifier<int>`-бамп уже используется (`_chatsScrollToTop`) → консистентно и тестируемо.

**Alternatives considered.** Завязаться на дефолт `_Section.account` без сигнала — отклонено: не гарантирует Account при сохранённом состоянии. Глобальный event-bus — отклонено как избыточно.

---

## R5 — Размещение аватара в `NavigationRail` (pin к низу)

**Decision.** Использовать слот `NavigationRail.trailing`, обёрнутый в `Expanded(child: Align(alignment: Alignment.bottomCenter, child: <padded avatar>))`. Аватар — `InkResponse`/`IconButton`-обёртка вокруг `AppAvatarWidget` (tooltip `Account`), с нижним отступом-токеном. Размер — `AppDimensionTokens.size.avatarSm` (как строки чатов) или меньший rail-размер по итогам сверки с дизайном.

**Rationale.** `trailing` в `NavigationRail` рендерится после destinations; `Expanded`+`Align(bottomCenter)` — канонический способ прижать его к низу rail. Это не добавляет третий destination (аватар — действие, не вкладка), поэтому `selectedIndex` остаётся валидным (0/1) и индикатор выбора не ломается.

**Alternatives considered.** Третий `NavigationRailDestination` — отклонено: исказил бы `selectedIndex`/семантику вкладок. Кастомный `Column` вместо `NavigationRail` — отклонено: потеря M3-темизации rail.

---

## R6 — Метод пиксельной сверки с макетами (claude_design MCP)

**Decision.** На этапе implement импортировать оба макета через claude_design MCP (`https://api.anthropic.com/v1/design/mcp`, auth `/design-login`), проект `d9e022e3-07fb-4fae-9147-226210933448`, файлы `NOX - Mobile.html` и `NOX - Desktop.html`. Сверять токен-к-токену (отступы, типографика, цвета из `ColorScheme`, форма/радиусы, hairline-градиент, тени/elevation поля поиска, бейдж, empty-state). Расхождения чинить в обеих ветках (`_mobile`/`_desktop`), приоритет — пользовательский HTML; затем сверять с per-platform корпусами (`5-1-chats.md`, `01-chats.md`) и при расхождении фиксировать корпус.

**Rationale.** Приложенные скриншоты — текущий DEBUG-билд (desktop без аккаунт-аватара = до-состояние), а HTML — целевой источник истины. Точный пиксель-дифф требует самого HTML, доступного только на implement через MCP.

**Подозреваемые дельты (гипотезы для аудита, подтвердить против HTML):** глубина/тень поля `Search`; точный градиент brand-hairline (teal→…→red); вес/трекинг wordmark; цвет/контраст бейджа и таймстампа в dark; стиль desktop pane-заголовка `Chats`; иллюстрация и копи no-selection empty-state; инсет/радиус выбранной строки на desktop. **Список не финальный** — финализируется по HTML на implement (Принцип II: расхождения чинятся в change-set).

**Alternatives considered.** Сверять только по скриншотам — отклонено: скриншоты — это до-состояние, а не таргет. Только по корпусам `_src/*.jsx` — отклонено: пользовательский HTML авторитетнее для этой задачи.

---

## R7 — Golden-харнесс и детерминированный прогон состояний

**Decision.** Использовать существующий `test/utils/golden.dart`: `goldenTest(name, build)` (mobile 360, light+dark) и `goldenTestDesktop(name, build)` (1280×800, dpr 2, light+dark). Состояния гонять детерминированно через `ChatsListBloc`-сценарии (`ChatsListScenario`: `normal`/`empty`/`loading`/`offline`/`error`/…) + ввод в `AppSearchFieldWidget` для `search`/`search-empty`, под `configureDependencies(Environment.test)` (mock-данные). Для desktop дополнительно: `no-selection` (без выбора) и `selected` (тап по строке → detail-панель). Анимируемые состояния (`loading`-спиннер) — `settle: false`.

**Rationale.** Это уже зафиксированный проектный харнесс и 3-golden-категории (widget / page-mobile / page-desktop). Сценарии `ChatsListScenario` дают детерминированный рендер без сети.

**Open (в tasks):** сколько отдельных baseline на состояние (по одному golden-кейсу на состояние × тема × вёрстка). Гранулярность финализируется в `/speckit-tasks` (см. `contracts/golden-coverage.md` — предложенная матрица).

**Alternatives considered.** Один «filled» golden на вёрстку — отклонено: spec требует покрыть **весь** функционал/состояния. Live-camera/сетевые данные — неприменимо.

---

## R8 — Семантика выбранного состояния и parity row-tap

**Decision.** Сохранить текущую parity: mobile row-tap → `Navigator.push(ChatThreadPage.route)` (5.2); desktop row-tap → `ChatsListEvent.chatSelected` (выбор без push) + подсветка inset-пилюлей (`secondaryContainer`, радиус `lg`) + загрузка треда в detail-панель. Эту логику не переписываем — только приводим визуал к дизайну.

**Rationale.** Поведение уже соответствует desktop-корпусу (`01-chats.md`: «Selecting a row highlights it (secondaryContainer) and loads the thread — no navigation push»). Менять нечего, кроме визуальной сверки подсветки/инсета.

**Alternatives considered.** Нет — поведение зафиксировано корпусом и кодом.
