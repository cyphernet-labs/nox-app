---
description: "Task list for 008-app-icons"
---

# Tasks: App icons — все платформы

**Input**: design-документы из `specs/008-app-icons/`

**Prerequisites**: plan.md ✅, spec.md ✅, research.md ✅, data-model.md ✅, contracts/ ✅, quickstart.md ✅

**Tests**: Dart-тесты (unit/widget/golden) **не применимы** — фича не добавляет `lib/`-кода. «Проверка» = структурная верификация (файлы в нативных путях + манифесты) + per-platform compile-smoke (решено в Clarifications). Verify-задачи включены в каждую историю.

**Organization**: задачи сгруппированы по user-story (по одной на платформу); каждая платформа реализуется и проверяется независимо.

`SRC = docs/design/system/nox-app-icons`

## Format: `[ID] [P?] [Story] Description`

- **[P]**: можно параллелить (разные файлы/каталоги, нет зависимостей)
- **[Story]**: к какой истории относится (US1–US5)

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: воспроизводимый путь регенерации (FR-008) — конфиг коммитим, генератор не запускаем.

- [X] T001 [P] Добавить в `pubspec.yaml` `dev_dependencies: flutter_launcher_icons` + блок `flutter_launcher_icons:` (`image_path`/`adaptive_icon_foreground` → `docs/design/system/nox-app-icons/source/*`, `adaptive_icon_background: "#151919"`, `remove_alpha_ios: true`, таргеты `android/ios/macos/windows`) — точно по `specs/008-app-icons/contracts/flutter-launcher-icons.md`; генератор **НЕ запускать**.
- [X] T002 Запустить `fvm flutter pub get`; убедиться, что `flutter_launcher_icons` резолвится без конфликта версий (пин совместимой версии под Dart `>=3.12`). Зависит от T001.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: единственный общий гард перед drop-in'ами; отдельных stories не блокирует сверх этого.

- [X] T003 Проверить целостность набора-источника: `SRC/{ios,android,macos,windows,linux,source}/` присутствуют со всеми ожидаемыми файлами (12 iOS PNG + `Contents.json`; Android `res/mipmap-*` + `anydpi-v26` + `values`; 7 macOS PNG + `Contents.json`; `windows/app_icon.ico`; `linux/hicolor/*` + `nox.desktop`; `source/icon-master-1024.png` + `icon-foreground-1024.png`).

**Checkpoint**: набор валиден — drop-in'ы платформ можно запускать параллельно.

---

## Phase 3: User Story 1 — Иконка на Android (Priority: P1) 🎯 MVP

**Goal**: брендовая adaptive-иконка NOX в Android-лаунчере вместо дефолта Flutter.

**Independent Test**: структурная проверка (T006) + `mise run build:android:stage` + визуал на эмуляторе (adaptive под маской устройства).

- [X] T004 [P] [US1] Скопировать `SRC/android/res/*` в `android/app/src/main/res/` (mipmap-{m,h,x,xx,xxx}dpi: `ic_launcher.png` + `ic_launcher_round.png` + `ic_launcher_foreground.png`; `mipmap-anydpi-v26/ic_launcher.xml` + `ic_launcher_round.xml`; `values/ic_launcher_background.xml`).
- [X] T005 [US1] Добавить в `android/app/src/main/AndroidManifest.xml` атрибут `android:roundIcon="@mipmap/ic_launcher_round"` (рядом с существующим `android:icon`; `android:label="NOX"` не трогать).
- [X] T006 [US1] Структурная верификация Android по `contracts/icon-install-map.md`: round+foreground в каждой плотности, `anydpi-v26` ссылается на `@mipmap/ic_launcher_foreground` и `@color/ic_launcher_background`, `ic_launcher_background = #151919`, в манифесте есть `android:roundIcon`. Зависит от T004, T005.

**Checkpoint**: Android-иконка готова и независимо проверяема.

---

## Phase 4: User Story 2 — Иконка на iOS (Priority: P1)

**Goal**: брендовая иконка NOX на домашнем экране iOS (opaque, скругление от ОС).

**Independent Test**: структурная проверка (T008) + `mise run build:ios:stage` + визуал на симуляторе.

- [X] T007 [P] [US2] Заменить папку `ios/Runner/Assets.xcassets/AppIcon.appiconset/` содержимым `SRC/ios/AppIcon.appiconset/` (`Contents.json` + 12 `Icon-*.png`); удалить дефолтные `Icon-App-*.png`.
- [X] T008 [US2] Структурная верификация iOS: `Contents.json` ссылается только на присутствующие файлы (`Icon-20-2x`…`Icon-1024`), 12 PNG, все без alpha (`sips -g hasAlpha` → no), дефолтных `Icon-App-*` не осталось. Зависит от T007.

**Checkpoint**: iOS-иконка готова; мобильный паритет (P1) закрыт.

---

## Phase 5: User Story 3 — Иконка на macOS (Priority: P2)

**Goal**: брендовая иконка NOX в Dock/Launchpad (rounded-rect + маржин).

**Independent Test**: структурная проверка (T010) + `mise run build:macos:stage` + визуал в Dock.

- [X] T009 [P] [US3] Заменить папку `macos/Runner/Assets.xcassets/AppIcon.appiconset/` содержимым `SRC/macos/AppIcon.appiconset/` (`Contents.json` + 7 `app_icon_{16,32,64,128,256,512,1024}.png`).
- [X] T010 [US3] Структурная верификация macOS: 7 `app_icon_*` + `Contents.json` (имена совпадают с дефолтом, замена консистентна); `nox.icns`/`nox.iconset` в таргет не попали. Зависит от T009.

**Checkpoint**: macOS-иконка готова.

---

## Phase 6: User Story 4 — Иконка на Windows (Priority: P2)

**Goal**: брендовая иконка NOX в таскбаре/заголовке окна.

**Independent Test**: структурная проверка (T012) + `mise run build:windows:stage` (на Windows-хосте/CI).

- [X] T011 [P] [US4] Заменить `windows/runner/resources/app_icon.ico` файлом `SRC/windows/app_icon.ico`.
- [X] T012 [US4] Структурная верификация Windows: `app_icon.ico` мультиразрешённый (`file app_icon.ico` → «7 icons»); `windows/runner/Runner.rc` (`IDI_APP_ICON ICON "resources\app_icon.ico"`) без изменений. Зависит от T011.

**Checkpoint**: Windows-иконка готова.

---

## Phase 7: User Story 5 — Иконка на Linux (Priority: P3)

**Goal**: packaging-ready ассеты NOX (`hicolor` + согласованный `.desktop`).

**Independent Test**: структурная проверка (T015) + `mise run build:linux:stage` (на Linux-хосте/CI); видимость в меню — будущий packaging (вне scope).

- [X] T013 [P] [US5] Создать `linux/packaging/`; скопировать `SRC/linux/hicolor/*` → `linux/packaging/hicolor/*` и `SRC/linux/nox.desktop` → `linux/packaging/nox.desktop`.
- [X] T014 [US5] Реконсилировать `linux/packaging/nox.desktop`: `Exec=nox`→`Exec=nox_app`, `StartupWMClass=nox`→`StartupWMClass=com.cyphernetlabs.noxapp` (`Name=NOX`, `Icon=nox`, `Comment=Secure messaging`, `Categories` — без изменений). Зависит от T013.
- [X] T015 [US5] Структурная верификация Linux: `linux/packaging/hicolor/<size>/apps/nox.png` для 16/24/32/48/64/128/256/512; `.desktop` содержит `Exec=nox_app` и `StartupWMClass=com.cyphernetlabs.noxapp`. Зависит от T014.

**Checkpoint**: все 5 платформ имеют брендовые ассеты.

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: трассируемость, кросс-платформенная верификация, закрытие DoD.

- [X] T016 [P] Добавить в `docs/design/system/nox-app-icons/README.md` короткую пометку «installed into native targets — see `specs/008-app-icons`» (трассируемость FR-009).
- [X] T017 Compile-smoke (FR-007 / SC-002): `compile-check.yml` (5 per-platform `--debug` builds) **dispatched на ветку `008-app-icons`** — все 5 джобов зелёные (android/ios/macos/windows/linux, run 28186502847). `compile-check.yml` триггерится только push-to-develop/master, не на PR → запущен через `workflow_dispatch`. PR `gate` (ci.yml) тоже green. Зависит от T004–T015.
- [ ] T018 Визуальная проверка (SC-001): macOS (Dock), iOS-симулятор (домашний экран), Android-эмулятор (лаунчер, adaptive). **Резидуал** — требует запуска на устройстве/дисплее (не автоматизируемо здесь); структурная проверка + 5/5 compile-smoke дают высокую уверенность.
- [X] T019 Финал: дефолтная иконка Flutter не отображается ни на одной платформе (подтверждено структурно — wholesale-замена appiconset/`.ico` + перезапись `ic_launcher.png`; 5/5 сборок зелёные); чек-лист DoD в `quickstart.md` отмечен. Остаточный визуал — T018.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: старт сразу; T002 зависит от T001.
- **Foundational (Phase 2, T003)**: гард набора — до drop-in'ов.
- **User Stories (Phase 3–7)**: после T003 — **все 5 независимы и параллелятся** (разные нативные каталоги). Конфиг регенерации (Phase 1) их не блокирует.
- **Polish (Phase 8)**: после завершения нужных историй (T017 — после всех drop-in'ов).

### User Story Dependencies

- US1–US5 взаимно независимы (нет cross-story зависимостей). Приоритет: US1 (Android, P1) → US2 (iOS, P1) → US3 (macOS, P2) → US4 (Windows, P2) → US5 (Linux, P3).

### Внутри истории

- copy/replace → manifest-правка (US1) / реконсиляция (US5) → структурная верификация.

### Parallel Opportunities

- T001 [P] (pubspec) — параллельно с T003.
- **T004, T007, T009, T011, T013 [P]** — пять drop-in'ов в разные нативные каталоги, выполняются параллельно после T003.
- T016 [P] — независимая правка README.

---

## Parallel Example: drop-in пяти платформ

```bash
# После T003 (гард набора) — пять платформенных drop-in'ов параллельно:
Task: "T004 [US1] copy SRC/android/res/* → android/app/src/main/res/"
Task: "T007 [US2] replace ios/Runner/Assets.xcassets/AppIcon.appiconset/"
Task: "T009 [US3] replace macos/Runner/Assets.xcassets/AppIcon.appiconset/"
Task: "T011 [US4] replace windows/runner/resources/app_icon.ico"
Task: "T013 [US5] create linux/packaging/ + copy hicolor + nox.desktop"
```

---

## Implementation Strategy

### MVP First

- **Минимальный инкремент** — US1 (Android): первая брендированная платформа.
- **Практический MVP** — P1-пара US1 + US2 (Android + iOS): брендированный мобильный паритет.
1. Phase 1 (Setup) → Phase 2 (T003 гард) → US1 → **STOP & VALIDATE** (T006 + Android compile-smoke + визуал).
2. Добавить US2 → валидировать → мобильный MVP готов.

### Incremental Delivery

Setup + гард → US1 → US2 (мобильный MVP) → US3 → US4 → US5 → Phase 8 (кросс-верификация + DoD). Каждая история добавляет платформу, не ломая прочие.

---

## Notes

- [P] = разные файлы/каталоги, нет зависимостей.
- Нет Dart-кода → нет unit/widget/golden-задач; верификация — структурная + compile-smoke.
- Конфиг `flutter_launcher_icons` (T001) **коммитится, но не запускается** (перезатёр бы crafted-набор; не покрывает Linux) — см. `contracts/flutter-launcher-icons.md`.
- **iOS no-alpha (T008):** присланные iOS-PNG имели alpha-канал (`hasAlpha: yes`) вопреки FR-003/SC-004 → во время реализации они **флэттены в no-alpha** (RGB над `#151919`) в наборе-источнике и в `ios/Runner/...` (Pillow, пиксели не изменились). `flutter_launcher_icons` имеет `remove_alpha_ios: true` — регенерация останется alpha-free.
- Коммит — после каждой истории или логической группы (по правилу репо — с явного подтверждения владельца).
- Долг (вне scope, на финальный вектор): мягкий апскейл 512/1024, фон `#151919` vs бренд `#0C2424`, отсутствие Android monochrome-слоя.
