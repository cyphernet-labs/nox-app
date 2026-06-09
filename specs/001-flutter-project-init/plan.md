# Implementation Plan: Инициализация Flutter-проекта NOX (multi-platform skeleton)

**Branch**: `001-flutter-project-init` | **Date**: 2026-06-09 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/001-flutter-project-init/spec.md`

## Summary

Поднять пустой репозиторий до запускаемого, соответствующего блюпринту каркаса `nox_app` на пять платформ (iOS, Android, Windows, Linux, macOS; web вне scope), **без реальных продуктовых фич**. Технический подход целиком выводится из блюпринта `docs/patterns/mobile/` (особенно `11-scaffolding-plan.md`) с уже внесёнными desktop-расширениями: `flutter create --platforms` на пять таргетов, один Dart-пакет со слоями-папками, единый injectable+get_it DI, тема из дизайн-токенов, **адаптивная оболочка** (`NavigationBar`↔`NavigationRail`, width-driven на `840dp`), зелёный code-gate и сквозной `Item`-verification-harness. Desktop-специфика (флейворы через `--dart-define-from-file`, prod-only identity, no-op/disabled fallbacks для push/deep-links/secure-storage, 3 compile-smoke CI-джоба) зафиксирована в блюпринте и здесь реализуется по нему.

## Technical Context

**Language/Version**: Dart `>=3.12.0 <4.0.0`; Flutter `3.44.1` (пин через FVM, `.fvmrc`).

**Primary Dependencies**: codegen-стек — `freezed` + `json_serializable` + `injectable`/`get_it` + `flutter_gen`, один прогон `build_runner`; `flutter_screenutil` (токены), `infinite_scroll_pagination` ^5 (PagingState-in-bloc), `sembast` (cache-first DAO), `rxdart` (BehaviorSubject); сетевые/бэкенд-зависимости (`dio` и пр.) присутствуют как пример — реальный контракт TBD. Адаптивная оболочка — **кастомный breakpoint без** `flutter_adaptive_scaffold`/`custom_adaptive_scaffold`. Исключены из скелета: `window_manager`, `bitsdojo_window`, `desktop_multi_window`, `yaru`.

**Storage**: `Sembast` (env-scoped `AppDatabase`: Dev/Prod = IO, Test = memory). В скелете реально пишет только `Item`-harness (mock-данные); продуктовых данных нет.

**Testing**: `flutter_test` — baseline-набор на `Item`-harness (bloc smoke + mapper round-trip); `flutter test integration_test` зарезервирован. Тесты держат зелёный gate осмысленным.

**Target Platform**: iOS, Android, Windows, Linux, macOS. **Web — вне scope.** Min-OS = дефолты Flutter 3.44.1 (Windows 10 / macOS 10.15 / Linux GTK3); пин конкретики — FUTURE (с packaging).

**Project Type**: Кросс-платформенное Flutter-приложение, **один Dart-пакет** `nox_app`, Clean Architecture слоями-папками (`presentation → domain ← data`, `domain` ни от чего не зависит).

**Performance Goals**: Для скелета perf-целей нет (нет фич); инвариант — app shell стартует без падений и держит стоковую M3-плавность. Реальные цели задаются с фичами.

**Constraints**: только дизайн-токены (никакого хардкода цвета/отступов/типографики/overlay); `RepositoryResult<T>` (data XOR exception) во всём repo-слое; обязательный `LogRepository` (никаких сырых `print`/`debugPrint`); codegen-first (сгенерированные файлы не правятся руками, исключены из анализа); line length 140, стоковый `flutter_lints`, `flutter analyze` без ошибок; single-window; адаптивная оболочка width-driven (`Constants.railBreakpoint = 840dp`), не Platform-driven; compile-time flavor'ы `stage`/`prod` без runtime-ветвления; desktop-fallback'ы по FR-012 (проза-only в скелете).

**Scale/Scope**: Структурный каркас + один `Item`-harness-слайс. 7 слоёв-папок, 5 платформенных таргетов, 2 флейвора, 3 desktop compile-smoke CI-джоба. Без auth/push/deep-link/реального бэкенда (FR-013).

**Open unknowns**: нет `NEEDS CLARIFICATION`. Бэкенд/протокол/криптоядро **намеренно не выбраны** (ограничение конституции, §«Технологический контекст»): сетевые/auth/envelope/endpoint специфики в блюпринте `04`/`14`/`15`/`16` — пример/TBD; скелет поднимает структуру и НЕ интегрируется с реальным бэкендом, поэтому это не блокер плана.

## Constitution Check

*GATE: проверка против ратифицированной конституции **v1.1.0** (принципы I–V). Перепроверяется после Phase 1.*

| Принцип | Гейт | Статус |
|---|---|---|
| I. Приватность и E2EE | Аналитика/логи/крэши без PII; аналитика opt-in (выключена); identity-wipe-путь определён | ✅ PASS — крипто/messaging нет (FR-013); аналитика не подключена; secure-storage/wipe задокументированы, wiring с auth. Ничего не ослабляет приватность. |
| II. Спека/дизайн-корпус — источник истины | План следует spec + `docs/design/spec/`; out-of-scope молча не расширяется | ✅ PASS — desktop расширен через governance (v1.1.0), не молча; план не выходит за spec. |
| III. Блюпринт обязателен | Строим по `docs/patterns/mobile/` (+ desktop-расширения) | ✅ PASS — план = проекция блюпринта; desktop-части уже внесены. |
| IV. Верность дизайн-системе | M3 light+dark из токенов `nox-handoff`, без хардкода, тёмный splash | ✅ PASS — FR-005; единая M3 на 5 платформах, без `yaru`. |
| V. Языковая дисциплина | RU-проза / EN-код/идентификаторы/UI-микрокопия | ✅ PASS — каркас EN-only (`TextConstants`), full i18n отложен. |

**Гейты пройдены, нарушений нет.** Desktop-scope — не нарушение (governed v1.1.0); один Dart-пакет — без лишних проектов. Раздел Complexity Tracking пуст.

## Project Structure

### Documentation (this feature)

```text
specs/001-flutter-project-init/
├── plan.md              # этот файл (/speckit-plan)
├── research.md          # Phase 0 — консолидация решений (clarify + 18 desktop)
├── data-model.md        # Phase 1 — структурные элементы + Item-harness
├── quickstart.md        # Phase 1 — runnable validation (scaffold → gate → build/launch)
├── contracts/           # Phase 1 — внутренние контракты каркаса (внешние/бэкенд — TBD)
├── checklists/
│   └── requirements.md  # spec-quality (создан /speckit-specify)
└── tasks.md             # Phase 2 — /speckit-tasks (НЕ создаётся этой командой)
```

### Source Code (repository root)

Один Dart-пакет `nox_app` (по блюпринту `00`/`11`); слои — папки в `lib/`. Пять платформенных runner'ов генерируются `flutter create --platforms=android,ios,macos,windows,linux` (без `web/`).

```text
nox_app/                         # корень пакета (== repo root)
├── pubspec.yaml                 # ОДИН манифест; name: nox_app
├── .fvmrc                       # Flutter 3.44.1
├── analysis_options.yaml        # flutter_lints, line length 140, gen/** исключены
├── build.yaml                   # codegen-конфиг
├── config/                      # desktop flavor inputs (committed, secret-free)
│   ├── stage.json               # {"app.flavor":"stage"}
│   └── prod.json                # {"app.flavor":"prod"}
├── lib/
│   ├── main.dart                # runZonedGuarded → configureDependencies(env) → getIt.allReady() → runApp(AppRoot)
│   ├── di/                      # configureDependencies + @InjectableInit + .config.dart
│   ├── domain/                  # контракты репозиториев, Freezed-модели (без JSON), RepositoryResult, исключения, configs
│   ├── data/                    # entity (basic+JSON), мапперы, DAO (Sembast), repo-impl'ы, remote-API (пример/TBD)
│   ├── presentation/
│   │   ├── app/                 # AppRoot (MaterialApp), AppRootBloc (themeMode), widgets/app_shell.dart (адаптивный)
│   │   ├── base/                # BaseBloc, BaseStatePage
│   │   └── pages/               # Item-harness page (плейсхолдер вкладок)
│   ├── general/                 # Constants (incl. railBreakpoint=840), PlatformUtils, formatters, LogRepository
│   ├── design/                  # AppTheme.light()/dark(), ThemeExtension<AppColors>, токены, gen/
│   └── resource/                # ассеты/строки (TextConstants, EN-only)
├── android/  ios/  macos/  windows/  linux/   # пять нативных runner'ов (НЕТ web/)
├── test/                        # baseline: Item bloc smoke + mapper round-trip
└── .github/workflows/           # ci.yml (gate) + compile-check.yml (5 платформ, Win/Linux compile-only)
```

**Structure Decision**: Единственный вариант — **single Dart package, Clean Architecture слоями-папками** (несущий инвариант блюпринта; принцип III). Никаких backend/frontend-split или мульти-пакетов. Десктоп-таргеты — это дополнительные нативные runner'ы того же пакета (генерируются `flutter create`), не отдельные проекты. `config/<flavor>.json` — единственная desktop-специфичная добавка к структуре (флейвор без native `--flavor`).

## Complexity Tracking

> Нарушений Constitution Check нет — раздел не заполняется.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| — | — | — |
