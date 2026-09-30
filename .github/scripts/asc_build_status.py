#!/usr/bin/env python3
"""
Только чтение: показывает, в каком состоянии у Apple последние сборки SmartStock
(обработка, экспортное соответствие, раздача внутренним тестерам).
Скрипт делает исключительно GET-запросы к App Store Connect API и ничего не меняет в аккаунте.
Последний запуск по просьбе: проверка сборки 477 (Google Фото через Picker API).
"""
import os, sys, base64, json, time, urllib.request, urllib.error, urllib.parse, subprocess

BUNDLE_ID = "com.samvel.smartstock.SmartStock"
API_BASE = "https://api.appstoreconnect.apple.com/v1"

key_id = os.environ.get("APPSTORE_KEY_ID", "").strip()
issuer_id = os.environ.get("APPSTORE_ISSUER_ID", "").strip()
key_path = os.environ.get("AUTH_KEY_PATH", "").strip()
if not key_id or not issuer_id or not key_path:
    print("❌ Не заданы переменные API ключа!")
    sys.exit(1)

try:
    from cryptography.hazmat.primitives import serialization, hashes
    from cryptography.hazmat.primitives.asymmetric import ec, utils
except ImportError:
    if subprocess.run([sys.executable, "-m", "pip", "install", "--break-system-packages", "cryptography"]).returncode != 0:
        subprocess.run([sys.executable, "-m", "pip", "install", "cryptography"], check=True)
    from cryptography.hazmat.primitives import serialization, hashes
    from cryptography.hazmat.primitives.asymmetric import ec, utils


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("utf-8")


def make_token() -> str:
    with open(key_path, "rb") as f:
        pk = serialization.load_pem_private_key(f.read().replace(b"\r\n", b"\n").strip(), password=None)
    now = int(time.time())
    header = b64url(json.dumps({"alg": "ES256", "kid": key_id, "typ": "JWT"}, separators=(",", ":")).encode())
    payload = b64url(json.dumps({"iss": issuer_id, "iat": now - 10, "exp": now + 600, "aud": "appstoreconnect-v1"}, separators=(",", ":")).encode())
    signing_input = f"{header}.{payload}".encode()
    r, s = utils.decode_dss_signature(pk.sign(signing_input, ec.ECDSA(hashes.SHA256())))
    return f"{header}.{payload}.{b64url(r.to_bytes(32, 'big') + s.to_bytes(32, 'big'))}"


TOKEN = make_token()


def get(path):
    """Единственный тип запроса в этом скрипте — GET."""
    req = urllib.request.Request(f"{API_BASE}{path}", headers={"Authorization": f"Bearer {TOKEN}"}, method="GET")
    try:
        with urllib.request.urlopen(req) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        print(f"⚠️ Apple API [{e.code}] {path}: {e.read().decode('utf-8', errors='ignore')[:500]}")
        return None


apps = get("/apps?filter[bundleId]=" + urllib.parse.quote(BUNDLE_ID) + "&fields[apps]=name,bundleId")
if not apps or not apps.get("data"):
    print("❌ Приложение не найдено в App Store Connect.")
    sys.exit(1)
app_id = apps["data"][0]["id"]
print(f"📱 Приложение: {apps['data'][0]['attributes'].get('name')} ({BUNDLE_ID}), id {app_id}")

builds = get(
    f"/builds?filter[app]={app_id}&sort=-uploadedDate&limit=6&include=buildBetaDetail"
    "&fields[builds]=version,uploadedDate,processingState,expired,minOsVersion,usesNonExemptEncryption,buildBetaDetail"
    "&fields[buildBetaDetails]=internalBuildState,externalBuildState,autoNotifyEnabled"
)
if not builds:
    sys.exit(1)

details = {i["id"]: i.get("attributes", {}) for i in builds.get("included", []) if i.get("type") == "buildBetaDetails"}
print(f"\nПоследние сборки ({len(builds.get('data', []))}):")
for b in builds.get("data", []):
    a = b.get("attributes", {})
    ref = (b.get("relationships", {}).get("buildBetaDetail", {}).get("data") or {}).get("id")
    d = details.get(ref, {})
    print(
        f"  • {a.get('version')} · загружена {a.get('uploadedDate')} · обработка: {a.get('processingState')}"
        f" · для внутренних тестеров: {d.get('internalBuildState', '—')}"
        f" · шифрование: {a.get('usesNonExemptEncryption')} · мин. iOS: {a.get('minOsVersion')} · истекла: {a.get('expired')}"
    )

print("\nПояснения: processingState VALID = обработана; PROCESSING = ещё обрабатывается; FAILED/INVALID = Apple отклонила (причина придёт письмом).")
print("internalBuildState READY_FOR_BETA_TESTING или IN_BETA_TESTING = доступна внутренним тестерам; MISSING_EXPORT_COMPLIANCE = нужен ответ про шифрование.")
