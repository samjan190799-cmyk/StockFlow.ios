#!/bin/bash
# Снимает скриншоты для App Store в симуляторе: iPhone 6.9" и iPad 13", русский и английский интерфейс.
# Использование: take_screenshots.sh <путь к SmartStock.app> <папка для результата>
set -euo pipefail

APP="$1"
OUT="$2"
BUNDLE_ID="com.samvel.smartstock.SmartStock"
SCENES=(queue-new queue-ready detail queue-uploaded prompt agencies settings)

RUNTIME=$(xcrun simctl list runtimes -j | python3 -c '
import json, sys
rt = [r for r in json.load(sys.stdin)["runtimes"] if r.get("isAvailable") and r["identifier"].split(".")[-1].startswith("iOS")]
rt.sort(key=lambda r: [int(x) if x.isdigit() else 0 for x in r["version"].split(".")])
print(rt[-1]["identifier"])')
echo "Рантайм: $RUNTIME"

# Подбор типов устройств: самый новый iPhone Pro Max и самый новый iPad Pro 13"
pick_type() {
  xcrun simctl list devicetypes -j | python3 -c '
import json, re, sys
pattern = sys.argv[1]
types = [t for t in json.load(sys.stdin)["devicetypes"] if re.search(pattern, t["name"])]
def key(t):
    nums = re.findall(r"\d+", t["name"])
    return [int(n) for n in nums]
types.sort(key=key)
print(types[-1]["identifier"] if types else "")' "$1"
}
IPHONE_TYPE=$(pick_type '^iPhone \d+ Pro Max$')
IPHONE63_TYPE=$(pick_type '^iPhone \d+ Pro$')
IPAD_TYPE=$(pick_type '^iPad Pro 13-inch')
echo "iPhone: $IPHONE_TYPE"
echo "iPhone 6.3: $IPHONE63_TYPE"
echo "iPad:   $IPAD_TYPE"

mkdir -p "$OUT"

shoot_device() {
  local label="$1" type="$2" with_ads_check="${3:-yes}"
  [ -z "$type" ] && { echo "Нет типа устройства для $label, пропуск"; return; }
  local udid
  udid=$(xcrun simctl create "shots-$label" "$type" "$RUNTIME")
  xcrun simctl boot "$udid"
  xcrun simctl bootstatus "$udid" -b >/dev/null
  xcrun simctl status_bar "$udid" override --time "9:41" --batteryState charged --batteryLevel 100 \
    --cellularMode active --cellularBars 4 --wifiMode active --wifiBars 3 || true
  xcrun simctl install "$udid" "$APP"

  capture() {
    # capture <папка> <язык> <сцена> <имя файла> <доп. пауза> [доп. аргументы запуска...]
    local dir="$1" lang="$2" scene="$3" name="$4" extra="$5"
    shift 5
    local lang_value="Русский"
    [ "$lang" = "en" ] && lang_value="English"
    mkdir -p "$OUT/$dir"
    xcrun simctl terminate "$udid" "$BUNDLE_ID" >/dev/null 2>&1 || true
    local data
    data=$(xcrun simctl get_app_container "$udid" "$BUNDLE_ID" data)
    rm -f "$data/Documents/ss_done"
    xcrun simctl launch "$udid" "$BUNDLE_ID"       -ss_scene "$scene" -sys_language "$lang_value" -sys_theme "Темная" -sys_notifications NO       -AppleLanguages "($lang)" -AppleLocale "$lang" "$@" >/dev/null
    local waited=0
    until [ -f "$data/Documents/ss_done" ] || [ "$waited" -ge 120 ]; do
      sleep 1
      waited=$((waited + 1))
    done
    [ -f "$data/Documents/ss_done" ] || echo "ВНИМАНИЕ: $dir/$scene не дошёл до готовности за 120 с"
    sleep "$extra"
    xcrun simctl io "$udid" screenshot --type=png "$OUT/$dir/$name.png"
    echo "OK $dir/$name.png"
  }

  for lang in ru en; do
    local n=0
    for scene in "${SCENES[@]}"; do
      n=$((n + 1))
      capture "$label-$lang" "$lang" "$scene" "0${n}-${scene}" 1
    done
  done

  # Проверочные кадры с включённой рекламой (не для App Store): как выглядит баннер на каждой вкладке
  if [ "$with_ads_check" = "yes" ]; then
    for scene in queue-new queue-ready prompt agencies settings; do
      capture "check-ads-$label" ru "$scene" "$scene" 10 -ss_ads 1
    done
  fi

  xcrun simctl shutdown "$udid" || true
  xcrun simctl delete "$udid" || true
}

shoot_device iphone-6.9 "$IPHONE_TYPE"
shoot_device iphone-6.3 "$IPHONE63_TYPE" no
shoot_device ipad-13 "$IPAD_TYPE"

find "$OUT" -name '*.png' -exec file {} \; | sed 's/PNG image data, //' | head -60
