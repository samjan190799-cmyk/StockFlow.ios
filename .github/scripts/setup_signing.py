#!/usr/bin/env python3
"""
Подключает ПОСТОЯННЫЙ сертификат Apple Distribution (из секретов GitHub) и профиль SmartStock_AppStore_Stable.

Что делает:
  1. импортирует .p12 в временный keychain раннера;
  2. находит этот сертификат в аккаунте Apple по серийному номеру (если его там нет — он отозван, и сборка честно падает);
  3. берёт профиль SmartStock_AppStore_Stable; если его нет или он потерял силу — пересоздаёт ТОЛЬКО его;
  4. ставит профиль на раннер и отдаёт его UUID следующим шагам.

Чего НЕ делает: не создаёт сертификаты, не отзывает сертификаты, не трогает чужие профили.
Именно отзыв сертификатов после сборки ломал подпись (ITMS-90035 Invalid Signature).
"""
import os, sys, base64, json, time, subprocess, urllib.request, urllib.error
from pathlib import Path

API_BASE = "https://api.appstoreconnect.apple.com/v1"
BUNDLE_ID = "com.samvel.smartstock.SmartStock"
PROFILE_NAME = "SmartStock_AppStore_Stable"

key_id = os.environ.get("APPSTORE_KEY_ID", "").strip()
issuer_id = os.environ.get("APPSTORE_ISSUER_ID", "").strip()
key_path = os.environ.get("AUTH_KEY_PATH", "").strip()
keychain_path = os.environ.get("KEYCHAIN_PATH", "").strip()
keychain_password = os.environ.get("KEYCHAIN_PASSWORD", "")
p12_b64 = "".join(os.environ.get("DIST_CERT_P12_BASE64", "").split())
p12_password = os.environ.get("DIST_CERT_P12_PASSWORD", "").strip()
runner_tmp = Path(os.environ.get("RUNNER_TEMP", "/tmp"))
github_env = os.environ.get("GITHUB_ENV", "/tmp/env")


def fail(msg):
    print(f"::error::{msg}")
    sys.exit(1)


if not (key_id and issuer_id and key_path):
    fail("Не заданы переменные API ключа App Store Connect.")
if not (p12_b64 and p12_password):
    fail("Не заданы секреты DIST_CERT_P12_BASE64 / DIST_CERT_P12_PASSWORD (постоянный сертификат подписи).")
if not (keychain_path and keychain_password):
    fail("Не задан временный keychain (KEYCHAIN_PATH / KEYCHAIN_PASSWORD).")

try:
    from cryptography.hazmat.primitives import serialization, hashes
    from cryptography.hazmat.primitives.asymmetric import ec, utils
    from cryptography.hazmat.primitives.serialization import pkcs12
except ImportError:
    if subprocess.run([sys.executable, "-m", "pip", "install", "--break-system-packages", "cryptography"]).returncode != 0:
        subprocess.run([sys.executable, "-m", "pip", "install", "cryptography"], check=True)
    from cryptography.hazmat.primitives import serialization, hashes
    from cryptography.hazmat.primitives.asymmetric import ec, utils
    from cryptography.hazmat.primitives.serialization import pkcs12


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("utf-8")


def make_token() -> str:
    with open(key_path, "rb") as f:
        pk = serialization.load_pem_private_key(f.read().replace(b"\r\n", b"\n").strip(), password=None)
    now = int(time.time())
    header = b64url(json.dumps({"alg": "ES256", "kid": key_id, "typ": "JWT"}, separators=(",", ":")).encode())
    payload = b64url(json.dumps({"iss": issuer_id, "iat": now - 10, "exp": now + 600, "aud": "appstoreconnect-v1"},
                                separators=(",", ":")).encode())
    signing_input = f"{header}.{payload}".encode()
    r, s = utils.decode_dss_signature(pk.sign(signing_input, ec.ECDSA(hashes.SHA256())))
    return f"{header}.{payload}.{b64url(r.to_bytes(32, 'big') + s.to_bytes(32, 'big'))}"


TOKEN = make_token()


def api(method, path, body=None):
    req = urllib.request.Request(
        f"{API_BASE}{path}",
        data=json.dumps(body).encode("utf-8") if body is not None else None,
        headers={"Authorization": f"Bearer {TOKEN}", "Content-Type": "application/json"},
        method=method,
    )
    try:
        with urllib.request.urlopen(req) as resp:
            raw = resp.read()
            return json.loads(raw) if raw.strip() else {"status": "ok"}
    except urllib.error.HTTPError as e:
        text = e.read().decode("utf-8", errors="ignore")
        print(f"⚠️ Apple API [{e.code}] {method} {path}: {text}")
        return {"error_code": e.code, "body": text}


# --- 1. Сертификат из секрета ------------------------------------------------------------------
p12_bytes = base64.b64decode(p12_b64)
try:
    _key, cert, _chain = pkcs12.load_key_and_certificates(p12_bytes, p12_password.encode())
except Exception as exc:
    fail(f"Не удалось прочитать .p12 из секрета (неверный пароль или повреждён файл): {exc}")
if cert is None or _key is None:
    fail("В .p12 нет сертификата или закрытого ключа.")

serial_int = cert.serial_number
sha1 = cert.fingerprint(hashes.SHA1()).hex().upper()
subject = cert.subject.rfc4514_string()
print(f"🔐 Сертификат из секрета: {subject}")
print(f"   серийный №…{format(serial_int, 'X')[-6:]} · SHA-1 {sha1[:8]}… · до {cert.not_valid_after_utc.date() if hasattr(cert, 'not_valid_after_utc') else cert.not_valid_after.date()}")

p12_path = runner_tmp / "dist.p12"
p12_path.write_bytes(p12_bytes)
try:
    subprocess.run(["security", "import", str(p12_path), "-k", keychain_path, "-P", p12_password,
                    "-A", "-T", "/usr/bin/codesign", "-T", "/usr/bin/security"], check=True)
    subprocess.run(["security", "set-key-partition-list", "-S", "apple-tool:,apple:,codesign:",
                    "-s", "-k", keychain_password, keychain_path], check=True, stdout=subprocess.DEVNULL)
finally:
    p12_path.unlink(missing_ok=True)
print("✅ Сертификат и закрытый ключ импортированы во временный keychain.")

# --- 2. Сертификат должен существовать (не отозван) в аккаунте Apple ---------------------------
res = api("GET", "/certificates?limit=200&fields[certificates]=certificateType,serialNumber,expirationDate")
if "data" not in res:
    fail("Не удалось получить список сертификатов из App Store Connect API.")
cert_id = None
for c in res["data"]:
    sn = (c.get("attributes", {}).get("serialNumber") or "").strip()
    if sn and int(sn, 16) == serial_int:
        cert_id = c["id"]
        break
if not cert_id:
    fail("Сертификат из секрета отсутствует в аккаунте Apple — его отозвали. Выпустите новый и обновите секреты DIST_CERT_P12_*.")
print(f"✅ Сертификат найден в аккаунте Apple (id {cert_id}), он действителен.")

# --- 3. Профиль SmartStock_AppStore_Stable -----------------------------------------------------
prof_res = api("GET", f"/profiles?filter[name]={PROFILE_NAME}&limit=20&include=certificates")
profile = None
for p in prof_res.get("data", []):
    a = p["attributes"]
    if a.get("name") != PROFILE_NAME:
        continue
    cert_refs = {r["id"] for r in (p.get("relationships", {}).get("certificates", {}).get("data") or [])}
    expires = (a.get("expirationDate") or "")[:10]
    still_valid = a.get("profileState") == "ACTIVE" and cert_id in cert_refs and expires > time.strftime("%Y-%m-%d", time.gmtime(time.time() + 7 * 86400))
    if still_valid:
        profile = p
        break
    print(f"ℹ️ Профиль {PROFILE_NAME} ({p['id']}) не подходит (state={a.get('profileState')}, cert привязан={cert_id in cert_refs}, до {expires}) — пересоздаю только его.")
    api("DELETE", f"/profiles/{p['id']}")

if profile is None:
    bundles = api("GET", f"/bundleIds?filter[identifier]={BUNDLE_ID}&limit=50&fields[bundleIds]=identifier")
    bundle = next((b for b in bundles.get("data", []) if b["attributes"]["identifier"] == BUNDLE_ID), None)
    if not bundle:
        fail(f"Bundle ID {BUNDLE_ID} не найден в аккаунте.")
    created = api("POST", "/profiles", {
        "data": {
            "type": "profiles",
            "attributes": {"name": PROFILE_NAME, "profileType": "IOS_APP_STORE"},
            "relationships": {
                "bundleId": {"data": {"type": "bundleIds", "id": bundle["id"]}},
                "certificates": {"data": [{"type": "certificates", "id": cert_id}]},
            },
        }
    })
    if "data" not in created:
        fail("Не удалось создать профиль провижининга.")
    profile = created["data"]
    print(f"✅ Профиль {PROFILE_NAME} создан.")
else:
    print(f"✅ Профиль {PROFILE_NAME} действителен, переиспользуем.")

attrs = profile["attributes"]
uuid = attrs["uuid"]
pp_dir = Path.home() / "Library/MobileDevice/Provisioning Profiles"
pp_dir.mkdir(parents=True, exist_ok=True)
(pp_dir / f"{uuid}.mobileprovision").write_bytes(base64.b64decode(attrs["profileContent"]))
print(f"✅ Профиль установлен: {uuid} (до {(attrs.get('expirationDate') or '?')[:10]})")

with open(github_env, "a", encoding="utf-8") as f:
    f.write(f"MAIN_APP_PROFILE_UUID={uuid}\n")
    f.write(f"SIGNING_CERT_SHA1={sha1}\n")

print("🔎 Доступные идентичности подписи в keychain:")
subprocess.run(["security", "find-identity", "-v", "-p", "codesigning", keychain_path])
