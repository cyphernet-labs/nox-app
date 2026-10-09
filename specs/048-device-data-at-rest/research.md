# Research: Данные на диске устройства

Опора — код `lib/data/local/app_database.dart` (Sembast в «Документах»), `lib/data/repository/file/file_repository_impl.dart` (кэш вложений, докачка 043), `lib/data/local/chat/outbox_copies.dart` (копии исходящих), `flutter_secure_storage` с нынешними опциями, Rust-модуль 044.

## R1. Ключ локальной базы и «только это устройство»

- **Decision:** 32 случайных байта, создаются при первом запуске, хранятся в `flutter_secure_storage` под `device.storage_key` с опциями «только это устройство»; те же опции — у ключа устройства и всех секретов сессии (FR-002, FR-003):
  - iOS — `KeychainAccessibility.first_unlock_this_device`;
  - Android — хранилище плагина на Android Keystore, `allowBackup="false"` и правила извлечения данных, исключающие всё;
  - macOS — `usesDataProtectionKeychain: true` с `first_unlock_this_device`; для этого macOS-сборка подписывается командой (`DEVELOPMENT_TEAM = W84KAPTJ9Y`, как iOS) и получает `keychain-access-groups`; сборки CI — с `CODE_SIGNING_ALLOWED=NO`;
  - Windows — DPAPI плагина (текущий пользователь), файл хранилища — в `%LOCALAPPDATA%`, не в перемещаемом профиле;
  - Linux — libsecret (локальная связка ключей).
- **Rationale:** решение 3, Принцип III 1.4.0 (без desktop-fallback). Нынешняя macOS-связка ключей (`usesDataProtectionKeychain: false`) попадает в Time Machine и переносится Migration Assistant — так нельзя.
- **Риск:** локальная сборка macOS требует профиля разработки команды; проверяется на этой машине (`flutter build macos` c автоматической подписью), Windows и Linux — владелец.

## R2. Шифрование — в Rust-модуле

- **Decision:** модуль получает «сейф»: `nox_vault_set_key(key32)` (ключ в обнуляемом буфере процесса), `nox_vault_clear()`, `nox_vault_seal(data)`/`nox_vault_open(data)` (ChaCha20-Poly1305 на `ring`, случайный nonce в начале результата) и `nox_vault_seal_chunk`/`nox_vault_open_chunk` (ключ файла `HKDF-SHA256(ключ, info = "nox/devfile/v1|" + имя)`, nonce — номер куска, AAD — номер ‖ признак последнего). Вызовы синхронные, только процессор.
- **Rationale:** трекер темы 4: шифр локальной базы — `ring` в Rust-модуле, та же библиотека, что под TLS; синхронные вызовы нужны кодеку Sembast.

## R3. База

- **Decision:** Sembast открывается с `SembastCodec(signature: 'nox-vault-1', codec: VaultCodec)`: каждая строка файла — `base64(nonce ‖ шифротекст ‖ тег)`; чужой ключ — отказ подписи кодека при открытии. Файл базы переезжает из «Документов» в папку данных приложения (R5). Тестовое окружение — `databaseFactoryMemory`, как сегодня.
- **Rationale:** FR-004; Sembast шифрует запись целиком, включая служебную строку.

## R4. Файлы

- **Decision:** формат файла как у сервера (047): заголовок `NOXF`, куски по 64 КиБ с тегом. Кэш вложений (`nox_attachments`) и `.part` докачки 043 — запечатанные куски; докачка продолжается с границы последнего целого куска (`Range` от него), `.part.tag` — как сегодня. Копии исходящих (`nox_outbox/<client_message_id>/<имя>`) — запечатаны; загрузка читает расшифровывающим потоком с `received`. Картинки — расшифровка в память (`Image.memory`), миниатюры — в памяти.
- **Rationale:** FR-005, FR-006; докачка из 043 сохраняется.

## R5. Где лежат данные и бэкапы

- **Decision:** корень данных — `getApplicationSupportDirectory()` на iOS, Android, macOS, Linux; на Windows — `%LOCALAPPDATA%\NOX`. Там база, `nox_attachments`, `nox_outbox`, состояние Tor. iOS и macOS — метка `NSURLIsExcludedFromBackupKey` на корне данных (короткий метод платформы в `AppDelegate`); Android — `allowBackup="false"`, `fullBackupContent="false"`, `dataExtractionRules` с исключением всего для `cloud-backup` и `device-transfer`. Кэш (`getApplicationCacheDirectory`) не используется для вложений.
- **Rationale:** FR-009, FR-010, решение 2.

## R6. Временные копии

- **Decision:** `<временная папка>/nox_open/`: копия видео — для плеера, стирается при его закрытии; копия для «Открыть в…» — стирается при следующем запуске или выходе; при каждом запуске папка очищается. «Сохранить» — расшифровка в выбранное место. Нет места — ошибка открытия `Couldn't open this file. Free up some space and try again.` (EN), `Не вдалося відкрити цей файл. Звільніть місце і спробуйте ще раз.` (UK).
- **Rationale:** FR-007, FR-008, FR-014, уточнение.

## R7. Ключ не прочитать, выход

- **Decision:** при запуске: ключа нет и базы нет — новый ключ; ключа нет, а база есть — принудительный выход (стирание) и спаривание; ошибка чтения сейфа — без стирания, повтор с паузой (заставка). Выход: остановить связь, стереть базу, файлы, временные копии, ключ локальной базы и ключ устройства, `nox_vault_clear()`.
- **Rationale:** FR-011, FR-012, уточнение.

## R8. Производительность

- **Decision:** замер открытия списка чатов и треда на 10 000 сообщений до и после (тест-бенч в `test/`), бюджет +20% (SC-003).

## R9. Проверка

- **Decision:** Dart — кодек (круг, чужой ключ), формат файлов (круг, подмена, усечение, диапазон, докачка с середины куска), временные копии (жизненный цикл, очистка при запуске), ключ (нет ключа + база — стирание; ошибка чтения — без стирания), SC-001 (поиск маркеров по папке данных); Rust — сейф (круг, обнуление); голдены ошибки открытия на 5.3 обеих ширин. Устройства: iOS-бэкап, Android-перенос, Time Machine — владелец и проверка на этой машине, где возможно.
