# Implementation Plan: App-state flow (spine приложения)

**Branch**: `009-app-state-flow` | **Date**: 2026-06-25 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/009-app-state-flow/spec.md`

## Summary

Перенос проверенного **app-state-spine** (`docs/app-state-flow-migration.md`) в NOX, адаптированный под продуктовую модель. Вводится единый реактивный источник правды о фазе жизненного цикла приложения — `AppStateRepository` (in-memory `BehaviorSubject`, **проекция** сигналов сессии, без DAO), управляющий **всей** верхнеуровневой навигацией через расширенный `AppRootBloc` + route-swap в `AppRoot`. Состояния: `init → unauthorized → registrationPending → authorized` (без гостя/ролей; `registrationPending` = first-login gate имени). Сигналы сессии — `SessionModel { identifier, label?, onboardingComplete }`: `identifier` в `flutter_secure_storage`, флаги в `SharedPreferences`. Мутации (`signIn`/`completeOnboarding`/`logout`) оркеструются `AuthRepository` по контракту «мутируй → `fetchAppState()`». Первый переход удержан за splash-анимацией (двухфазное применение); контракт `sessionExpired` + единый `forceLogout` заложены, 401-триггер отложен (бэкенд TBD). Точка входа меняется с launcher на Splash-под-spine; галерея остаётся dev-доступной. Технический подход и развилки зафиксированы в [research.md](research.md) (R1–R12).

## Technical Context

**Language/Version**: Dart `>=3.12.0 <4.0.0`, Flutter `3.44.1` (FVM-pinned), line length 140.

**Primary Dependencies**: `flutter_bloc`, `freezed`/`freezed_annotation`, `injectable`+`get_it`, `rxdart 0.28.0` (`BehaviorSubject`), `flutter_secure_storage ^10.3.1`, `shared_preferences ^2.5.5`, `flutter_screenutil`. (Все уже в `pubspec.yaml`.)

**Storage**: `flutter_secure_storage` (identifier) + `shared_preferences` (`onboardingComplete`, кэш `label`). **Никакого Sembast-DAO для app-state** — состояние derived/in-memory (миграционный гайд §1.1).

**Testing**: `flutter_test`, `bloc_test`, `mockito` (mocktail запрещён); harness `pumpApp`/test-env DI (`Environment.test`); goldens исключены из `make gate`/CI.

**Target Platform**: iOS, Android, macOS, Windows, Linux (web — вне scope).

**Project Type**: кросс-платформенное Flutter-приложение, один пакет `nox_app` (Clean Architecture слоями-папками).

**Performance Goals**: cold-start резолюция — cache-only, без сети, укладывается в окно reveal-анимации splash (типично <100 ms); первая навигация гейтится завершением анимации (нет мелькания).

**Constraints**: offline-capable резолюция; secure-storage нативные backends на 5 таргетах; **identifier никогда не попадает в логи** (конституция I); единый путь wipe на logout.

**Scale/Scope**: ~6 новых доменных файлов (enum + 2 модели + 3 контракта), 3 repo-impl + 1 DI-модуль, расширение `AppRootBloc`/`AppRootState`/`AppRootEvent`, route-swap в `AppRoot`, реконсиляция 4 экранов (Splash/Login/SetUsername/Settings), 1 новая строка `TextConstants`, macOS entitlements, ~5 тест-файлов. Малая-средняя фича.

**Unknowns**: нет блокирующих `NEEDS CLARIFICATION` — спека прошла `/speckit-clarify`; бэкенд/сетевые контракты помечены TBD конституцией (не блокируют cache-only spine).

## Constitution Check

*GATE: пройден до Phase 0; перепроверен после Phase 1.*

| Принцип | Оценка | Обоснование |
|---|---|---|
| **I. Приватность и E2EE** | ✅ PASS | `identifier` (секрет) → secure storage; logout = полный wipe (`deleteAll()` + prefs clear), точно по «Logout полностью стирает идентификатор и локальные данные». **Гард**: `identifier` не логируется (логируются только исключения через `BaseRepositoryHelper`); аналитика N/A. Сеть не трогается (cache-only). |
| **II. Спека/дизайн — источник истины** | ✅ PASS | Spec-driven (spec→clarify→plan); экраны следуют locked-спекам 1.1/2.1/2.3/4.1/7.x. Дрейф устраняется в том же change-set: имя хелпера в блюпринте (`AppFeedbackHelper`), форма `05 §6.1`, снятие gap `auth/app-state-spine` (R9/R10/R12). |
| **III. Блюпринт обязателен** | ✅ PASS (с расширением подсистемы) | Строим по `03/04/02/05/06`; spine — задокументированный-но-отложенный паттерн `05 §6.1`, материализуется. **Desktop-native gate**: secure storage — платформенная нативная часть → по Принципу III **расширяем на desktop** (macOS keychain entitlement, Linux libsecret уже в CI, Windows DPAPI), а не stub'аем. Дрейф код↔блюпринт чиним тем же change-set. |
| **IV. Верность дизайн-системе** | ✅ PASS | sessionExpired-snackbar через токенизированный `showAppSnackBar(error:true)` (`context.appColors`/`ColorScheme`); splash brand-fixed dark canvas сохранён; без хардкод-цветов/отступов. |
| **V. Языковая дисциплина** | ✅ PASS | Код/идентификаторы EN; UI-микрокопирайт EN (`Your session expired`, `Log out`, `Your ID`); spec/research/прочие артефакты — RU; коммиты EN. |

**Tech-context конституции**: бэкенд/протокол не выбран → реальный sign-in/refresh/401-триггер помечены пример/TBD, не «изобретаются» (FR-017). Соответствует.

**Итог гейта**: нарушений нет → **Complexity Tracking пуст**. (Перепроверка после Phase 1: дизайн-артефакты не вводят новых отклонений — расширение `AppRootBloc` и DAO-less `BehaviorSubject` остаются в рамках `05 §6.1`/`04 §8.1`; гейт остаётся PASS.)

## Project Structure

### Documentation (this feature)

```text
specs/009-app-state-flow/
├── plan.md              # этот файл
├── research.md          # Phase 0 (R1–R12)
├── data-model.md        # Phase 1
├── quickstart.md        # Phase 1
├── contracts/
│   ├── repositories.md  # AppState/Session/Auth интерфейсы
│   └── navigation.md    # state→экран, two-phase apply, реконсиляция
├── checklists/
│   └── requirements.md  # spec-quality (16/16)
└── tasks.md             # Phase 2 (/speckit-tasks — НЕ создаётся этой командой)
```

### Source Code (repository root)

```text
lib/
├── domain/
│   ├── model/app/
│   │   ├── app_state_type.dart            # NEW enum
│   │   ├── app_state_model.dart           # NEW @freezed (+ .init())
│   │   └── session_model.dart             # NEW @freezed
│   └── repository/app/
│       ├── app_state_repository.dart      # NEW контракт
│       ├── session_repository.dart        # NEW контракт
│       └── auth_repository.dart           # NEW контракт
├── data/
│   └── repository/app/
│       ├── app_state_repository_impl.dart # NEW @LazySingleton, BehaviorSubject, no-DAO
│       ├── session_repository_impl.dart   # NEW secure storage + prefs
│       └── auth_repository_impl.dart       # NEW оркестрация mutate→fetchAppState
├── di/
│   ├── register_module.dart               # NEW @module: FlutterSecureStorage + SharedPreferences(@preResolve)
│   └── global_aliases.dart                # EDIT: + appStateRepository, authRepository
├── general/
│   └── text_constants.dart                # EDIT: + sessionExpiredMessage
└── presentation/
    ├── app/
    │   ├── app_root.dart                   # EDIT: home→SplashPage, routing+sessionExpired BlocListener
    │   └── bloc/
    │       ├── app_root_bloc.dart          # EDIT: subscribe watchAppState, update/apply
    │       ├── app_root_state.dart         # EDIT: + lastAppState/appliedAppState/isReady
    │       └── app_root_event.dart         # EDIT: + updateAppState/applyAppState
    └── pages/
        ├── splash_page/splash_page.dart            # EDIT: demo flag, applyAppState on reveal-done
        ├── login_page/…                            # EDIT: real → authRepository.signIn
        ├── set_username_page/…                     # EDIT: real → authRepository.completeOnboarding
        └── settings_root_page/settings_root_page.dart  # EDIT: _logout → authRepository.logout

macos/Runner/{DebugProfile,Release}.entitlements    # EDIT: keychain-access-groups

test/
├── data/repository/app/{app_state,session,auth}_repository_impl_test.dart  # NEW unit
└── presentation/app/{bloc/app_root_bloc_test.dart, app_root_test.dart}     # NEW bloc/widget

docs/blueprints/mobile/05-presentation-layer.md (+06)  # EDIT (drift-fix): AppFeedbackHelper, two-phase splash-gate, снять app-state-spine gap
```

**Structure Decision**: Один пакет `nox_app`, слои-папки (`presentation → domain ← data`). Новый доменный кластер `model/app/` + `repository/app/`; data-impl'ы под `data/repository/app/`; app-level навигация — правка существующего `presentation/app/`. Никаких новых пакетов/роутеров — single-window `Navigator` + `GlobalKey` (блюпринт). Реконсиляция экранов — точечные правки уже существующих файлов (demo-vs-real split). Blueprint drift-fixes идут тем же change-set (Принцип II/III).

## Complexity Tracking

> Constitution Check без нарушений — таблица не заполняется.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| — | — | — |

## Phase 1 — Agent context

`CLAUDE.md` обновляется (managed-секция Spec Kit / `<!-- SPECKIT … -->` маркеры либо опциональный after_plan-hook `speckit.agent-context.update`) ссылкой на этот план. См. отчёт команды.
