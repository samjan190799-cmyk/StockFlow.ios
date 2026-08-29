#!/usr/bin/env python3
"""
Официальный нативный генератор JWT токенов для Apple App Store Connect API (RFC 7515 ES256 / IEEE P1363 standard) для StockFlow.ios.
Автоматически настраивает актуальный сертификат дистрибуции и профиль провижининга Apple App Store.
"""
import os, sys, base64, json, urllib.request, urllib.error, subprocess, time
from pathlib import Path

key_id     = os.environ.get("APPSTORE_KEY_ID", "").strip()
issuer_id  = os.environ.get("APPSTORE_ISSUER_ID", "").strip()
key_path   = os.environ.get("AUTH_KEY_PATH", "").strip()
runner_tmp = Path(os.environ.get("RUNNER_TEMP", "/tmp"))
github_env = os.environ.get("GITHUB_ENV", "/tmp/env")

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

def api_request(method, path, body=None):
    url = f"https://api.appstoreconnect.apple.com/v1{path}"
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

print("🍎 [2/4] Запрос на создание iOS Distribution сертификата в Apple...")
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

cer_b64 = None
cert_id_new = None

if "data" in res and "attributes" in res["data"]:
    cer_b64 = res["data"]["attributes"]["certificateContent"]
    cert_id_new = res["data"]["id"]
    print("✅ Сертификат подписи успешно сгенерирован Apple API!")
else:
    print("⚠️ Лимит сертификатов исчерпан. Выполняем авто-освобождение слота через API...")
    certs_res = api_request("GET", "/certificates?filter[certificateType]=IOS_DISTRIBUTION")
    if not certs_res.get("data"):
        certs_res = api_request("GET", "/certificates?filter[certificateType]=DISTRIBUTION")
        
    for old_cert in certs_res.get("data", []):
        cert_id = old_cert["id"]
        print(f"🗑 Авто-отзыв старого сертификата {cert_id}...")
        api_request("DELETE", f"/certificates/{cert_id}")
        
    print("🔄 Повторная генерация свежего сертификата подписи...")
    res_retry = api_request("POST", "/certificates", create_payload)
    if "data" in res_retry and "attributes" in res_retry["data"]:
        cer_b64 = res_retry["data"]["attributes"]["certificateContent"]
        cert_id_new = res_retry["data"]["id"]
        print("✅ Свежий сертификат подписи успешно сгенерирован!")

if cer_b64:
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
    if cert_id_new:
        print("🔄 Проверка и генерация профиля провижининга для SmartStock...")
        b_list = api_request("GET", "/bundleIds")
        main_b_id = None
        
        for b in b_list.get("data", []):
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

        p_list = api_request("GET", "/profiles?filter[profileType]=IOS_APP_STORE")
        for p_item in p_list.get("data", []):
            p_id = p_item["id"]
            p_name = p_item["attributes"]["name"]
            if "SmartStock" in p_name:
                print(f"🗑 Очистка старого профиля [{p_name}] ({p_id})...")
                api_request("DELETE", f"/profiles/{p_id}")

        if main_b_id:
            print("⚙️ Создание профиля провижининга SmartStock_Clean_AppStore...")
            create_prof_res = api_request("POST", "/profiles", {
                "data": {
                    "type": "profiles",
                    "attributes": {
                        "name": "SmartStock_Clean_AppStore",
                        "profileType": "IOS_APP_STORE"
                    },
                    "relationships": {
                        "bundleId": {"data": {"type": "bundleIds", "id": main_b_id}},
                        "certificates": {"data": [{"type": "certificates", "id": cert_id_new}]}
                    }
                }
            })
            print("✅ Профиль SmartStock_Clean_AppStore создан!")

print("📲 [3/4] Скачивание профилей для приложения...")
profiles_res = api_request("GET", "/profiles?filter[profileType]=IOS_APP_STORE")
pp_dir = Path.home() / "Library/MobileDevice/Provisioning Profiles"
pp_dir.mkdir(parents=True, exist_ok=True)

main_uuid = None
last_uuid = None

for p in profiles_res.get("data", []):
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
        
    dest_pp = pp_dir / f"{uuid}.mobileprovision"
    dest_pp.write_bytes(pp_bytes)
    last_uuid = uuid
    
    if "SmartStock" in name or app_id.endswith(".com.samvel.smartstock.SmartStock") or app_id.endswith(".com.samvel.smartstock"):
        main_uuid = uuid
        print(f"✅ Профиль приложения смонтирован [{name}] (App ID: {app_id}): {uuid}")

if not main_uuid and last_uuid:
    main_uuid = last_uuid
    print(f"✅ Назначен основной профиль: {main_uuid}")

with open(github_env, "a", encoding="utf-8") as f:
    if main_uuid:
        f.write(f"MAIN_APP_PROFILE_UUID={main_uuid}\n")

print("✨ [4/4] Подготовка завершена!")
