# Quickstart: установка сервера

## macOS (здесь)

```bash
sudo deploy/install-macos.sh --port 8443             # с tor
# или для проверки без системы:
deploy/install-macos.sh --prefix "$STAND" --port 18443 --no-service
```

1. Скрипт спрашивает пароль дважды (короткий или не совпавший — снова), ставит tor (если подпись сошлась) и сервер, в конце печатает ссылку, QR-код и `http://127.0.0.1:8081`.
2. Телефон или приложение на этой машине спаривается по ссылке.
3. `sudo launchctl kickstart -k system/com.cyphernetlabs.noxd` → `/health` `locked` → `noxd unlock` (без `sudo`: команда ходит на loopback-страницу) → `ok`, приложение на связи.
4. Повторный запуск скрипта → обновление, переписка и устройства на месте.
5. `ps aux | grep noxd` и логи службы — пароля нет.

## Linux и Windows — владелец

`sudo deploy/install-linux.sh`, `deploy\install-windows.ps1` (PowerShell от администратора) — те же шаги.
