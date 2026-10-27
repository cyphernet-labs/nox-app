# Дизайн-система NOX

> Дизайн-система NOX: цвет, типографика, форма, высота, отступы, движение, иконки и токены компонентов, на которые ссылаются экраны. Основа для макетов и реализации на Flutter / Material Design 3. Цветовая база **извлечена из референса логотипа** [`assets/logo-reference.png`](assets/logo-reference.png) (см. «Цвет»). Машиночитаемый источник значений — DTCG-токены [`nox-handoff/tokens/`](../system/nox-handoff/tokens/); при расхождении с этим документом верны они. Общие UI-решения и микрокопирайт — в [overview.md](overview.md) и [screens/](screens/README.md).

Документ описывает **две вещи раздельно**:

1. **Функциональная схема** (M3 `ColorScheme`, seed = бирюза) — спокойная, для интерактивных элементов, поверхностей, текста. Адаптируется light/dark.
2. **Бренд-палитра** (мульти-хью из логотипа) — выразительная, для логотипа и splash. **Не** используется для primary-кнопок.

**Два намеренных исключения из темизации** (фиксированные, не зависят от light/dark): фон **splash** (`brand/canvas-dark`) и поверхность **QR-кода** в карточке приглашения 7.8 (`brand/qr-surface`).

---

## 1. Бренд

### Логотип

- Источник/мудборд: [`assets/logo-reference.png`](assets/logo-reference.png) — маска в стиле «разноцветные мазки» на тёмном сине-зелёном фоне.
- Характер: тёмный canvas + многоцветные «всплески» (бирюза, золото, красный, лайм, синий).
- **Нужен ассет:** векторный логотип (SVG), full-color на тёмном. Логотип стоит на splash (тёмный фон), в онбординг-карте широкой ширины и в заголовке окна широкой ширины; сейчас это растровый файл.

### Wordmark «NOX»

- Текст `NOX`, всегда верхний регистр.
- Шрифт — **Roboto Bold (700)**, поставляется с приложением на всех платформах; letter-spacing **+0.12em**.
- Размер: по умолчанию 22 (как Title Large) — AppBar онбординга и 5.1, онбординг-карта; **28** — на splash; **13** с letter-spacing **+0.14em** — в заголовке окна широкой ширины.
- Цвет: на splash — `brand/white` (#FAFAFA) на `brand/canvas-dark`; в AppBar (2.1, 2.3, 2.4, 5.1) — `colorScheme.onSurface`.

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

Полные `ColorScheme` (light + dark) **выверены вручную** от бирюзового seed по логике тонов M3 и заданы явно, роль за ролью (`nox-handoff/tokens/color.{light,dark}.tokens.json`). `ColorScheme.fromSeed` их не воспроизводит и не используется: значения §2.2–2.3 берутся как есть.

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
| surfaceContainerLowest | `#0C1312` |
| surfaceContainerLow | `#1C2423` |
| surfaceContainer | `#222A28` |
| surfaceContainerHigh | `#2C3431` |
| surfaceContainerHighest | `#37403C` |
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

Семейства (оба поставляются с приложением и одинаковы на всех пяти платформах):
- **Sans (основное)** — `Roboto` (400 / 500 / 700).
- **Mono** — `Roboto Mono`. Используется только для идентификатора в 7.1 и поля ссылки спаривания в 2.1 (метрики как Body Large: 16 / 24).
- **Wordmark `NOX`** — Roboto Bold (700) поверх Title Large, letter-spacing +0.12em (отдельно от шкалы; размеры — в §1).

Шкала — M3 type scale:

| Token (M3) | Size / Line | Weight | Применение в NOX |
|---|---|---|---|
| Display Small | 36 / 44 | 400 | — (резерв) |
| Headline Small | 24 / 32 | 400 | заголовок empty-state; крупный body-Header имени чата (5.4); title `AlertDialog` (Logout); заголовок диалога создания чата (6.1, широкая) |
| Title Large | 22 / 28 | 400 | AppBar title (имя чата 5.2/5.4, `Settings`, `New chat`, имя файла 5.3); имя файла в теле 5.3; заголовок панели `Details` (5.4, широкая); имя в карте идентичности (7.1) |
| Title Medium | 16 / 24 | 500 | имя чата в списке (5.1) и в шапке ленты (5.2, широкая); имя автора в ленте (5.2); filename в file-chip; заголовок lightbox 5.3 (широкая) |
| Body Large | 16 / 24 | 400 | текст сообщения; поля ввода; ID и ссылка спаривания (mono-семейство) |
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
| `shape/s` | 8 | малые чипы, превью-плитки 7.3 / 7.4 |
| `shape/m` | 12 | `Card` (identity-card), карточки выбора 7.3 / 7.4, QR-поверхность |
| `shape/l` | 16 | message bubble (база); плитки строк настроек (7.1) |
| `shape/xl` | 28 | bottom sheet (верхние углы), `AlertDialog` |
| `shape/full` | stadium / круг | `FilledButton`, `TextButton`, `SearchBar`, `Badge`, `SegmentedButton` (пилюля целиком), выделение пункта меню настроек (широкая), **docked FAB «+» (круг)** |

**Message bubble:** база `shape/l` (16); «свой» угол (нижний-правый) и «чужой» (нижний-левый) скашиваются до 4 — лёгкая ассиметрия вместо «хвоста».
**FAB «+»:** круглый (`shape/full`), под него рассчитан `CircularNotchedRectangle` нижней панели (см. §9.1).

---

## 5. Высота (elevation, M3 tonal)

| Level | dp | Применение |
|---|---|---|
| 0 | 0 | плоские поверхности, AppBar (по умолчанию) |
| 1 | 1 | `Card`, приподнятые list-поверхности |
| 2 | 3 | `BottomAppBar` (нижняя панель), `SearchBar` |
| 3 | 6 | docked FAB «+», `MaterialBanner`, боковая панель карточки чата (5.4, широкая) |
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
| Переключение табов (4.1) | без слайда: обе вкладки смонтированы в `Stack` (`IgnorePointer` + `AnimatedOpacity`), смена — fade ≤ 150 мс | standard |
| Snackbar in/out | 150 / 75 мс | standard |
| Раскрытие bottom sheet | 300 мс | emphasized-decelerate |
| State-layer / ripple | M3 default | — |

Циклических/бесконечных анимаций нет (splash — однократная).

---

## 8. Иконография

- Набор — **Material Symbols Rounded** (weight 400, optical 24, grade 0), в обеих формах оси FILL (контурная и заполненная). Приложение несёт эти глифы как SVG-файлы, а не шрифтом иконок; имена в спеках экранов вида `Icons.*` / `*_outline` означают тот же глиф набора: `error_outline` — это `error` в контурной форме.
- Размер по умолчанию — 24, ведущий глиф строки настроек — 22; крупная иконка на 3.1 / 5.3 — 48–96.
- **Навигация (4.1):** Chats — `forum`, Settings — `settings` (выбранный таб — заполненная форма, невыбранный — контурная), центр — `add`.
- **Действия:** back `arrow_back`, paste `content_paste`, scan `qr_code_scanner`, attach `attach_file`, send `send`, flashlight `flashlight_on/off`, switch camera `cameraswitch`, search `search`, copy `content_copy`, save `download`, edit `edit`, remove-attachment `close`, play/pause видео `play_arrow` / `pause`, переход `chevron_right`.
- **Строки настроек (7.1):** аккаунт `person`, Devices `devices`, Connection `lan`, Notifications `notifications`, Appearance `palette`, Language `language`, Terms `description`, About `info`, Log out `logout` (всегда заполненный).
- **Состояния:** нет связи `wifi_off`, уведомления заблокированы `notifications_off`, нет доступа к камере `no_photography`, пояснение `info`, системный язык `smartphone`, приглашение устройства `devices`.
- **Статусы сообщений:** `schedule` (pending), `check` (sent), `error_outline` (error) — цвета см. §9.2 / [chat.md](screens/chat.md).
- **Типы файлов:** единая таблица в [overview.md / Файлы](overview.md#файлы-иконки-типов-и-превью).
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
| Рейл (широкая ширина) | полоса 80 `surface` с hairline `outlineVariant` справа; две ячейки назначений (глиф + подпись `Label Medium`): выбранная — заливка `secondaryContainer` со скруглением 16, глиф заполненный, цвет `onSecondaryContainer`; невыбранная — прозрачная, `onSurfaceVariant`; внизу — аватар аккаунта 36 с кольцом. «+» на рейле нет |

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
| Превью | `Body Medium`, `onSurfaceVariant`; у чата с непрочитанными — `onSurface` |
| Время | `Label Small`, `onSurfaceVariant`; у чата с непрочитанными — `primary` |
| Unread badge | фон `primary`, текст `onPrimary`, `Label Small`, `shape/full`, cap `99+`; **при N=0 не рендерится** |
| Аватар | 40, с тонким кольцом; палитра §2.5, инициалы #FFFFFF; fallback glyph `forum` #FFFFFF |
| Divider | нет; на широкой ширине строки отстоят на 4 друг от друга и на 8 от краёв панели, выбранная — скруглённая (16) заливка `secondaryContainer` |

### 9.4. Identity card (7.1)

| Часть | Токен |
|---|---|
| Card | filled, `surfaceContainerLow`, `shape/m`, elevation 1 |
| Аватар | генерируемый, с кольцом, 56; инициалы по правилу для людей |
| Имя | `Title Large`, `onSurface` |
| ID | целиком, без маски, **mono** (§3), text-wrap, `onSurfaceVariant` |
| Действия `Edit name`, `Copy ID` | `FilledButton.tonal` с глифом (`secondaryContainer` / `onSecondaryContainer`), в переносимом ряду |

### 9.5. Поля, кнопки, list-контролы

| Компонент | Токен |
|---|---|
| `TextField` (outlined) | `shape/xs`, border `outline` / focus `primary`, error `error`, текст `onSurface`, helper/counter `onSurfaceVariant` |
| `FilledButton` (primary) | фон `primary`, текст `onPrimary`, `shape/full`, Label Large; disabled `onSurface`@12% фон / `onSurface`@38% текст |
| `TextButton` (secondary) | текст `primary`, `shape/full` |
| `SearchBar` | `surfaceContainerHigh`, `shape/full`, elevation 2, текст `onSurface`, hint `onSurfaceVariant` |
| `SegmentedButton` | пилюля целиком (`shape/full`), как остальные кнопки NOX; selected `secondaryContainer` / `onSecondaryContainer`, unselected `onSurface`, контур `outline` |
| `SwitchListTile` | on: дорожка `primary`, бегунок `onPrimary`; off: дорожка `surfaceContainerHighest` с контуром `outline`, бегунок `outline`; галочки на бегунке нет (глиф там возможен только шрифтом иконок, а приложение их не несёт); label `onSurface` |
| Карточка выбора (7.3 / 7.4) | превью-плитка слева + подпись (и подзаголовок в 7.3) + радио-точка справа; выбранная — заливка `surfaceContainerHigh` и обводка `primary` 2, остальные — прозрачные с hairline `outlineVariant`; `shape/m` |

### 9.6. Прогресс-индикаторы

| Компонент | Токен |
|---|---|
| `CircularProgressIndicator` (центр / standalone) | `primary` на `surface` |
| `CircularProgressIndicator` внутри `FilledButton` (Loading) | `onPrimary` (цвет load-bearing — на фоне `primary`) |
| `CircularProgressIndicator` suffix поля (Checking-availability 6.1, переименование чата) | `onSurfaceVariant` |
| `LinearProgressIndicator` (5.3, determinate %) | indicator `primary`, track `surfaceContainerHighest` |

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
| `TextField` | multiline (до 6 строк), без бордера — поле сливается с контейнером; hint `onSurfaceVariant` |
| Attach `IconButton` | `onSurfaceVariant` |
| Send `IconButton` | active `primary`; disabled `onSurface`@38% |

### 9.9. QR-сканер / camera-overlay (2.2) — brand-fixed (поверх живого видео)

Цвета **не** из `ColorScheme` (читаемость поверх камеры):

| Часть | Значение |
|---|---|
| Затемняющая маска (вне прицела) | `#000000` @ 55% |
| Прицел (рамка) | уголки stroke `brand/white` #FAFAFA, ширина 3dp, скруглены дугой радиуса `shape/m` (12) по углам окна маски; размер ≈ 70% короткой стороны (квадрат) |
| Overlay-инструкция `Aim your camera…` | текст #FAFAFA (фиксированный, не theme), `Body Large`, с тенью для читаемости |
| Permission-denied / камера недоступна | **непрозрачная** поверхность `surface` (не прозрачная над камерой), текст по ролям, кнопка `FilledButton` |
| AppBar | над камерой — прозрачный, back и действия `brand/white`; над непрозрачной поверхностью — `surface` (см. qr-scan.md) |

### 9.10. QR-поверхность (brand-fixed) — карточка приглашения 7.8

Карточка приглашения (`Add a device`) — filled `Card`: QR-код, под ним пояснение, пометка «только дома» (когда она нужна), сама ссылка текстом и действия `Copy` и `Hide`.

| Часть | Токен |
|---|---|
| QR-поверхность (под код) | **`brand/qr-surface` #FFFFFF** (фиксированная светлая, чтобы код сканировался и в dark), `shape/m` |
| QR-модули | `brand/qr-ink` #0C0C0C |
| Quiet-zone | отступ 10% стороны кода вокруг него |
| Имя для экранного диктора | `Pairing link QR code` (код — картинка, и без имени диктору достаётся пустое место) |

### 9.11. Обратная связь и оверлеи

| Компонент | Токен |
|---|---|
| `SnackBar` (transient) | `inverseSurface` / `onInverseSurface`; error-вариант — `errorContainer` / `onErrorContainer`; позиция над нижней панелью / FAB |
| `MaterialBanner` (persistent / offline) | полоса во всю ширину под хромом экрана: `surfaceContainer`, elevation 3, глиф `onSurfaceVariant`, текст `onSurface`, action `TextButton` `primary` |
| Карточка-уведомление на экране настроек (7.2) | та же геометрия, что у карточек настроек (`shape/l`, отступ 16 от краёв), фон `surfaceContainer`; действие — на своей строке у правого края |
| `AlertDialog` (Logout) | `surfaceContainerHigh`, `shape/xl`, elevation 5; title `Headline Small`, body `Body Medium` `onSurfaceVariant`, confirm — `error`-текст |
| 3.1 экран ошибки | иконка `error_outline` `onSurfaceVariant` 48–96, кнопка `FilledButton` |
| `AppBar` (стандартный) | container `surface`, title `onSurface`, иконки `onSurface` / `onSurfaceVariant`, elevation 0 (при прокрутке под ним — 2) |

### 9.12. Строки настроек (7.1)

| Часть | Токен |
|---|---|
| Строка (узкая ширина) | отдельная плитка на пункт: `surfaceContainerLow`, `shape/l`, зазор 8; справа — `chevron_right` `onSurfaceVariant` |
| Ведущий глиф | 22, `onSurfaceVariant`, **без круглой подложки** (решение владельца 2026-09-20: кольца подряд читаются как кнопки и спорят с пилюлей выделения) |
| Подпись | `Body Large`, `onSurface` |
| `Log out` | своя плитка, подпись и глиф `error`, глиф всегда заполненный, шеврона нет |
| Пункт меню-панели (широкая) | без контейнера; выбранный — пилюля `secondaryContainer` с отступом 8 от краёв панели, подпись и глиф `onSecondaryContainer`, глиф заполненный |
| Группы меню-панели (широкая) | линия `outlineVariant` под группой, не между строками; `Log out` прижат к низу панели; у заголовка панели линии нет |

### 9.13. Панели широкой ширины

| Часть | Токен |
|---|---|
| Заголовок окна | полоса `surfaceContainerLow`: логотип, wordmark 13 (+0.14em), `— <раздел>` (`Body Medium`, `onSurfaceVariant`); под ней брендовая градиентная линия |
| Онбординг-карта (2.1, 2.3, 2.4; панель 2.2, когда доступа к камере нет или камера недоступна) | по центру окна, ширина до 440, hairline `outlineVariant`; логотип, wordmark, короткая градиентная пилюля 120×3 |
| Боковая панель карточки чата (5.4) | справа, ширина 380, elevation 3, hairline `outlineVariant` по левому краю; аватар шапки с кольцом — 72 (на узкой ширине 5.4 — 56) |
| Шапка панели (`Details` в 5.4, lightbox 5.3) | необязательный ведущий глиф, заголовок (`Title Large` в 5.4, `Title Medium` в 5.3), кнопка закрытия; hairline под шапкой |
| Шапка ленты (5.2) | аватар с кольцом 40 + имя (`Title Medium`), действия info и `Invite a person` (выключено), hairline под шапкой |

---

## 10. Empty state

Нужен для 5.1 (нет чатов), 5.2 (нет сообщений), 5.4 (нет файлов), а также для пустой панели ленты на широкой ширине (чат не выбран). Нарисованных иллюстраций нет: арт пустого состояния — эта композиция из стоковых элементов (`NoxEmptyState` в каталоге виджетов `nox-handoff-2`, `AppEmptyContentWidget` в приложении):

- квадрат 132 со скруглением 20 и обводкой 1.5 `outlineVariant`, внутри — глиф 56 `onSurfaceVariant`: 5.1 и пустая панель ленты → `forum`, 5.2 → `chat_bubble`, 5.4 → `folder_open`;
- две брендовые точки внутри квадрата: `brand/teal` 14 сверху справа, `brand/gold` 10 снизу слева;
- под квадратом — заголовок `Headline Small` `onSurface` и текст `Body Medium` `onSurfaceVariant` (колонка не шире 260).

---

## 11. Открытые артефакты

- **Логотип** — финальный векторный SVG (full-color на тёмном); от него зависит монохромный мастер иконки приложения (P16).

Иконки приложения для всех пяти платформ установлены — набор собран из растрового логотипа, финальный ждёт векторного; цветовые схемы выверены и заданы токенами (§2.2–2.3); wordmark — Roboto Bold (§1).

Иллюстрации пустых состояний не заказываются: арт пустого состояния — композиция §10. Три SVG в [`nox-assets/illustrations/`](../system/nox-assets/illustrations/README.md) — эскизы корпуса; в бандл приложения они не входят.
