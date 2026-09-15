# Certificate fixtures for the server pin (feature 036)

GENERATED. Do not edit by hand. Regenerate from `client_backend`:

    go run internal/server/testdata/generate_pin_fixtures.go

Deterministic where it matters: keys from fixed seeds, validity windows and
serial numbers from fixed values. The **subject public key** — the only part of
a certificate the pin ever reads — is identical on every run, and so is
`fingerprint.txt`.

The **signature** bytes are not, and cannot be: Go hedges the ECDSA nonce with
randomness from a source no caller controls, exactly so that nobody depends on
how much a signature consumes. Regenerating therefore shows a diff in the
signature of every ECDSA-signed file here and in nothing else — so regenerate
only when the generator actually changed.

They are made in Go because nothing on the Dart side can mint an X.509
certificate: there is no such package in `pubspec.yaml` and adding one for a
test is not on the table.

## The two keys

| Key | What it is |
|---|---|
| **correct** | the key the pin names — `fingerprint.txt` is its `sha256(SubjectPublicKeyInfo)` |
| **foreign** | somebody else's key entirely |

Fingerprint of the correct key:

    6FYeakrObeuc6pC26ChvxKWaFxNd2LgN861OwQjrjaA=

## The files

| File | Key | Expected verdict | Why it exists |
|---|---|---|---|
| `valid.der` / `.pem` | correct | **accept** | the ordinary case |
| `reissued.der` / `.pem` | correct | **accept** | a different certificate on the same key — a server restart must not lock out a paired device |
| `stranger.der` / `.pem` | foreign | **refuse** | the whole phase in one file |
| `truncated.der` | correct | **refuse** | the header is present, the key behind it is not; a check that hashes whatever follows the header would pass this |
| `headerless.der` | — (Ed25519) | **refuse** | no P-256 SubjectPublicKeyInfo at all; not hypothetical, it is what this server issued before 036 |
| `expired.der` / `.pem` | correct | **accept** | expired in 2020; a home server's owner may not have touched it for years |
| `wrong_name.der` / `.pem` | correct | **accept** | names `mail.example.com` and 203.0.113.7; a home server has no name and its address changes |
| `unknown_issuer.der` / `.pem` | correct | **accept** | signed by an authority nothing trusts; trust comes from the link, not from an issuer |
| `unknown_issuer_chain.pem` | correct | — | leaf + that authority, the chain a real server would present |
| `server_key.pem` | correct | — | PKCS#8 of the correct key, so a test can actually SERVE the three tolerance certificates |
| `stranger_key.pem` | foreign | — | PKCS#8 of the foreign key, so the refusal can be proved against a real handshake |
| `fingerprint.txt` | correct | — | what the pairing link would carry |

The three tolerance cases are deliberately on the **correct** key. Negative
tests alone would be passed by an implementation that refuses on dates or
names — and that implementation breaks on the first home server somebody
forgot about.
