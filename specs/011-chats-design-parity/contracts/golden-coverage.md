# Contract: Golden coverage (mobile + desktop)

Перечень golden-кейсов, фиксирующих функционал экрана Chats. Каждый кейс рендерит **light + dark** (две PNG). Файлы: `*_golden_test.dart` + обязательный `@Tags(['golden'])`; baseline в `test/.../goldens/`. Проверка — `make golden-verify`, исключены из `make test`/CI.

Состояния гонятся детерминированно через `ChatsListScenario` (+ ввод в `AppSearchFieldWidget`) под `configureDependencies(Environment.test)`.

## Категория «page — mobile» (`goldenTest`, поверхность 360, dpr 3)

Файл: `test/presentation/pages/chats_list_page/chats_list_page_golden_test.dart`.

> **Реализация (факт, 011 merged — Принцип II).** Ниже — итоговая golden-матрица, как она реализована в `chats_list_page_golden_test.dart`. Она осознанно отличается от исходного предложения: `loading`/`search_empty` (mobile) и `selected`/`empty`/`search_empty` (desktop-page) НЕ заведены отдельными goldens — эти interaction-only состояния залочены **поведенческими** widget-тестами в `chats_list_page_test.dart` (`search filters …` / `search with no match …` / `desktop selection fills the row …`), а desktop-вид консолидирован в один полноэкранный кейс через `TabBarShell`. Кейс `filled` называется `chats_list_page`; добавлен отдельный `inline_error` (баннер) рядом с `error` (fatal).

| Имя кейса | Сценарий | settle | Baseline |
|---|---|---|---|
| `chats_list_page` | normal (есть чаты) | true | `chats_list_page_{light,dark}.png` |
| `chats_list_page_empty` | empty | true | `…_empty_{light,dark}.png` |
| `chats_list_page_offline` | offline | true | `…_offline_{light,dark}.png` |
| `chats_list_page_inline_error` | inline-error (баннер поверх списка) | true | `…_inline_error_{light,dark}.png` |
| `chats_list_page_error` | fatal | true | `…_error_{light,dark}.png` |

## Категория «page — desktop» (`goldenTestDesktop`, 1280×800, dpr 2)

В том же файле (или `…_golden_test.dart`), вызовы `goldenTestDesktop(...)` → суффикс `_desktop_`.

| Имя кейса | Сценарий | settle | Baseline |
|---|---|---|---|
| `chats_list_page` (через `TabBarShell`) | full desktop view: window-titlebar + rail (с аккаунт-аватаром) + list-pane + no-selection thread-pane | true | `chats_list_page_desktop_{light,dark}.png` |

> Desktop-кейс рендерит полный десктопный вид через смонтированный `TabBarShell` на широкой поверхности (не изолированная страница с `forceWide`), поэтому baseline включает rail + window-titlebar + аккаунт-аватар. Состояния `selected`/`empty`/`search_empty` на desktop-page залочены поведенческими widget-тестами (см. реконсиляционную заметку выше), а не отдельными desktop-goldens.

## Категория «widget» (`goldenTest`, существующий харнесс)

| Имя кейса | Что | Baseline |
|---|---|---|
| `app_navigation_rail_widget` | rail c аккаунт-аватаром внизу (`Chats` активна) | `app_navigation_rail_widget_{light,dark}.png` |

> Аккаунт-аватар фиксируется как минимум на уровне widget-golden rail (FR-017). Если desktop-page-goldens рендерят `TabBarShell`, аватар попадает и туда — widget-golden остаётся узким локом самого rail.

## Правила (проектные)

- Имя файла `*_golden_test.dart`, тег `@Tags(['golden'])` — иначе тест молча выпадет из CI/`make test`.
- Анимируемые состояния (`loading`-спиннер) — `settle: false`.
- Шрифты — `loadNoxFonts` (внутри харнесса), глифы рендерятся как настоящий Roboto.
- Baseline генерируются `make golden-update`, проверяются `make golden-verify` (Apple Silicon/macOS).
- Осиротевшую `test/presentation/pages/chats_list_page/failures/` удалить при добавлении настоящего golden-теста.
- **(G1) Перегенерация затронутых существующих widget-goldens.** Если US1/US2 меняют виджеты, у которых уже есть golden (`app_chat_item_widget`, `app_search_field_widget` при наличии), их baseline ОБЯЗАТЕЛЬНО перегенерировать в том же change-set — иначе `make golden-verify` упадёт неожиданно. Scope `make golden-update` в T021 включает эти файлы, а не только новые.
- **(U1b) Desktop-page-goldens рендерятся через смонтированный `TabBarShell`** на широкой поверхности (а не изолированная страница с `forceWide`), чтобы baseline включал rail + window-titlebar + аккаунт-аватар — настоящий десктопный вид экрана.

## Acceptance

- FR-014 (page-mobile), FR-015 (page-desktop), FR-016 (все состояния), FR-017 (аватар), FR-018 (`make golden-verify` зелёный, `make gate` зелёный).
- SC-005 (намеренная регрессия ловится), SC-006 (полный гейт без падений).
