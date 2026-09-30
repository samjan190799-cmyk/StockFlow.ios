#!/usr/bin/env python3
"""
Официальный нативный генератор JWT токенов для Apple App Store Connect API (RFC 7515 ES256 / IEEE P1363 standard) для StockFlow.ios.
Автоматически настраивает актуальный сертификат дистрибуции и профиль провижининга Apple App Store.

Режимы:
  (без аргументов) — создать сертификат и профиль SmartStock для сборки;
  cleanup          — удалить сертификат и профиль, созданные этим запуском.

Чужие сертификаты и профили (другие приложения аккаунта) скрипт не отзывает и не удаляет.
"""
import os, sys, base64, json, urllib.request, urllib.error, subprocess, time
from pathlib import Path

key_id     = os.environ.get("APPSTORE_KEY_ID", "").strip()
issuer_id  = os.environ.get("APPSTORE_ISSUER_ID", "").strip()
key_path   = os.environ.get("AUTH_KEY_PATH", "").strip()
runner_tmp = Path(os.environ.get("RUNNER_TEMP", "/tmp"))
github_env = os.environ.get("GITHUB_ENV", "/tmp/env")

mode = sys.argv[1] if len(sys.argv) > 1 else "setup"
created_cert_id_env = os.environ.get("CREATED_CERT_ID", "").strip()
created_profile_id_env = os.environ.get("CREATED_PROFILE_ID", "").strip()

if mode == "cleanup" and not created_cert_id_env and not created_profile_id_env:
    print("ℹ️ Нечего чистить: в этом запуске сертификат и профиль не создавались.")
    sys.exit(0)

if not key_id or not issuer_id or not key_path:
    print("❌ Ошибка: не заданы переменные API ключа!")
    sys.exit(1)

try:
    from cryptography.hazmat.primitives import serialization, hashes
    from cryptography.hazmat.primitives.asymmetric import ec, utils
except ImportError:
    subprocess.run([sys.executable, "-m", "pip", "install", "--break-system-packages", "cryptography"], check=True)
    from cryptography.hazmat.primitives import serialization, hashes
    from cryptography.hazmat.primitives.asymmetric import ec, utils

# Читаем .p8 ключ
with open(key_path, "rb") as f:
    key_bytes = f.read().replace(b"\r\n", b"\n").replace(b"\r", b"\n").strip()
    pk = serialization.load_pem_private_key(key_bytes, password=None)

def base64url_encode(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b'=').decode('utf-8')

# Генерируем RFC 7515 JWS ES256 токен вручную для 100% совместимости с Apple API
now = int(time.time())
header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
payload = {
    "iss": issuer_id,
    "iat": now - 10,
    "exp": now + 1100,
    "aud": "appstoreconnect-v1"
}

header_b64 = base64url_encode(json.dumps(header, separators=(',', ':')).encode('utf-8'))
payload_b64 = base64url_encode(json.dumps(payload, separators=(',', ':')).encode('utf-8'))

signing_input = f"{header_b64}.{payload_b64}".encode('utf-8')

# DER подпись из cryptography
der_signature = pk.sign(signing_input, ec.ECDSA(hashes.SHA256()))

# Конвертируем DER подпись (ASN.1) в формат IEEE P1363 (ровно 64 байта R+S), требуемый Apple API
r, s = utils.decode_dss_signature(der_signature)
raw_signature = r.to_bytes(32, byteorder='big') + s.to_bytes(32, byteorder='big')
sig_b64 = base64url_encode(raw_signature)

token = f"{header_b64}.{payload_b64}.{sig_b64}"

API_BASE = "https://api.appstoreconnect.apple.com/v1"

# Сертификаты подписи принадлежат всей команде (аккаунту), а не одному приложению:
# один и тот же сертификат может подписывать сразу несколько приложений.
# Поэтому скрипт отзывает только те сертификаты, которые используются профилями
# SmartStock и больше ничьими. Всё остальное (DriveAlert, сертификаты без профилей,
# сертификаты неизвестного владельца) не трогаем.
OUR_BUNDLE = "com.samvel.smartstock"


def is_our_bundle(identifier):
    return identifier == OUR_BUNDLE or identifier.startswith(OUR_BUNDLE + ".")


def api_request(method, path, body=None):
    url = f"{API_BASE}{path}"
    data = json.dumps(body).encode("utf-8") if body else None
    req = urllib.request.Request(
        url,
        data=data,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json"
        },
        method=method
    )
    try:
        with urllib.request.urlopen(req) as r:
            if r.status == 204:
                return {"status": "success"}
            res_content = r.read()
            if not res_content or not res_content.strip():
                return {"status": "success"}
            return json.loads(res_content)
    except urllib.error.HTTPError as e:
        err_b = e.read().decode("utf-8", errors="ignore")
        print(f"⚠️ Apple API Answer [{e.code}]: {err_b}")
        return {"error_code": e.code, "body": err_b}


def api_get_all(path):
    """GET со всеми страницами. Возвращает (data, included, ok)."""
    data, included = [], []
    next_path = path
    while next_path:
        res = api_request("GET", next_path)
        if "error_code" in res:
            return data, included, False
        data.extend(res.get("data", []))
        included.extend(res.get("included", []))
        nxt = (res.get("links") or {}).get("next")
        next_path = nxt[len(API_BASE):] if nxt and nxt.startswith(API_BASE) else None
    return data, included, True


def run_cleanup():
    """Удаляет профиль и сертификат, созданные именно этим запуском, чтобы не занимать слоты аккаунта."""
    print("🧹 Чистка: удаляем профиль и сертификат, созданные этим запуском (чужие не трогаем)...")
    if created_profile_id_env:
        res = api_request("DELETE", f"/profiles/{created_profile_id_env}")
        print("✅ Профиль удалён" if "error_code" not in res else "⚠️ Профиль не удалён (не критично)")
    if created_cert_id_env:
        res = api_request("DELETE", f"/certificates/{created_cert_id_env}")
        print("✅ Сертификат отозван" if "error_code" not in res else "⚠️ Сертификат не отозван (не критично)")


if mode == "cleanup":
    try:
        run_cleanup()
    except Exception as exc:
        print(f"⚠️ Чистка не удалась (не критично): {exc}")
    sys.exit(0)


def load_inventory():
    """Кому принадлежит каждый сертификат подписи. None, если Apple не отдала данные."""
    certs, _, ok_certs = api_get_all(
        "/certificates?limit=200&fields[certificates]=certificateType,displayName,name,serialNumber,expirationDate"
    )
    profiles, included, ok_profiles = api_get_all(
        "/profiles?limit=200&include=bundleId,certificates"
        "&fields[profiles]=name,profileType,profileState,bundleId,certificates"
        "&fields[bundleIds]=identifier&fields[certificates]=certificateType"
    )
    if not (ok_certs and ok_profiles):
        return None

    bundle_identifiers = {
        item["id"]: item.get("attributes", {}).get("identifier", "")
        for item in included if item.get("type") == "bundleIds"
    }
    dist_certs = {
        c["id"]: c for c in certs
        if c.get("attributes", {}).get("certificateType") in ("IOS_DISTRIBUTION", "DISTRIBUTION")
    }
    used_by = {cert_id: set() for cert_id in dist_certs}
    our_profiles = []
    for p in profiles:
        rel = p.get("relationships", {})
        bundle_ref = (rel.get("bundleId", {}).get("data") or {})
        identifier = bundle_identifiers.get(bundle_ref.get("id"), "")
        if is_our_bundle(identifier):
            our_profiles.append(p)
        for cert_ref in (rel.get("certificates", {}).get("data") or []):
            if cert_ref.get("id") in used_by:
                used_by[cert_ref["id"]].add(identifier or "неизвестное приложение")
    return {"certs": dist_certs, "used_by": used_by, "our_profiles": our_profiles}


def revocable_cert_ids(inv):
    """Сертификаты, которыми пользуется только SmartStock. Самые старые первыми."""
    ids = [cid for cid, used in inv["used_by"].items() if used and all(is_our_bundle(x) for x in used)]
    ids.sort(key=lambda cid: inv["certs"][cid].get("attributes", {}).get("expirationDate") or "")
    return ids


def describe_cert(inv, cert_id):
    attrs = inv["certs"][cert_id].get("attributes", {})
    used = inv["used_by"][cert_id]
    serial = (attrs.get("serialNumber") or "")[-6:]
    owner = "профили: " + ", ".join(sorted(used)) if used else "нет профилей, владелец неизвестен"
    verdict = "SmartStock — можно освободить" if cert_id in revocable_cert_ids(inv) else "не трогаем"
    return f"{cert_id} · {attrs.get('name') or attrs.get('displayName') or 'сертификат'} · №…{serial} · до {(attrs.get('expirationDate') or '?')[:10]} · {owner} → {verdict}"


def cert_created(res):
    return "data" in res and "attributes" in res["data"]


print("🔑 [1/4] Генерация локальной парной пары ключей и CSR...")
csr_key_path = Path(runner_tmp) / "dist.key"
csr_path = Path(runner_tmp) / "dist.csr"

subprocess.run(["openssl", "genrsa", "-out", str(csr_key_path), "2048"], check=True)
subprocess.run([
    "openssl", "req", "-new", "-key", str(csr_key_path),
    "-out", str(csr_path), "-subj", "/CN=iOS Distribution/O=SmartStock/C=US"
], check=True)

csr_raw = csr_path.read_text()
csr_pem = csr_raw.replace("-----BEGIN CERTIFICATE REQUEST-----", "").replace("-----END CERTIFICATE REQUEST-----", "").replace("\r", "").replace("\n", "").strip()

print("🍎 [2/4] Инвентаризация сертификатов и профилей аккаунта (только чтение)...")
inventory = load_inventory()
if inventory is None:
    print("⚠️ Apple не отдала список сертификатов или профилей. Чужие сертификаты под защитой: ничего отзываться не будет.")
else:
    if not inventory["certs"]:
        print("В аккаунте нет сертификатов дистрибуции.")
    for cert_id in inventory["certs"]:
        print("  •", describe_cert(inventory, cert_id))

print("🍎 Запрос на создание iOS Distribution сертификата в Apple...")
create_payload = {
    "data": {
        "type": "certificates",
        "attributes": {
            "certificateType": "IOS_DISTRIBUTION",
            "csrContent": csr_pem
        }
    }
}

res = api_request("POST", "/certificates", create_payload)

if not cert_created(res) and res.get("error_code") in (401, 403):
    print("❌ Apple отклонила ключ App Store Connect API (нет прав на сертификаты). Проверьте роль ключа: нужна Admin.")
    sys.exit(1)

if not cert_created(res):
    print("⚠️ Не удалось создать сертификат (скорее всего, исчерпан лимит). Освобождаем слот, затрагивая только сертификаты SmartStock...")
    if inventory is not None:
        for cert_id in revocable_cert_ids(inventory):
            print(f"🗑 Отзыв сертификата SmartStock {cert_id} (другие приложения его не используют)...")
            del_res = api_request("DELETE", f"/certificates/{cert_id}")
            if "error_code" in del_res:
                continue
            time.sleep(2)
            res = api_request("POST", "/certificates", create_payload)
            if cert_created(res):
                break

if not cert_created(res):
    print("❌ Не удалось получить сертификат подписи, а отзывать чужие сертификаты скрипт не будет.")
    if inventory is not None and inventory["certs"]:
        print("Сертификаты, занимающие слоты аккаунта:")
        for cert_id in inventory["certs"]:
            print("  •", describe_cert(inventory, cert_id))
        print("Отзовите ненужный сертификат вручную: developer.apple.com → Certificates, затем запустите сборку снова.")
    sys.exit(1)

cer_b64 = res["data"]["attributes"]["certificateContent"]
cert_id_new = res["data"]["id"]
print("✅ Сертификат подписи успешно сгенерирован Apple API!")

# Запоминаем сразу, чтобы завершающий шаг workflow убрал сертификат даже при сбое сборки
with open(github_env, "a", encoding="utf-8") as f:
    f.write(f"CREATED_CERT_ID={cert_id_new}\n")

new_profile_name = None

# Сохраняем .cer и собираем .p12
cer_path = runner_tmp / "dist.cer"
p12_path = runner_tmp / "dist.p12"
cer_path.write_bytes(base64.b64decode(cer_b64))

# Конвертируем DER сертификат в PEM
subprocess.run([
    "openssl", "x509", "-inform", "DER", "-in", str(cer_path), "-out", str(runner_tmp / "dist.pem")
], check=True)

# Собираем .p12 через openssl
p12_cmd = [
    "openssl", "pkcs12", "-export", "-legacy", "-out", str(p12_path),
    "-inkey", str(csr_key_path), "-in", str(runner_tmp / "dist.pem"),
    "-passout", "pass:123456"
]
res_p12 = subprocess.run(p12_cmd)
if res_p12.returncode != 0:
    subprocess.run([
        "openssl", "pkcs12", "-export", "-out", str(p12_path),
        "-inkey", str(csr_key_path), "-in", str(runner_tmp / "dist.pem"),
        "-passout", "pass:123456"
    ], check=True)

keychain_path = os.environ.get("KEYCHAIN_PATH", "")
if keychain_path and Path(keychain_path).exists():
    print(f"🔑 Импорт .p12 сертификата в Keychain: {keychain_path}")
    subprocess.run([
        "security", "import", str(p12_path),
        "-k", keychain_path,
        "-P", "123456",
        "-A", "-T", "/usr/bin/codesign", "-T", "/usr/bin/security"
    ], check=True)
    subprocess.run([
        "security", "list-keychains", "-d", "user", "-s", keychain_path, "login.keychain-db"
    ], check=True)
    subprocess.run([
        "security", "set-key-partition-list",
        "-S", "apple-tool:,apple:,codesign:",
        "-s", "-k", "123456", keychain_path
    ], check=True)
    print("✅ Сертификат подписи успешно импортирован и зарегистрирован в Keychain!")

# Привязываем новый сертификат к профилю
print("🔄 Проверка и генерация профиля провижининга для SmartStock...")
bundle_list, _, _ = api_get_all("/bundleIds?limit=200&fields[bundleIds]=identifier")
main_b_id = None

for b in bundle_list:
    bid_identifier = b.get("attributes", {}).get("identifier")
    if bid_identifier == "com.samvel.smartstock.SmartStock" or bid_identifier == "com.samvel.smartstock":
        main_b_id = b.get("id")
        print(f"Найдено совпадение Bundle ID [{bid_identifier}]: {main_b_id}")
        break

if not main_b_id:
    print("⚙️ Регистрация нового Bundle ID [com.samvel.smartstock.SmartStock]...")
    create_bid_res = api_request("POST", "/bundleIds", {
        "data": {
            "type": "bundleIds",
            "attributes": {
                "identifier": "com.samvel.smartstock.SmartStock",
                "name": "SmartStock",
                "platform": "IOS"
            }
        }
    })
    if "data" in create_bid_res:
        main_b_id = create_bid_res["data"]["id"]
        print(f"✅ Bundle ID зарегистрирован: {main_b_id}")

# Старые профили чистим только у нашего приложения (по Bundle ID, а не по имени)
deleted_any = False
if inventory is not None:
    for p_item in inventory["our_profiles"]:
        if p_item.get("attributes", {}).get("profileType") != "IOS_APP_STORE":
            continue
        p_id = p_item["id"]
        p_name = p_item.get("attributes", {}).get("name", "")
        print(f"🗑 Очистка старого профиля SmartStock [{p_name}] ({p_id})...")
        api_request("DELETE", f"/profiles/{p_id}")
        deleted_any = True
if deleted_any:
    time.sleep(3)  # Apple применяет удаление с небольшой задержкой

if main_b_id:
    # Уникальное имя: повторное имя даёт 409 "Multiple profiles found with the name"
    new_profile_name = f"SmartStock_AppStore_{int(time.time())}"
    print(f"⚙️ Создание профиля провижининга {new_profile_name}...")
    create_prof_res = api_request("POST", "/profiles", {
        "data": {
            "type": "profiles",
            "attributes": {
                "name": new_profile_name,
                "profileType": "IOS_APP_STORE"
            },
            "relationships": {
                "bundleId": {"data": {"type": "bundleIds", "id": main_b_id}},
                "certificates": {"data": [{"type": "certificates", "id": cert_id_new}]}
            }
        }
    })
    if "data" not in create_prof_res:
        print("❌ Не удалось создать профиль провижининга. Останавливаем сборку, чтобы не подписать чужим профилем.")
        sys.exit(1)
    with open(github_env, "a", encoding="utf-8") as f:
        f.write(f"CREATED_PROFILE_ID={create_prof_res['data']['id']}\n")
    print(f"✅ Профиль {new_profile_name} создан!")

print("📲 [3/4] Скачивание профилей для приложения...")
profile_items, _, _ = api_get_all("/profiles?filter[profileType]=IOS_APP_STORE&limit=200")
pp_dir = Path.home() / "Library/MobileDevice/Provisioning Profiles"
pp_dir.mkdir(parents=True, exist_ok=True)

main_uuid = None
fallback_uuid = None  # любой профиль именно нашего Bundle ID, если свежесозданный не найден

for p in profile_items:
    name = p["attributes"]["name"]
    pp_b64 = p["attributes"]["profileContent"]
    pp_bytes = base64.b64decode(pp_b64)

    tmp_pp = runner_tmp / f"temp_{p['id']}.mobileprovision"
    tmp_pp.write_bytes(pp_bytes)

    try:
        uuid = subprocess.check_output(f"security cms -D -i '{tmp_pp}' | plutil -extract UUID raw -", shell=True, text=True).strip()
    except Exception:
        import uuid as u_lib
        uuid = str(u_lib.uuid4())

    try:
        app_id = subprocess.check_output(f"security cms -D -i '{tmp_pp}' | plutil -extract Entitlements.application-identifier raw -", shell=True, text=True).strip()
    except Exception:
        app_id = ""

    # Берём только профили НАШЕГО приложения. Профили других приложений аккаунта (например DriveAlert) не трогаем.
    is_our_app = (
        app_id.endswith(".com.samvel.smartstock.SmartStock")
        or app_id.endswith(".com.samvel.smartstock")
        or (app_id == "" and "SmartStock" in name)
    )
    if is_our_app:
        (pp_dir / f"{uuid}.mobileprovision").write_bytes(pp_bytes)
        if new_profile_name and name == new_profile_name:
            main_uuid = uuid
            print(f"✅ Профиль приложения смонтирован [{name}] (App ID: {app_id}): {uuid}")
        elif fallback_uuid is None:
            fallback_uuid = uuid

if not main_uuid and fallback_uuid:
    main_uuid = fallback_uuid
    print(f"✅ Назначен профиль приложения: {main_uuid}")

if not main_uuid:
    print("❌ Не найден профиль провижининга для com.samvel.smartstock.SmartStock. Останавливаем сборку.")
    sys.exit(1)

with open(github_env, "a", encoding="utf-8") as f:
    f.write(f"MAIN_APP_PROFILE_UUID={main_uuid}\n")

print("✨ [4/4] Подготовка завершена!")
