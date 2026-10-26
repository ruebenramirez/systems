# Continuwuity / conduwuit client-API quirks

`matrix.rueb.dev` runs **Continuwuity**, which is a fork of **conduwuit** (Rust) —
*not* a Synapse fork. Several client-API behaviours differ from the Matrix spec
and from what Synapse-derived tooling assumes. Each item below was observed
directly on this server; several cost real debugging time.

Server at time of writing: `matrix-continuwuity-26.9.1`, `GET /versions` → `v1.18`.

---

## 1. `GET /keys` does not report cross-signing — do not trust it

`GET /_matrix/client/v3/keys` returns:

```json
{ "master_keys": {}, "self_signing_keys": {}, "user_signing_keys": {}, "device_keys": {} }
```

even for an account with a complete, healthy cross-signing hierarchy and nine
devices. **It is structurally incapable of showing what you are looking for.** An
empty result here means nothing.

Use `POST /_matrix/client/v3/keys/query` instead — and it must be the **object**
form:

```bash
# works
-d '{"device_keys":{"@r3v2:matrix.rueb.dev":[]}}'

# silently returns nothing — no error, just empty
-d '{"device_keys":["@r3v2:matrix.rueb.dev"]}'
```

The array form is legal per spec. Here it returns an empty result set with a 200,
which is the worst possible failure mode: a check that quietly passes while
measuring nothing.

Verify a signature chain like this:

```bash
curl -s -X POST "$H/_matrix/client/v3/keys/query" -H "Authorization: Bearer $TOK" \
  -H 'Content-Type: application/json' -d '{"device_keys":{"@user:matrix.rueb.dev":[]}}' \
| jq -r '.device_keys["@user:matrix.rueb.dev"] | to_entries[]
        | "\(.key[0:10])  signed-by: \(((.value.signatures//{})["@user:matrix.rueb.dev"]//{}|keys)|join(","))"'
```

A healthy account shows each device signed by the self-signing key id, the SSK
and USK signed by the master key id, and the MK self-signed.

---

## 2. UIA requires `identifier.type`

Every user-interactive-auth call (device deletion, password change) requires the
`type` field inside `identifier`, which the spec makes optional in practice:

```json
{"auth":{
  "type":"m.login.password",
  "identifier":{"type":"m.id.user","user":"@r3v2:matrix.rueb.dev"},
  "password":"...",
  "session":"..."
}}
```

Omitting `identifier.type` yields a misleading
`M_BAD_JSON: deserialization failed: missing field 'type'`, which points at the
wrong nesting level.

---

## 3. `/account/password` uses `new_password`, not `newpassword`

The spec field is `newpassword`. conduwuit expects **`new_password`** (snake_case).

It also **validates the body before running UIA**, so the usual "send `{}` to
discover the session id" probe returns `M_BAD_JSON` instead of a `401` with a
session. Include the field in the probe:

```bash
SID=$(curl -s -X POST "$H/_matrix/client/v3/account/password" \
  -H "Authorization: Bearer $TOK" -H 'Content-Type: application/json' \
  -d "{\"new_password\":\"$NEW\"}" | jq -r '.session')
```

### ⚠️ Changing the password logs out every other device

`/account/password` defaults to `logout_devices: true`. Changing the password
**invalidates all other sessions** — every Element/SchildiChat session is signed
out, and their device entries are removed.

Only the access token used to authenticate the request survives.

Do not assume a password change is low-friction on this server. Before changing
it, confirm the user has their **recovery key**: after the logout, no device
holds the cross-signing private keys, and SSSS is the only route back to them.
Logging out does not erase local crypto stores, but reinstalling or clearing app
data does — so advise against clearing app data until re-login is done.

---

## 4. SSSS: no retrieval endpoint, but the secrets are in account_data

`GET /_matrix/client/v3/keys/device_signing/` returns **404** (only an unstable
`upload` route exists in the binary). That does **not** mean SSSS is unused.

The SSSS secrets live in account_data and are readable:

```
GET /_matrix/client/v3/user/<uid>/account_data/m.cross_signing.master
```

Shape — note the extra nesting under a random 32-char key id, not `default`:

```json
{ "encrypted": { "caHdvBcvOkYyScLGdGDsReSn8TeQ9kxb":
    { "iv": "...", "ciphertext": "...", "mac": "..." } } }
```

Present for both `@r3v2` and `@hermes`: `m.cross_signing.master`,
`m.cross_signing.self_signing`, `m.cross_signing.user_signing`,
`m.megolm_backup.v1`.

### Verifying a recovery key offline

Do this with **mautrix's own functions** so the construction is correct by
construction — hand-rolling the KDF produced a false negative once already:

```python
from mautrix.crypto.ssss.util import decode_base58_recovery_key, calculate_hash
k = decode_base58_recovery_key(RECOVERY_KEY)          # None if malformed
ok  = calculate_hash(k, iv) == mac.rstrip("=")        # iv/mac from account_data
```

Run it where mautrix is installed, e.g. inside the Hermes container:

```bash
sudo podman exec -e RK="$RK" -e IV="$IV" -e MAC="$MAC" hermes \
  /opt/hermes/.venv/bin/python -c '...as above...'
```

Recovery key format (mautrix `decode_base58_recovery_key`): 35 bytes,
`[0] == 0x8b`, `[1] == 1` (version), `[2:34]` = key, `[34]` = XOR parity of the
first 34 bytes. Displayed as 48 base58 chars in 12 groups of 4 (59 chars with
spaces).

---

## 5. Room key backup response shape

`GET /_matrix/client/v3/room_keys/keys` nests sessions under **`sessions`**, not
the spec's `keys`:

```
rooms.<room_id>.sessions.<session_id>.{first_message_index, forwarded_count,
                                       is_verified, session_data}
session_data: { ciphertext, ephemeral, mac }
```

`GET /room_keys/keys/{room_id}/{session_id}` returns **404** — fetch the whole
set and index into it.

Backup `auth_data` may carry **no `pbkdf2` block**, in which case the backup key
is used directly rather than derived from the recovery key via PBKDF2.

---

## 6. Smaller oddities

- `GET /account/whoami` returns `device_id` but `user: null`.
- Device `last_seen_ip` is always `127.0.0.1` because HAProxy terminates TLS
  locally without forwarding the client address. Until `proxy_protocol` /
  `X-Forwarded-For` is configured, the IP field is useless for triaging an
  unknown device.
- Dehydrated devices (MSC3814) appear in the device list with a long 43-char
  device id. They are auto-managed — do not delete them.
- `DELETE /devices/{id}` needs a **fresh UIA session per device**; a session id
  cannot be reused across deletions.
