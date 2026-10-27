# Quickstart: данные на диске сервера

## 1. Автоматические проверки

```bash
cd client_backend && gofmt -l . && go vet ./... && go test -race ./... && CGO_ENABLED=0 go build -trimpath -ldflags=-s -o /dev/null .
```

## 2. Сквозной прогон на macOS

```bash
cd client_backend && go build -o "$STAND/noxd" .
"$STAND/noxd" -db "$STAND/nox.db" -addr 0.0.0.0:8443 -status-addr 127.0.0.1:8081 &
printf 'correct horse battery\ncorrect horse battery\n' | "$STAND/noxd" unlock      # задать пароль
curl -s http://127.0.0.1:8081/health                                               # {"status":"ok"}
```

1. Спарить приложение, написать сообщения, отправить картинку и видео.
2. Остановить сервер; `grep -r` маркеров сообщений и байтов картинки по `$STAND` → пусто (SC-001).
3. Запустить снова → `/health` `locked`, приложение — плашка без связи (`No connection` или подсказка `Use Tor`, если известен onion-адрес); неверный пароль → `Wrong password.`, каталог не изменился (SC-003); верный → открыт за ≤2 с, приложение на связи (SC-002).
4. `noxd password` → новый пароль открывает, прежний — нет; меньше 5 с (SC-006).
5. Оборвать загрузку большого файла посреди передачи и продолжить → файл целый; видео перематывается (SC-004).
6. `noxd backup "$STAND/backup.tar"`; `noxd restore "$STAND/backup.tar" -db "$OTHER/nox.db"` → команда называет момент бэкапа и устройства, которые примет сервер; запустить сервер на `$OTHER` с тем же портом, ввести пароль → приложение подключается без спаривания и перечитывает переписку (SC-005).

## 3. Проверки владельца

- Linux и Windows: запуск, пароль, бэкап и восстановление между машинами.
