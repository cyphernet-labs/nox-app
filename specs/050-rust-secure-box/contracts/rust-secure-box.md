# Контракт: интерфейс RustSecureBox

RustSecureBox — крейт `packages/rust_secure_box` (`rust_secure_box`). Один и тот же исходный код:

- в приложении он встроен в Rust-модуль `nox_tor` как зависимость Rust;
- на сервере собран в WebAssembly и переведён `wasm2go` в Go-код (research R1).

Настоящую реализацию кладут на место заглушки. Контракт ниже — всё, что приложение и сервер от неё ждут.

## Свойства

- **Без состояния.** Ничего не хранит между вызовами; ключи передаёт вызывающий.
- **Потокобезопасна.** Вызовы из любого числа потоков одновременно.
- **Только вычисления.** Ни файлов, ни сети, ни обращений к системе. Единственное, что приходит снаружи, — случайные байты: в приложении от системы, на сервере — импортом `env.rsb_random` от Go.
- **Ошибки — значения, а не паники.** Паника в приложении перехватывается модулем (`-3`), ловушка WebAssembly на сервере — обёрткой Go (ошибка, экземпляр выбрасывается). Но реализация не должна на них рассчитывать.
- **Логика и ключи как у прежней проверки** (решение 4): настоящий RustSecureBox — Ed25519 по RFC 8032, закрытый ключ — 32 байта (семя), открытый — 32, подпись — 64. Заглушка — research R4.

## Rust API (`src/lib.rs`)

```rust
pub const PRIVATE_KEY_LEN: usize = 32;
pub const PUBLIC_KEY_LEN: usize = 32;
pub const CHALLENGE_LEN: usize = 32;
pub const SIGNATURE_LEN: usize = 64;

pub type PrivateKey = [u8; PRIVATE_KEY_LEN];
pub type PublicKey = [u8; PUBLIC_KEY_LEN];
pub type Challenge = [u8; CHALLENGE_LEN];
pub type Signature = [u8; SIGNATURE_LEN];

pub enum Error {
    InvalidArgument, // ключ, который реализация не принимает
    Random,          // нет случайных байтов
    Internal,        // любая другая беда реализации
}

pub struct KeyPair { pub private_key: PrivateKey, pub public_key: PublicKey }

/// Новая пара ключей.
pub fn generate_keys() -> Result<KeyPair, Error>;
/// Новый случайный челлендж и открытый ключ для `own`.
pub fn get_challenge(own: &PrivateKey) -> Result<(Challenge, PublicKey), Error>;
/// Подпись `own` над челленджем другой стороны.
pub fn sign_challenge(own: &PrivateKey, theirs: &Challenge) -> Result<Signature, Error>;
/// Верна ли подпись `public_key` над `challenge`. Ok(false) — неверна; Err — ошибка.
pub fn check_signature(public_key: &PublicKey, challenge: &Challenge, signature: &Signature) -> Result<bool, Error>;
```

`KeyPair` и закрытые ключи затираются при удалении (`Drop`).

## C ABI WebAssembly (`src/wasm.rs`, только `wasm32`)

Экспорты (`#[no_mangle] extern "C"`):

```c
uint8_t *rsb_io(void);                                                  // буфер обмена, 256 байт
int32_t  rsb_generate_keys(uint8_t *private_out, uint8_t *public_out);
int32_t  rsb_get_challenge(const uint8_t *private_key, uint8_t *challenge_out, uint8_t *public_out);
int32_t  rsb_sign_challenge(const uint8_t *private_key, const uint8_t *challenge, uint8_t *signature_out);
int32_t  rsb_check_signature(const uint8_t *public_key, const uint8_t *challenge, const uint8_t *signature);
```

Возвраты:

| Код | Значение |
|---|---|
| `0` | успех |
| `1` / `0` | только `rsb_check_signature`: подпись верна / неверна |
| `-1` | неверный аргумент |
| `-2` | нет случайных байтов |
| `-3` | внутренняя ошибка |

Указатели — внутри буфера `rsb_io`: хост пишет туда входы и читает выходы. Размеры фиксированы (32/32/64).

Импорт — ровно один:

```c
// модуль "env"
int32_t rsb_random(uint8_t *ptr, uint32_t len); // 0 — буфер заполнен случайными байтами
```

Других импортов быть не должно. На сервере это проверяет компилятор: тип окружения в Go реализует сгенерированный интерфейс `Xenv` из одного метода `Xrsb_random`.

Сборка: `cargo rustc --release --target wasm32-unknown-unknown --crate-type cdylib`, стек 64 КиБ (`.cargo/config.toml`), `panic = "abort"`. Перевод: `go run github.com/ncruces/wasm2go@v0.4.15 -embed -pkg boxwasm -o …/boxwasm/box.go`. Всё это делает `packages/rust_secure_box/build-wasm.sh`.

## Проверки, которые проходит любая реализация

- `get_challenge(sk).1 == generate_keys().public_key` для того же `sk`.
- `check_signature(pk, c, sign_challenge(sk, c)) == Ok(true)`.
- `check_signature` — `Ok(false)`, если:
  - ключ другой пары;
  - челлендж другой;
  - в подписи изменён любой байт.
- Челленджи 1000 вызовов подряд различны.
- 16 потоков одновременно получают те же ответы, что и по одному.

Векторы `rsb-vectors.json` — только для заглушки (`"implementation": "stub-v1"`). У настоящей реализации — свои векторы, по тому же формату.

## Пробный ключ (FR-022)

Закрытый ключ из 32 байт `0x01`. Сервер считает RustSecureBox заглушкой, если открытый ключ для пробного ключа равен значению `probe.public_key` из векторов заглушки. Любая ошибка на пробе значит «не заглушка».
