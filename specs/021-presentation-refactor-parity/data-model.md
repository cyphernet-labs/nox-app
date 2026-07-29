# Component Model (не data-model)

**Phase 1.** Фича не затрагивает данные/сущности. Ниже — «модель компонентов»: извлекаемые виджеты
(E1–E13) и токены (O1–O2) с их входами и источниками-дублями. Это карта для `/speckit-tasks`.

## Новые извлекаемые виджеты (`App*Widget` / приватные)

| # | Компонент | Входы (props) | Заменяет дубли в |
|---|---|---|---|
| E1 | `AppPrimaryButtonWidget` | `{label, onPressed, loading}` | login_page:249, set_username_page:172 |
| E2 | `AppOnboardingScaffoldWidget` | `{subtitle, field, actions, mobileActionsPadding?}` | login_page:181, set_username_page:105 (+ qr `_wide`) |
| E3 | `AppHairlineDividerWidget` (const) | — | 11 сайтов `Divider(height: border.hairline)` |
| E4 | `AppRingedAvatarWidget` | `{name, size, initials?}` | chat_card_page:226, chats_list_page:216 |
| E5 | `WatchChat` (reactive) | `{chatId, initial, builder(ctx, ChatModel)}` | app_thread_view:129, chat_thread_page:76, chat_card_page:119/217 |
| E6 | `_SettingsPaneHeader` (приватный) | `{title, leading?}` | settings_root_page:227/300 |
| E7 | attachment-preview helper | `{attachment, onTap? , onRemove?}` | app_thread_view `_bubble`/`_composerBar` |
| E8 | `showAdaptiveLightbox` (helper) | `{context, page, dialogDecoration?}` | showFileView, openImageViewer |
| E9 | `_ElevatedBannerShell` (тонкий) | `{icon, child, action?}` | app_notice_strip, app_info_banner |
| E10 | `_QrDesktopViewfinder` (приватный) | scanning-state props | qr_scan_page:371 |
| E11 | rail sub-widgets | — | app_navigation_rail `_createFab`/`_destination`/`_accountAvatar` |
| E12 | `_devMenuRows()` | — | settings_root_page:197/258 |
| E13 | `AppDevScenarioDropdown<T extends Enum>` | `{value, values, onChanged, label?}` | 6 debug-dropdown (thread/card/list/create/login/username) |

## Новые токены (`lib/design/theme/`)

| # | Токен | Значения (равны текущим литералам) | Заменяет |
|---|---|---|---|
| O1 | `NoxOpacity.{scrim, disabled, ring}` | scrim 0.5 (свести 0.55→0.5), disabled 0.38, ring 0.06 | side-sheet, chat_card, file_view, composer, rail |
| O2 | геометрия-const | `_loadMoreThreshold=200`, `qrDesktopReticleFraction=0.78`, splash reveal-scale `0.85` | app_thread_view:106, qr_scan_page:389, splash_page:51 |

## Инвариант

Извлечение НЕ меняет визуальный вывод (голдены байт-в-байт). Токены численно равны прежним значениям
(единственное исключение — scrim 0.55→0.5, если признано рассинхроном → 1 baseline перегенерируется).
