# Research: Завести дизайн-систему — ассеты, токены и шрифты

**Feature**: `002-design-system-assets` | **Date**: 2026-06-15 | **Phase**: 0

Технических `NEEDS CLARIFICATION` после `/speckit-clarify` не осталось (две развилки — шрифты и иконки — разрешены владельцем). Ниже зафиксированы решения по способу заведения каждого класса ресурсов.

---

## R1. Шрифты: какие файлы, откуда, как объявить

**Decision**: Забандлить статические `.ttf`: `Roboto-Regular` (400), `Roboto-Medium` (500), `Roboto-Bold` (700), `RobotoMono-Regular` (400) в `assets/fonts/`. Объявить два семейства в `pubspec.yaml` → `fonts:` с точными именами `Roboto` и `Roboto Mono`. `flutter_gen` → `fonts.enabled` остаётся `false`.

```yaml
fonts:
  - family: Roboto
    fonts:
      - { asset: assets/fonts/Roboto-Regular.ttf, weight: 400 }
      - { asset: assets/fonts/Roboto-Medium.ttf,  weight: 500 }
      - { asset: assets/fonts/Roboto-Bold.ttf,    weight: 700 }
  - family: Roboto Mono
    fonts:
      - { asset: assets/fonts/RobotoMono-Regular.ttf, weight: 400 }
```

**Rationale**:
- Имена семейств **обязаны** точно совпадать со строками в `nox_text_theme.dart` (`_sans = 'Roboto'`, `noxMonoFamily = 'Roboto Mono'`) — иначе Flutter молча падает на дефолт.
- Набор начертаний выведен из реального использования: `noxTextTheme` задаёт `w400` (displaySmall/headlineSmall/titleLarge/bodyLarge/bodyMedium) и `w500` (titleMedium/labelLarge/labelMedium); вордмарк NOX — Bold `700` (`nox-assets/manifest.json` → brand.wordmark). `Roboto Mono` нужен только Regular (отображение `Your ID`/ключей). Бандл именно этих весов исключает faux-bold-синтез без лишнего веса.
- `fonts.enabled: false` в `flutter_gen` оставляем: семейства потребляются как строковые константы в сгенерированном `noxTextTheme`; генерируемый класс шрифтов не нужен.

**Source / license**: `Roboto` и `Roboto Mono` — Apache-2.0, Google Fonts (канонические репозитории `github.com/googlefonts/roboto` и `github.com/googlefonts/RobotoMono`, статические инстансы). Дотягиваются в `assets/fonts/` на этапе реализации; рядом кладётся `assets/fonts/README.md` с источником, версией и текстом лицензии (Apache-2.0). Бинарников шрифтов в репозитории сейчас нет — это единственный внешний артефакт, который нужно принести.

**Alternatives considered**:
- *Только Regular обоих семейств* — отклонено: w500/w700 синтезируются (faux-bold), визуальный дрейф от дизайна.
- *Полные семейства (все веса)* — отклонено: лишний вес бандла за неиспользуемые начертания.
- *Платформенный шрифт без бандла* — отклонено владельцем: на iOS/desktop `Roboto` не системный, `Roboto Mono` не системный нигде.
- *Вариативный шрифт (Roboto Flex / variable Roboto)* — отклонено: усложняет маппинг весов; статические инстансы детерминированнее для фиксированного набора весов.

---

## R2. Иконки: бандл всех SVG и сверка счётчиков

**Decision**: Скопировать **все 37** SVG-файлов из `docs/design/system/nox-assets/icons/svg/` в `assets/svg/icons/` **вербатим** (имена как в источнике, включая `*-fill.svg`). Рендер — `flutter_svg`; type-safe доступ — flutter_gen (`Assets.svg.icons.*`) поверх семантического реестра `NoxIcons` (R3).

**Rationale — реконсиляция счётчиков** (источник несамосогласован):
- На диске **37** файлов. `icons.json` ссылается на **35** уникальных svg-путей (`counts.svgFiles: 35`), `manifest.json` сообщает `svgFiles: 37` (диск). Расхождение = **2** файла, присутствующие на диске, но не упомянутые в `icons.json`: `flashlight_on.svg` и `send.svg` — это **outlined-варианты**, чья единственная используемая форма — filled (`flashlight_on-fill.svg`, `send-fill.svg`).
- `references: 38` — общее число записей в группах; `uniqueLigatures: 33` — различные `name`. Связь: 35 уникальных svg = 33 имени, из которых `forum`/`settings` имеют оба варианта (fill+outline) → +2 файла.
- **Заводим все 37** (включая 2 неиспользуемых outlined) — «завести абсолютно все ассеты». Семантический реестр покрывает 35 используемых; 2 лишних outlined остаются доступны через flutter_gen, но в реестр не добавляются (помечается в `NoxIcons`-доке). Расхождение счётчиков фиксируется здесь как известная нестыковка источника.

**Recoloring**: SVG используют `fill="currentColor"`. Цвет **не зашивается** — перекраска на стороне вызова (`SvgPicture.asset(..., colorFilter: ColorFilter.mode(color, BlendMode.srcIn))` либо `SvgGenImage.svg(colorFilter: ...)`). Поскольку виджеты вне scope, заводим только ассеты + аксессоры; контракт перекраски документируется, но не реализуется в виджете.

**Alternatives considered**:
- *Бандлить только 35 используемых* — отклонено: противоречит «завести абсолютно все».
- *pub-пакет `material_symbols_icons`* — отклонено владельцем (см. clarify): нужны файлы-ассеты в проекте; инфраструктура pubspec уже под SVG.

---

## R3. Семантический icon-реестр `NoxIcons`

**Decision**: Рукописный `lib/design/nox_icons.dart` — `abstract final class NoxIcons` с именованными статическими геттерами, **ссылающимися** на flutter_gen-аксессоры (`Assets.svg.icons.forumFill`), а не на строки путей. Имена геттеров — по глифу+FILL (`forum`/`forumFill`, `settings`/`settingsFill`, `send`/`sendFill`, `flashlightOn`/`flashlightOff`), производные от `icons.json`. Метаданные (назначение/`use`, FILL) — в doc-комментариях; группировка (navigation/actions/status/fileTypes/emptyStates/misc) сохраняется как секции.

**Rationale**: Единственный канал строк путей — flutter_gen (FR-012); `NoxIcons` несёт только семантику и метаданные, которых нет в `icons.json`-агностичном flutter_gen. Keying по глифу (не по экранной роли вроде `chatsTabSelected`) — потому что экраны/виджеты вне scope; семантические роли преждевременны без потребителя. Подменённые имена (`music_note` = audio, `draft` = прочий файл) маппятся корректно с комментарием-пояснением.

**Alternatives considered**:
- *Keying по экранной роли* — отклонено: нет потребителей (виджеты вне scope); привязка к ролям — задача экранов.
- *Только flutter_gen без реестра* — отклонено: теряются FILL/назначение и группировка из `icons.json`, которые ценны для будущих экранов и являются частью «завести токены».

---

## R4. Бренд-логотип и иллюстрации

**Decision**: Скопировать `nox-assets/brand/logo.png` → `assets/png/logo.png` (растровый плейсхолдер для splash). Скопировать три иллюстрации `nox-assets/illustrations/empty-*.svg` → `assets/svg/illustrations/` вербатим. **Не** копировать `logo-reference.png` (reference-only moodboard). Финальный вектор логотипа, launcher app-icon и финальные иллюстрации — pending-ордера, **вне scope**.

**Rationale**: «Завести абсолютно все» = занести существующие шиппинговые/плейсхолдер-ассеты (`status: ready|placeholder` в `manifest.json`); reference-only и pending исключаются явно (FR-006, FR-015). Иллюстрации читаются и на light, и на dark (тонкий контур + brand-акценты, прозрачный фон — спека `illustrations/README.md`).

**Alternatives considered**:
- *Ждать финальных ассетов* — отклонено: блокирует заведение дизайн-системы; плейсхолдеры специально подготовлены для wiring.
- *Бандлить `logo-reference.png`* — отклонено: не шиппинговый ассет.

---

## R5. flutter_gen и декларации `pubspec.yaml`

**Decision**: Обновить `pubspec.yaml` → `assets:` так, чтобы перечислить новые подпапки явно (Flutter включает файлы только из перечисленных директорий, без рекурсии):

```yaml
assets:
  - assets/png/
  - assets/svg/icons/
  - assets/svg/illustrations/
  - assets/animation/
```

`flutter_gen` (`output: lib/design/gen/`, `flutter_svg: true`, `line_length: 140`) генерирует `Assets.png.logo`, `Assets.svg.icons.*`, `Assets.svg.illustrations.*`. Прогон — `fvm dart run build_runner build --delete-conflicting-outputs` (один проход вместе с freezed/json/injectable). `lib/design/gen/` остаётся в `.gitignore` — аксессоры не коммитятся, воспроизводятся кодогеном (в т. ч. в CI).

**Rationale**: Раскладка по типу (`svg/icons`, `svg/illustrations`, `png`, `fonts`) даёт чистые вложенные аксессоры и отделяет иконки от иллюстраций. Текущие «голые» записи (`assets/`, `assets/svg/`) заменяются точными подпапками, чтобы не тянуть пустые `.gitkeep` и держать список явным.

**Alternatives considered**:
- *Плоско всё в `assets/svg/`* — отклонено: смешивает иконки и иллюстрации, менее читаемые аксессоры.
- *Коммитить `assets.gen.dart`* — отклонено: противоречит блюпринту (gitignored, codegen-first).

---

## R6. Сверка и синхронизация токенов

**Decision**: Подход — **сверка + синхронизация** (генерационный пайплайн JSON→Dart вне scope, по clarify). Конкретно:
- `nox_color_scheme.dart`, `nox_text_theme.dart`, `nox_brand.dart` — уже **побайтово совпадают** с `nox-handoff/flutter/` → только верификация (без правок).
- `nox_tokens.dart` — отличается **только форматированием** (`dart format -l 140` схлопнул выравнивание комментариев); значения идентичны → ре-синхронизация: считать lib-версию канонично-форматированной, ничего не менять по значениям; добавить регрессионный тест значений (ниже).
- Источник истины — `docs/design/system/nox-handoff/` (не `nox-handoff-2/` — помеченный конституцией дубль `TODO(handoff-duplicate)`; токены/Dart идентичны, отличается лишь out-of-scope `flutter/widgets/`).

**Регрессионный тест согласованности**: `test/design/tokens_sync_test.dart` — ассерты репрезентативных значений против спецификации/хендофа: spacing `s4 == 16`, radius `xl == 28`, elevation `level2 == 3`, duration `push == 300ms`, type `bodyMedium.fontSize == 14` / `titleMedium.fontWeight == w500`, brand splash-фон/QR-поверхность, наличие 8-цветовой палитры аватаров. Это даёт автоматическую защиту от дрейфа без хрупкого побайтового diff форматирования.

**Rationale**: Токены уже доставлены и эквивалентны источнику; занос «с нуля» не нужен. Пайплайн Style Dictionary — отдельная будущая задача (clarify). Репрезентативные ассерты тестируемы и устойчивы к косметике.

**Alternatives considered**:
- *Настроить Style Dictionary сейчас* — отклонено владельцем (отдельная задача).
- *Побайтовый file-diff в тесте* — отклонено: хрупко к форматированию/комментариям.

---

## R7. Полная M3-шкала размеров шрифта в `AppTextStyleTokens`

**Decision**: Заменить три ad-hoc стиля (`body`/`title`/`caption`) на **9 ролей** M3-шкалы, по значениям `noxTextTheme`. Каждая — color-injecting фабрика с `.sp`-размером и `letterSpacing`, **без** `height` и **без** `fontFamily` (height несёт `noxTextTheme`; семейство наследуется из темы — `Roboto`):

| Роль | fontSize (sp) | fontWeight |
|---|---|---|
| `displaySmall` | 36 | w400 |
| `headlineSmall` | 24 | w400 |
| `titleLarge` | 22 | w400 |
| `titleMedium` | 16 | w500 |
| `bodyLarge` | 16 | w400 |
| `bodyMedium` | 14 | w400 |
| `labelLarge` | 14 | w500 |
| `labelMedium` | 12 | w500 |
| `labelSmall` | 11 | w500 |

**Rationale**: «Завести токены размеров шрифта» = полная шкала, а не произвольное подмножество (FR-009). Отсутствие `height`/`fontFamily` в фабриках — прямое требование блюпринта §3.2/§5 (height задаёт `noxTextTheme`, иначе квадратичный скейл; семейство — из темы). Внешних потребителей `body`/`title`/`caption` в `lib/` нет (проверено grep) → замена безопасна.

**Alternatives considered**:
- *Оставить body/title/caption + добавить недостающее* — отклонено: непарность с M3-ролями, путаница имён.
- *Задавать height в фабриках* — отклонено: дублирует/конфликтует с `noxTextTheme`, ломает скейл (§3.2).

---

## R8. Удаление `AppImagesTokens`

**Decision**: Удалить `lib/design/app_images_tokens.dart`. Пути к картинкам — только через flutter_gen (`Assets.png.logo`, `Assets.svg.illustrations.*`). Внешних потребителей в `lib/` нет (проверено grep) → удаление безопасно.

**Rationale**: Разрешение «обоих каналов» блюпринта §7 в пользу flutter_gen (clarify); текущие пути `AppImagesTokens` битые (`assets/png/logo.png`, `assets/png/empty_state.png`). Единый авторитетный канал (FR-007, FR-012). Семантический слой остаётся только для иконок (`NoxIcons`), где источник несёт метаданные.

**Alternatives considered**:
- *Оставить как тонкую обёртку над flutter_gen* — отклонено владельцем (clarify): второй слой без выгоды для 4 файлов; flutter_gen-аксессоры самодостаточны.

---

## R9. Точки реконсиляции блюпринта (Принцип III)

Изменения фичи расходятся с текущим текстом блюпринта — приводятся в соответствие в том же change-set (`docs/blueprints/mobile/06-theming.md`):

- **§0 (файловое дерево)** — добавить `nox_icons.dart`, убрать `app_images_tokens.dart`.
- **§1 (источник типографики)** — назвать забандленные семейства `Roboto` 400/500/700 + `Roboto Mono` 400.
- **§5 (`AppTextStyleTokens` + footnote шрифтов)** — полная 9-ролевая шкала вместо skeleton `body/title/caption`; footnote (line 443) «Семейства бандлятся (или берётся платформенный дефолт)» → теперь забандлены.
- **§7 (картиночные ассеты / «оба канала»)** — разрешено: `AppImagesTokens` удалён, flutter_gen авторитетен; **иконки** (картиночные ассеты через flutter_gen) и реестр `NoxIcons` заводятся здесь же. Отдельной icon-секции в `06-theming.md` нет (§8 — это `lib/general/`), поэтому иконки относятся к §7, а не к новому §8.

**Rationale**: Конституция (Принцип III) требует чинить дрейф код↔блюпринт в том же change-set. Эти правки — документация, не код; выполняются на этапе реализации вместе с кодом.
