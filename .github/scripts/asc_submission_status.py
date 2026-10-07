#!/usr/bin/env python3
"""
Только чтение: показывает, в каком состоянии у Apple последние сборки SmartStock
(обработка, экспортное соответствие, раздача внутренним тестерам).
Скрипт делает исключительно GET-запросы к App Store Connect API и ничего не меняет в аккаунте.
Последний запуск по просьбе: проверка сборки 477 (Google Фото через Picker API), сборка 479.
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
print(f"📱 Приложение: {apps['data'][0]['attributes'].get('name')}, id {app_id}")

versions = get(f"/apps/{app_id}/appStoreVersions?limit=5&include=build&fields[appStoreVersions]=versionString,appStoreState,platform,createdDate&fields[builds]=version")
print()
print("Версии:")
if versions:
    builds = {i["id"]: i.get("attributes", {}).get("version") for i in versions.get("included", []) if i.get("type") == "builds"}
    for v in versions.get("data", []):
        a = v.get("attributes", {})
        b = (v.get("relationships", {}).get("build", {}).get("data") or {}).get("id")
        print(f"  • {a.get('platform')} {a.get('versionString')} · {a.get('appStoreState')} · сборка {builds.get(b, '—')} · создана {a.get('createdDate')}")

subs = get(f"/apps/{app_id}/reviewSubmissions?limit=10&include=items&fields[reviewSubmissions]=state,platform,submittedDate")
print()
print("Заявки на проверку (reviewSubmissions):")
if subs:
    items = {i["id"]: i for i in subs.get("included", [])}
    for s in subs.get("data", []):
        a = s.get("attributes", {})
        print(f"  • {s['id']} · {a.get('platform')} · {a.get('state')} · отправлена {a.get('submittedDate')}")
        for ref in (s.get("relationships", {}).get("items", {}).get("data") or []):
            it = items.get(ref["id"], {})
            rels = {k: (v.get("data") or {}).get("type") for k, v in (it.get("relationships") or {}).items() if v.get("data")}
            print(f"      - элемент {ref['id']} · {it.get('attributes', {}).get('state')} · {rels}")

groups = get(f"/apps/{app_id}/subscriptionGroups?limit=5")
print()
print("Группы подписок и подписки:")
for g in (groups or {}).get("data", []):
    print(f"  группа {g['id']} · {g.get('attributes', {}).get('referenceName')}")
    subs_list = get(f"/subscriptionGroups/{g['id']}/subscriptions?limit=10")
    for s in (subs_list or {}).get("data", []):
        a = s.get("attributes", {})
        shot = get(f"/subscriptions/{s['id']}/appStoreReviewScreenshot")
        sd = (shot or {}).get("data") or {}
        sa = sd.get("attributes", {}) if isinstance(sd, dict) else {}
        state = sa.get("assetDeliveryState")
        state = state.get("state") if isinstance(state, dict) else state
        shot_text = f"{sa.get('fileName')} · {sa.get('fileSize')} байт · {state}" if sa else "нет"
        print(f"    • {a.get('productId')} · {a.get('name')} · состояние {a.get('state')} · скриншот для проверки: {shot_text}")
