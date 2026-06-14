# Дизайн-система NOX

> Версия 0.2, 2026-05-29 (после аудита покрытия). Основа для Figma-макетов и реализации на Flutter / Material Design 3. Цветовая база **извлечена из референса логотипа** [`assets/logo-reference.png`](assets/logo-reference.png) (см. «Цвет»). Общие UI-решения и микрокопирайт — в [overview.md](overview.md) и [screens/](screens/README.md); здесь — токены и стиль, на которые ссылаются экраны.

Документ описывает **две вещи раздельно**:

1. **Функциональная схема** (M3 `ColorScheme`, seed = бирюза) — спокойная, для интерактивных элементов, поверхностей, текста. Адаптируется light/dark.
2. **Бренд-палитра** (мульти-хью из логотипа) — выразительная, для логотипа и splash. **Не** используется для primary-кнопок.

**Два намеренных исключения из темизации** (фиксированные, не зависят от light/dark): фон **splash** (`brand/canvas-dark`) и поверхность **QR-кода** в bottom sheet 7.1 (`brand/qr-surface`).

---

## 1. Бренд

### Логотип

- Источник/мудборд: [`assets/logo-reference.png`](assets/logo-reference.png) — маска в стиле «разноцветные мазки» на тёмном сине-зелёном фоне.
- Характер: тёмный canvas + многоцветные «всплески» (бирюза, золото, красный, лайм, синий).
- **Нужен ассет:** векторный логотип (SVG), full-color на тёмном. На текущем этапе логотип используется только на splash (тёмный фон) → достаточно одного варианта.

### Wordmark «NOX»

- Текст `NOX`, всегда верхний регистр.
- Шрифт — системный (Roboto / SF Pro), **Bold (700)**, letter-spacing **+0.12em**.
- Цвет: на splash — `brand/white` (#FAFAFA) на `brand/canvas-dark`; в AppBar (2.1, 2.3, 5.1) — `colorScheme.onSurface`.

### Splash (brand-fixed)

- Фон — фиксированный токен **`brand/canvas-dark` = #0C2424** (не зависит от темы; одно из двух исключений темизации). Логотип full-color по центру, wordmark `NOX` (#FAFAFA) под ним. Анимация — см. [splash.md](screens/splash.md).

---

## 2. Цвет

### 2.1. Source / seed-цвета (извлечены из логотипа)

| Токен | HEX | Происхождение |
|---|---|---|
| `seed/primary` (бирюза) | **#12B4B4** | доминирующий vivid-цвет логотипа (`#0CB4B4`) |
| `seed/secondary` (золото) | **#F4C20C** | `#FCCC0C` / `#FCB40C` |
| `seed/tertiary` (коралл) | **#FB7A12** | `#FC840C` |
| `brand/canvas-dark` | **#0C2424** | доминирующий фон логотипа (56% пикселей) |
| `brand/ink` | **#0C0C0C** | тёмные зоны |

Полные `ColorScheme` (light + dark) **генерируются из seed** через `ColorScheme.fromSeed(seedColor: Color(0xFF12B4B4))` с override `secondary`/`tertiary` из золота/коралла, либо собираются в [Material Theme Builder](https://m3.material.io/theme-builder). Значения §2.2–2.3 — **выверенный старт** (тон по логике M3 для бирюзового seed), не финальный замер; регенерация из seed обязана давать близкие значения.

### 2.2. Функциональная схема — Light

| Роль | HEX |
|---|---|
| primary | `#006A6A` |
| onPrimary | `#FFFFFF` |
| primaryContainer | `#6FF7F6` |
| onPrimaryContainer | `#002020` |
| secondary | `#4A6363` |
| onSecondary | `#FFFFFF` |
| secondaryContainer | `#CCE8E7` |
| onSecondaryContainer | `#051F1F` |
| tertiary | `#6F5E00` |
| onTertiary | `#FFFFFF` |
| tertiaryContainer | `#FAE08A` |
| onTertiaryContainer | `#221B00` |
| error | `#BA1A1A` |
| onError | `#FFFFFF` |
| errorContainer | `#FFDAD6` |
| onErrorContainer | `#410002` |
| surface | `#F4FBFA` |
| onSurface | `#161D1D` |
| surfaceVariant | `#DAE5E3` |
| onSurfaceVariant | `#3F4948` |
| outline | `#6F7979` |
| outlineVariant | `#BEC9C8` |
| surfaceContainerLowest | `#FFFFFF` |
| surfaceContainerLow | `#EFF5F4` |
| surfaceContainer | `#E9EFEE` |
| surfaceContainerHigh | `#E3EAE9` |
| surfaceContainerHighest | `#DDE4E3` |
| inverseSurface | `#2B3231` |
| onInverseSurface (inverseOnSurface) | `#ECF2F1` |
| inversePrimary | `#4CDADA` |
| surfaceTint | `#006A6A` |
| shadow | `#000000` |
| scrim | `#000000` |

### 2.3. Функциональная схема — Dark

| Роль | HEX |
|---|---|
| primary | `#4CDADA` |
| onPrimary | `#003737` |
| primaryContainer | `#004F4F` |
| onPrimaryContainer | `#6FF7F6` |
| secondary | `#B0CCCB` |
| onSecondary | `#1B3534` |
| secondaryContainer | `#324B4A` |
| onSecondaryContainer | `#CCE8E7` |
| tertiary | `#DEC56B` |
| onTertiary | `#3A2F00` |
| tertiaryContainer | `#534619` |
| onTertiaryContainer | `#FAE08A` |
| error | `#FFB4AB` |
| onError | `#690005` |
| errorContainer | `#93000A` |
| onErrorContainer | `#FFDAD6` |
| surface | `#0E1514` |
| onSurface | `#DDE4E3` |
| surfaceVariant | `#3F4948` |
| onSurfaceVariant | `#BEC9C8` |
| outline | `#899393` |
| outlineVariant | `#4E5B58` |
| surfaceContainerLowest | `#090F0F` |
| surfaceContainerLow | `#161D1D` |
| surfaceContainer | `#1A2120` |
| surfaceContainerHigh | `#242B2B` |
| surfaceContainerHighest | `#2F3635` |
| inverseSurface | `#DDE4E3` |
| onInverseSurface (inverseOnSurface) | `#2B3231` |
| inversePrimary | `#006A6A` |
| surfaceTint | `#4CDADA` |
| shadow | `#000000` |
| scrim | `#000000` |

> Splash-фон `#0C2424` сознательно темнее/зеленее, чем dark `surface` — это брендовый токен, не роль схемы.

### 2.4. Бренд-палитра (выразительная, мульти-хью)

Используется для **логотипа и splash** и редких декоративных акцентов. Не для primary-действий. (Фоны аватаров — отдельная палитра §2.5, производная от этих хью, но контраст-tuned.)

| Токен | HEX |
|---|---|
| `brand/teal` | #12B4B4 |
| `brand/teal-deep` | #0E7C7C |
| `brand/gold` | #F4C20C |
| `brand/amber` | #FBB00C |
| `brand/coral` | #FB7A12 |
| `brand/red` | #E11D1D |
| `brand/lime` | #8FA50C |
| `brand/blue` | #2E6FB0 |
| `brand/white` | #FAFAFA |
| `brand/canvas-dark` | #0C2424 |
| `brand/ink` | #0C0C0C |
| `brand/qr-surface` (fixed light) | #FFFFFF |
| `brand/qr-ink` (QR-модули) | #0C0C0C |

### 2.5. Палитра генерируемых аватаров (avatar-only)

Детерминированный фон по хешу имени (см. [overview.md / Generated avatar](overview.md#generated-avatar-для-чатов)): `palette[ hash(name) % 8 ]`. Это **отдельная, контраст-выверенная** палитра — затемнённые производные от бренд-хью; `violet` и `green` существуют только здесь (в бренд-идентике их нет). Инициалы — белые **#FFFFFF**.

| # | Фон | Хью | Контраст к #FFFFFF |
|---|---|---|---|
| 0 | #0E7C7C | teal | ~5.0:1 |
| 1 | #8A6A00 | gold-deep | ~5.1:1 |
| 2 | #AD4A15 | coral-deep | ~4.9:1 |
| 3 | #5C7300 | lime-deep | ~5.4:1 |
| 4 | #2E6FB0 | blue | ~5.2:1 |
| 5 | #C0392B | red | ~5.4:1 |
| 6 | #7A4DB3 | violet | ~5.9:1 |
| 7 | #1E7268 | green | ~5.7:1 |

Все 8 фонов дают контраст с белым **≥ 4.5:1** (WCAG AA для обычного текста; пересчитано). **Fallback** (имя без корректных инициалов — эмодзи/символы/пусто): glyph `forum` (Material Symbols) белым #FFFFFF на том же hash-фоне.

### 2.6. Доступность

- Контраст текста к фону — **WCAG AA** (≥ 4.5:1 для body, ≥ 3:1 для крупного / иконок).
- Не кодировать смысл только цветом: статусы сообщений и ошибки сопровождаются иконкой/текстом.
- Метаданные в bubble (время/статус) — не ниже AA для своего размера; см. §9.2 (непрозрачность таймштампа 70%).

---

## 3. Типографика

Семейства:
- **Sans (основное)** — системное: Roboto (Android) / SF Pro (iOS).
- **Mono** — `Roboto Mono` (Android) / `SF Mono` (iOS) / generic `monospace` fallback. Используется только для идентификатора в 7.1 (метрики как Body Large: 16 / 24).
- **Wordmark `NOX`** — Title Large / Bold (700), letter-spacing +0.12em (отдельно от шкалы).

Шкала — M3 type scale:

| Token (M3) | Size / Line | Weight | Применение в NOX |
|---|---|---|---|
| Display Small | 36 / 44 | 400 | — (резерв) |
| Headline Small | 24 / 32 | 400 | заголовок empty-state; крупный body-Header имени чата (5.4); title `AlertDialog` (Logout) |
| Title Large | 22 / 28 | 400 | AppBar title (имя чата 5.2/5.4, `Settings`, `New chat`, имя файла 5.3) |
| Title Medium | 16 / 24 | 500 | имя чата в списке (5.1); имя автора в ленте (5.2); filename в 5.3 / ячейке 5.4 / file-chip |
| Body Large | 16 / 24 | 400 | текст сообщения; поля ввода; маска/ID (mono-семейство) |
| Body Medium | 14 / 20 | 400 | превью последнего сообщения; helperText; размер файла; `AlertDialog` body |
| Label Large | 14 / 20 | 500 | текст кнопок (`Sign in`, `Create`, `Done`, `Try again`) |
| Label Medium | 12 / 16 | 500 | подписи табов; counter `N/32`, `N/64` |
| Label Small | 11 / 16 | 500 | время в bubble; unread-badge |

---

## 4. Форма (corner radius)

| Token | Радиус | Применение |
|---|---|---|
| `shape/none` | 0 | edge-to-edge видео (2.2) |
| `shape/xs` | 4 | `TextField` (outlined), file-chip |
| `shape/s` | 8 | малые чипы, сегменты `SegmentedButton` |
| `shape/m` | 12 | `Card` (identity-card) |
| `shape/l` | 16 | message bubble (база) |
| `shape/xl` | 28 | bottom sheet (верхние углы), `AlertDialog` |
| `shape/full` | stadium / круг | `FilledButton`, `TextButton`, `SearchBar`, `Badge`, **docked FAB «+» (круг)** |

**Message bubble:** база `shape/l` (16); «свой» угол (нижний-правый) и «чужой» (нижний-левый) скашиваются до 4 — лёгкая ассиметрия вместо «хвоста».
**FAB «+»:** круглый (`shape/full`), под него рассчитан `CircularNotchedRectangle` нижней панели (см. §9.1).

---

## 5. Высота (elevation, M3 tonal)

| Level | dp | Применение |
|---|---|---|
| 0 | 0 | плоские поверхности, AppBar (по умолчанию) |
| 1 | 1 | `Card`, приподнятые list-поверхности |
| 2 | 3 | `BottomAppBar` (нижняя панель), `SearchBar` |
| 3 | 6 | docked FAB «+», `MaterialBanner` |
| 4 | 8 | — |
| 5 | 12 | `AlertDialog`, modal bottom sheet |

Тёмная тема: высота передаётся **tonal-overlay** (M3), не тенями.

---

## 6. Сетка и отступы

База — **4dp**. Токены: `space/1`=4, `space/2`=8, `space/3`=12, `space/4`=16, `space/6`=24, `space/8`=32.

- **Горизонтальные поля экрана:** 16 (`space/4`).
- **List item (5.1):** высота ≥ 72; паддинги 16 / 12; аватар 40, gap 16.
- **Message bubble:** padding 12×8; max-width 80%; gap внутри группы 2, между группами 12.
- **Composer (5.2):** вертикальный padding 8, иконки 48×48.
- **Min tap-target:** 48×48 во всех интерактивных элементах.

---

## 7. Движение (motion)

M3 motion. Easing: `emphasized` (вход/выход), `standard` (мелкие изменения).

| Назначение | Длительность | Easing |
|---|---|---|
| Splash появление | ~400 мс | emphasized-decelerate |
| Переход между экранами (push) | 300 мс | emphasized |
| Переключение табов (4.1) | без слайда (`IndexedStack`), fade ≤ 150 мс | standard |
| Snackbar in/out | 150 / 75 мс | standard |
| Раскрытие bottom sheet | 300 мс | emphasized-decelerate |
| State-layer / ripple | M3 default | — |

Циклических/бесконечных анимаций нет (splash — однократная).

---

## 8. Иконография

- Набор для Figma — **Material Symbols Rounded** (weight 400, optical 24, grade 0). Во Flutter им соответствуют `Icons.*` (Material Icons) либо пакет `material_symbols_icons` (`Symbols.*`); имена в спеках экранов даны как `Icons.*`, глиф тот же — **авторитетный для макета набор = Material Symbols Rounded**.
- Размер по умолчанию — 24; крупная иконка на 3.1 / 5.3 — 48–96.
- **Навигация (4.1):** Chats — `forum` (unselected `forum_outlined`), Settings — `settings` (unselected `settings_outlined`), центр — `add`.
- **Действия:** back `arrow_back`, paste `content_paste`, scan `qr_code_scanner`, attach `attach_file`, send `send`, flashlight `flashlight_on/off`, switch camera `cameraswitch`, search `search`, show/hide `visibility`/`visibility_off`, copy `content_copy`, QR `qr_code`, save `download`, edit `edit`, remove-attachment `close`.
- **Статусы сообщений:** `schedule` (pending), `check` (sent), `error_outline` (error) — цвета см. §9.2 / [chat.md](screens/chat.md).
- **Типы файлов:** единая таблица в [overview.md / Файлы](overview.md#файлы-иконки-типов-без-превью).
- **Default-иконка ошибки (3.1):** `error_outline`.

---

## 9. Токены компонентов

Цвета — через `ColorScheme` (адаптируются), кроме явных brand-fixed токенов.

### 9.1. Нижняя панель + docked FAB (4.1)

| Часть | Токен |
|---|---|
| Фон `BottomAppBar` | `surfaceContainer`, elevation 2, `shape` notch = `CircularNotchedRectangle` |
| Таб selected (иконка+подпись) | `primary` |
| Таб unselected | `onSurfaceVariant` |
| FAB «+» форма | круг (`shape/full`) |
| FAB «+» фон / иконка | `primaryContainer` / `onPrimaryContainer` |
| FAB elevation | 3 (6dp) |

### 9.2. Message bubble (5.2)

| Часть | Свой | Чужой |
|---|---|---|
| Фон | `primaryContainer` | `surfaceContainerHigh` |
| Текст | `onPrimaryContainer` | `onSurface` |
| Время | `onPrimaryContainer` @70% | `onSurfaceVariant` |
| Статус-иконка | см. §9 ниже / [chat.md](screens/chat.md) | — |
| Выравнивание | справа | слева |
| Author header | — | `Title Medium`, `onSurfaceVariant` |

Статус-иконки своего сообщения: `schedule` pending (`onSurfaceVariant`), `check` sent (`onSurfaceVariant`), `error_outline` error (`error`).

### 9.3. Chat list item (5.1)

| Часть | Токен |
|---|---|
| Имя чата | `Title Medium`, `onSurface` |
| Превью | `Body Medium`, `onSurfaceVariant` |
| Время | `Label Small`, `onSurfaceVariant` |
| Unread badge | фон `primary`, текст `onPrimary`, `Label Small`, `shape/full`, cap `99+`; **при N=0 не рендерится** |
| Аватар | палитра §2.5, инициалы #FFFFFF; fallback glyph `forum` #FFFFFF |
| Divider | `outlineVariant` (или без, по 8dp ритму) |

### 9.4. Identity card (7.1)

| Часть | Токен |
|---|---|
| Card | filled, `surfaceContainerLow`, `shape/m`, elevation 1 |
| Маска ID | `••••••••` (8 знаков), **mono** (§3), `onSurface` |
| Раскрытый ID | **mono**, text-wrap, `onSurfaceVariant` |
| Logout `ListTile` | текст+иконка `error` |

### 9.5. Поля, кнопки, list-контролы

| Компонент | Токен |
|---|---|
| `TextField` (outlined) | `shape/xs`, border `outline` / focus `primary`, error `error`, текст `onSurface`, helper/counter `onSurfaceVariant` |
| `FilledButton` (primary) | фон `primary`, текст `onPrimary`, `shape/full`, Label Large; disabled `onSurface`@12% фон / `onSurface`@38% текст |
| `TextButton` (secondary) | текст `primary`, `shape/full` |
| `SearchBar` | `surfaceContainerHigh`, `shape/full`, elevation 2, текст `onSurface`, hint `onSurfaceVariant` |
| `SegmentedButton` | selected `secondaryContainer` / `onSecondaryContainer`, unselected `onSurface`, контур `outline` |
| `SwitchListTile` | M3 default (track/thumb `primary` on; `outline`/`surfaceVariant` off); label `onSurface` |
| `RadioListTile` (7.3 / 7.4) | radio selected `primary`, unselected `onSurfaceVariant`; label `onSurface`; tile прозрачный на `surface` |

### 9.6. Прогресс-индикаторы

| Компонент | Токен |
|---|---|
| `CircularProgressIndicator` (центр / standalone) | `primary` на `surface` |
| `CircularProgressIndicator` внутри `FilledButton` (Loading) | `onPrimary` (цвет load-bearing — на фоне `primary`) |
| `CircularProgressIndicator` suffix поля (Checking-availability 2.3/6.1) | `onSurfaceVariant` |
| `LinearProgressIndicator` (5.3, determinate %) | indicator `primary`, track `surfaceVariant` |

### 9.7. File-chip (вложение)

Единый chip для файла (в bubble 5.2, в composer, ссылается file-icon map из overview).

| Часть | Токен |
|---|---|
| Контейнер | `surfaceContainerHighest`, `shape/xs`; внутри own-bubble — контрастный тон поверх `primaryContainer` |
| Иконка типа | `onSurfaceVariant` (маппинг — overview) |
| Имя файла | `Title Medium`, `onSurface`, ellipsis |
| Размер | `Body Medium`, `onSurfaceVariant` |
| Кнопка удаления `×` (только в composer) | `close`, `onSurfaceVariant`, tap-target 48×48 |

### 9.8. Composer (5.2)

| Часть | Токен |
|---|---|
| Контейнер | `surfaceContainer`, верхний divider `outlineVariant` |
| `TextField` | см. §9.5 (multiline, без бордера или outlined по дизайн-выбору) |
| Attach `IconButton` | `onSurfaceVariant` |
| Send `IconButton` | active `primary`; disabled `onSurface`@38% |

### 9.9. QR-сканер / camera-overlay (2.2) — brand-fixed (поверх живого видео)

Цвета **не** из `ColorScheme` (читаемость поверх камеры):

| Часть | Значение |
|---|---|
| Затемняющая маска (вне прицела) | `#000000` @ 55% |
| Прицел (рамка) | stroke `brand/white` #FAFAFA, ширина 3dp, углы `shape/m` (12), размер ≈ 70% ширины экрана (квадрат) |
| Overlay-инструкция `Aim your camera…` | текст #FAFAFA (фиксированный, не theme), `Body Large`, с лёгкой тенью/scrim для читаемости |
| Permission-denied overlay | **непрозрачная** поверхность `surface` (не прозрачная над камерой), текст по ролям, кнопка `Open settings` = `FilledButton` |
| AppBar | сплошной `surface` (см. qr-scan.md) |

### 9.10. QR bottom sheet (7.1 «Show QR») — brand-fixed QR-поверхность

| Часть | Токен |
|---|---|
| Sheet | `surface`, `shape/xl` (верх), elevation 5 |
| Drag-handle | `onSurfaceVariant` @ 40% |
| QR-поверхность (карточка под код) | **`brand/qr-surface` #FFFFFF** (фиксированная светлая, чтобы код сканировался и в dark) |
| QR-модули | `brand/qr-ink` #0C0C0C |
| Quiet-zone | padding ≥ 4 модуля / ~16dp вокруг кода |
| Заголовок / `Close` | `Title Large` `onSurface` / `TextButton` |

### 9.11. Обратная связь и оверлеи

| Компонент | Токен |
|---|---|
| `SnackBar` (transient) | `inverseSurface` / `onInverseSurface`; error-вариант — `errorContainer` / `onErrorContainer`; позиция над нижней панелью / FAB |
| `MaterialBanner` (persistent / offline) | `surfaceContainer`, action `primary`, сверху |
| `AlertDialog` (Logout) | `surfaceContainerHigh`, `shape/xl`, elevation 5; title `Headline Small`, body `Body Medium`, confirm — `error`-текст |
| 3.1 экран ошибки | иконка `error_outline` `onSurfaceVariant` 48–96, кнопка `FilledButton` |
| `AppBar` (стандартный) | container `surface`, title `onSurface`, иконки `onSurface` / `onSurfaceVariant`, elevation 0 |

---

## 10. Иллюстрации empty-state

Нужны для 5.1 (нет чатов), 5.2 (нет сообщений), 5.4 (нет файлов).

- Стиль: лёгкие линейно-«мазковые» спот-иллюстрации в духе логотипа — тонкий контур (`onSurfaceVariant`) + один-два брендовых акцента (`brand/teal` + `brand/gold`), прозрачный фон.
- Размер: ~120–160 в высоту, по центру, выше заголовка empty-state.
- Один ассет читаем и на light, и на dark.
- **Нужны ассеты:** 3 SVG (chats / messages / files). До их готовности — Material-иконка + текст как fallback, по экранам: 5.1 → `forum_outlined`, 5.2 → `chat_bubble_outline`, 5.4 → `folder_open` (цвет `onSurfaceVariant`).

---

## 11. Что ещё нужно заказать (артефакты вне этого документа)

- **Логотип** — финальный SVG (full-color на тёмном).
- **Шрифт wordmark** — подтвердить системный vs кастомный бренд-шрифт.
- **3 empty-state иллюстрации** (chats / messages / files).
- **App icon** (launcher) — на базе логотипа.
- **Тюнинг `ColorScheme`** в Material Theme Builder (значения §2.2–2.3 — выверенный старт). При финальном замере проверить роли `inverseSurface`/`inversePrimary`/`scrim`/`surfaceTint`.
