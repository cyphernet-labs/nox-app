# Quickstart: данные на диске устройства

## 1. Автоматические проверки

```bash
make tor-test                 # сейф в модуле
make gate && make golden-verify   # кодек, файлы, временные копии, ключ, SC-001, голдены 5.3
```

## 2. Прогон на macOS

1. `fvm flutter run -d macos --dart-define-from-file=config/stage.json` (сборка подписана командой).
2. Спарить, написать сообщения, отправить и получить картинку и видео.
3. `grep -r` маркеров сообщений и байтов файлов по папке данных приложения (`~/Library/Containers/com.cyphernetlabs.noxapp/Data/Library/Application Support/`) → пусто (SC-001).
4. `xattr -p com.apple.metadata:com_apple_backup_excludeItem` на папке данных → метка стоит; `tmutil isexcluded <папка>` → исключена.
5. Посмотреть видео, закрыть → `<temp>/nox_open` пуст (SC-004); «Открыть в…» → копия до следующего запуска.
6. Удалить `device.storage_key` из связки ключей → запуск: экран спаривания, после спаривания переписка на месте (SC-006).
7. Выйти → в папке данных и связке ключей ничего от NOX (SC-005).

## 3. Проверки владельца

- iOS: бэкап в iCloud и на компьютер без данных NOX; Android: перенос без данных NOX; Windows (`%LOCALAPPDATA%`), Linux (`~/.local/share`).
