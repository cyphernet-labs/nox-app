# Contract — Публичные API новых виджетов + BLoC-контракты (M2)

Новые переиспользуемые виджеты — без BLoC, токен-дисциплина, `NoxIcons` SVG, копирайт через `TextConstants`. Конструкторы `const` где возможно. Имена — `App*Widget`. Все должны корректно резолвиться под `pumpApp`.

## widgets/onboarding/

### `AppOnboardCardWidget`
Онбординг-голова (logo + wordmark + brand hairline) + слот контента; центральная карточка на десктопе. Переиспользуется 2.1, 2.3 и desktop-denied 2.2.
```
AppOnboardCardWidget({
  required Widget child,          // поле(я) + действия конкретного экрана
  double maxWidth = 440,          // десктоп cap карточки
  bool showHairline = true,
})
```
- Голова: `Image(Assets.png.logo...)` + `AppWordmarkWidget()` + `AppSplashHairlineWidget()` (reuse, без дублирования).
- На десктопе — `Center`→`ConstrainedBox(maxWidth)`; head + `child` в колонке, отступы `AppSpacingTokens`.
- Тема — `ColorScheme` (карточка `surface`/`surfaceContainer`); не brand-fixed.

### `AppIdFieldWidget`
Моно многострочное ID-поле (2.1) с suffix-`Paste`.
```
AppIdFieldWidget({
  required TextEditingController controller,
  required bool canPaste,         // буфер непуст
  required VoidCallback onPaste,
  ValueChanged<String>? onChanged,
  VoidCallback? onSubmitted,      // Enter/Go == Sign in
  String? errorText,
  bool enabled = true,
})
```
- `TextField(maxLines: null)` (растёт по высоте), стиль — `AppTextStyleTokens.monoBody(color: ...)` (`Roboto Mono`).
- placeholder `TextConstants.loginIdHint`; label `TextConstants.loginIdLabel`; suffix `IconButton(NoxIcons.contentPaste, tooltip: actionPaste, onPressed: canPaste ? onPaste : null)`.
- Без клиентской валидации формата (FR-011).

### `AppLabeledFieldWidget`
Labeled-поле + counter + suffix-спиннер доступности + `errorText` (2.3, 6.1).
```
AppLabeledFieldWidget({
  required TextEditingController controller,
  required String label,
  required int maxLength,         // 32 (2.3) / 64 (6.1)
  String? helperText,
  String? placeholder,
  String? errorText,
  bool checking = false,          // suffix-спиннер (Checking-availability)
  ValueChanged<String>? onChanged,
  VoidCallback? onSubmitted,
  bool enabled = true,
})
```
- `TextField` + `maxLength` → встроенный counter (тема `noxInputDecorationTheme` уже задаёт `counterStyle`/`helperStyle`).
- `checking` → `suffixIcon: AppSpinnerWidget(size: 18)`.
- `errorText` → стандартный M3 error (тема `cs.error`).

## widgets/qr/

### `AppQrOverlayWidget`
Brand-fixed QR-overlay поверх нейтрального плейсхолдера (2.2). **Единственное brand-fixed исключение M2** (вне `ColorScheme`, `design-system.md` §9.9).
```
AppQrOverlayWidget({
  double reticleFraction = 0.7,   // ≈70% ширины
})
```
- Маска вокруг прицела — `#000000` @ 55% (задокументированный brand-fixed `const` в файле виджета, ссылка §9.9).
- Прицел — stroke `NoxBrand.white` (#FAFAFA) 3dp, углы `NoxRadius.m` (12).
- Инструкция (`TextConstants.qrAimHint`) — текст `NoxBrand.white`.
- Нейтральный плейсхолдер позади — тематический fill (`surfaceContainerHighest`); рисуется родителем (`QrScanPage`), не темизируется только overlay.

## Переиспользуемые виджеты/страницы (M1, без изменений)

| Сущность | Сигнатура | Роль в M2 |
|---|---|---|
| `AppWordmarkWidget` | `const AppWordmarkWidget({super.key, this.color})` | Голова `OnboardCard` + мобайл `AppBar`. |
| `AppSplashHairlineWidget` | `const AppSplashHairlineWidget({super.key})` | Hairline под wordmark. |
| `AppWindowTitlebarWidget` | `const AppWindowTitlebarWidget({required this.title})` | Десктоп-оконный заголовок (`NOX · Sign in`/`Set up`/`Scan QR`). |
| `AppSpinnerWidget` | `AppSpinnerWidget({this.size = 24, this.color, this.strokeWidth = 3})` | Спиннер в кнопке (Loading) + suffix-спиннер (Checking). |
| `AppInfoBannerWidget` | (M1) icon+message+action | (опц.) офлайн/инфо-баннер, если потребуется. |
| `RoutePlaceholderPage` | `static Route<void> route({required String destinationLabel})` | Заглушки переходов (исходы/`Scan QR`/`Done`/`Create`-success). |
| `AppErrorPage` / `ErrorPageParams` | `static Route<void> route({required ErrorPageParams params})`; `ErrorPageParams.fatal({mode})` | Fatal-исход → 3.1 (blocking). |

## Контракты BLoC (2.1/2.3/6.1)

Конвенция (по `ItemListBloc`/`AppRootBloc`): `class <Page>Bloc extends BaseBloc<<Page>Event, <Page>State>`; ctor регистрирует `on<...>` (debounce-transformer для `*Changed`); `BaseBloc.executeLogic(..., onError: ...)` для submit (фейковый `Future`). Состояние — value-state + `copyWith` (см. [data-model.md](../data-model.md)). BLoC **не** в DI; страница создаёт/закрывает его (`initState`/`dispose`), `BlocProvider.value` + `BlocBuilder`.

```
// debounce transformer (в каждом BLoC с *Changed)
EventTransformer<E> _debounce<E>() =>
    (events, mapper) => events.debounce(const Duration(milliseconds: 300)).switchMap(mapper);
on<NameChanged>(_onNameChanged, transformer: _debounce());
on<DonePressed>(_onDonePressed);   // submit через executeLogic(onError:)
```

| BLoC | Events | Заметки |
|---|---|---|
| `LoginBloc` | `initialize`, `idChanged(String)`, `clipboardChanged(bool)`, `pastePressed`, `signInPressed`, `setOutcome(LoginOutcome)` | Нет клиентской валидации ID; `canSubmit => id.trim().isNotEmpty`. |
| `SetUsernameBloc` | `initialize`, `nameChanged(String)` (debounced), `donePressed`, `setOutcome(UsernameOutcome)` | charset клиентский (`[A-Za-z0-9._-]`) → availability (мок, case-sensitive). |
| `CreateChatBloc` | `initialize`, `nameChanged(String)` (debounced), `createPressed`, `setOutcome(CreateChatOutcome)` | charset свободный → availability (мок). |

## Контракт тестов

- Каждый новый `App*Widget`: widget-тест (рендер + интеракция) + golden (light/dark) под `test/presentation/widgets/{onboarding,qr}/`. Спиннер-голдены — `settle: false`.
- Каждый BLoC: `bloc_test` (bare-имена сабстейтов; `Error`/fatal только при переданном `onError`; debounce-кейсы с `await`).
- Микрокопия — только из `TextConstants`; в тестах ассертить по константам.
- `AppQrOverlayWidget` golden фиксирует brand-fixed цвета (#FAFAFA / #000@55%) одинаковыми в light и dark.
