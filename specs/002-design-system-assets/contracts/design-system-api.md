# Contract: Публичная Dart-поверхность дизайн-системы

**Feature**: `002-design-system-assets` | **Date**: 2026-06-15 | **Phase**: 1

У фичи нет внешнего сетевого/CLI-интерфейса. «Контракт» здесь — **публичная Dart-поверхность** `lib/design`, которую этот срез заводит/меняет и на которую будут опираться будущие виджеты/экраны. Описаны сигнатуры и инварианты, **не** реализация. Сырых строк путей и хардкод-цветов в потребителях быть не должно — только эти точки доступа.

---

## 1. `NoxIcons` — семантический icon-реестр (NEW)

`lib/design/nox_icons.dart`

```dart
abstract final class NoxIcons {
  const NoxIcons._();

  // navigation
  static SvgGenImage get forum        => Assets.svg.icons.forum;        // outlined — Chats tab unselected
  static SvgGenImage get forumFill    => Assets.svg.icons.forumFill;    // filled   — Chats tab selected
  static SvgGenImage get settings     => Assets.svg.icons.settings;
  static SvgGenImage get settingsFill => Assets.svg.icons.settingsFill;
  static SvgGenImage get add          => Assets.svg.icons.add;          // center FAB
  // actions: arrowBack, contentPaste, qrCodeScanner, attachFile, sendFill,
  //          flashlightOnFill, flashlightOff, cameraswitch, search,
  //          visibility, visibilityOff, contentCopy, qrCode, download, edit, close
  // status:  schedule (pending), check (sent), error
  // fileTypes: image, videocam, musicNote, pictureAsPdf, description,
  //            tableChart, article, folderZip, draft
  // emptyStates: chatBubble, folderOpen  (forum/forumFill reused from navigation)
  // misc: error (reused)
}
```

**Контракт-инварианты:**
- Каждый геттер возвращает `SvgGenImage` (flutter_gen) — **ссылку** на ассет, не строку пути.
- Покрывает все **35** используемых svg из `icons.json` (38 references → 33 имени, fill/outline различимы). 2 неиспользуемых outlined (`flashlight_on.svg`, `send.svg`) доступны через `Assets.svg.icons.*`, но не в `NoxIcons`.
- Перекраска — на стороне вызова: `NoxIcons.forum.svg(colorFilter: ColorFilter.mode(color, BlendMode.srcIn))`. Цвет не зашит (`currentColor`).
- Doc-комментарий каждого геттера несёт FILL + назначение (`use`) + группу из `icons.json`.

## 2. `AppTextStyleTokens` — размеры шрифта (UPDATED)

`lib/design/app_text_style_tokens.dart`. Color-injecting фабрики, `.sp`-размеры, **без** `height` и `fontFamily` (height — в `noxTextTheme`; семейство `Roboto` — из темы).

```dart
abstract final class AppTextStyleTokens {
  const AppTextStyleTokens._();
  static TextStyle displaySmall({required Color color}); // 36.sp w400
  static TextStyle headlineSmall({required Color color}); // 24.sp w400
  static TextStyle titleLarge({required Color color});   // 22.sp w400
  static TextStyle titleMedium({required Color color});  // 16.sp w500
  static TextStyle bodyLarge({required Color color});    // 16.sp w400
  static TextStyle bodyMedium({required Color color});   // 14.sp w400
  static TextStyle labelLarge({required Color color});   // 14.sp w500
  static TextStyle labelMedium({required Color color});  // 12.sp w500
}
```

**Контракт-инварианты:** 8 ролей соответствуют M3-шкале `noxTextTheme` (data-model §2.2). Прежние `body/title/caption` удалены (внешних потребителей нет). Вызов — только внутри `build` под `ScreenUtilInit` (блюпринт §3.2).

## 3. `Assets` — type-safe пути (GENERATED, flutter_gen)

`lib/design/gen/assets.gen.dart` (gitignored, не редактируется).

```dart
Assets.png.logo                       // SvgGenImage? нет — AssetGenImage (PNG)
Assets.svg.icons.<name>               // SvgGenImage (37 шт.)
Assets.svg.illustrations.emptyChats   // SvgGenImage
Assets.svg.illustrations.emptyMessages
Assets.svg.illustrations.emptyFiles
```

**Контракт-инвариант:** единственный канал строк путей к ассетам. `AppImagesTokens` **удалён**.

## 4. Тема и токены (EXISTING — verify-only, без изменения API)

Поверхность уже зафиксирована блюпринтом §1–§7 (color/typography §1, AppColors §2, AppTheme §3, spacing §4/§4.1, AppTextStyleTokens §5, overlay §6, assets §7) и не меняется этой фичей (только верификация согласованности):

```dart
AppTheme.light() / AppTheme.dark()                  // ThemeData (M3, light/dark)
Theme.of(context).colorScheme.<role>                // noxLightScheme/noxDarkScheme
Theme.of(context).textTheme.<role>                  // noxTextTheme (Roboto / Roboto Mono)
context.appColors.<semanticRole>                    // ThemeExtension<AppColors>
NoxSpacing.sN / NoxRadius.* / NoxRadius.bubble(isOwn)
NoxElevation.levelN / NoxDuration.* / NoxEasing.*
NoxBrand.<brandFixed> / noxAvatarColor(name) / noxInitials(name)
AppSpacingTokens.sN / AppOverlayStyleTokens.light|dark
const String noxMonoFamily = 'Roboto Mono';
```

**Контракт-инвариант:** значения этих API согласованы с `docs/design/system/nox-handoff/` (data-model §2; регрессионный тест R6).

## 5. `pubspec.yaml` (декларативный контракт сборки)

- `fonts:` объявляет `Roboto` (400/500/700) + `Roboto Mono` (400) с файлами `assets/fonts/*.ttf`.
- `assets:` перечисляет `assets/png/`, `assets/svg/icons/`, `assets/svg/illustrations/`, `assets/animation/`.
- `flutter_gen` (`output: lib/design/gen/`, `flutter_svg: true`, `fonts.enabled: false`, `line_length: 140`) — без изменений конфигурации.

## 6. Граница (что НЕ в контракте)

Виджеты/UI-Kit/примитивы (`nox_primitives.dart`, `nox_widgets.dart`, `nox_scaffold.dart`), экраны, рантайм-логика — **вне scope**. Контракт описывает только токены/ассеты и точки доступа к ним.
