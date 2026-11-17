#!/bin/bash
# Подготовка подписи для сборки в GitHub Actions без Xcode.
# Порядок и подробности: docs/testflight-github-actions.md
#
#   scripts/testflight-signing.sh csr
#       закрытый ключ + запрос на сертификат (CSR) для developer.apple.com
#   scripts/testflight-signing.sh p12 ~/Downloads/distribution.cer
#       сертификат от Apple + ключ → distribution.p12 со случайным паролем
#   scripts/testflight-signing.sh secrets ~/Downloads/CoughScan.mobileprovision ~/Downloads/AuthKey_XXXXXXXXXX.p8 [готовый.p12]
#       проверка и значения секретов GitHub в отдельных файлах
#
# Всё складывается в ~/CoughScan-signing (или $SIGNING_DIR), вне репозитория.
# Файлы оттуда нельзя коммитить и пересылать: это ключи подписи.

set -euo pipefail

DIR="${SIGNING_DIR:-$HOME/CoughScan-signing}"
KEY="$DIR/distribution.key"
CSR="$DIR/distribution.csr"
P12="$DIR/distribution.p12"
P12_PASS_FILE="$DIR/p12-password.txt"
OUT="$DIR/github-secrets"

# Системный LibreSSL создаёт .p12, который гарантированно читает `security import` на macOS.
OPENSSL=/usr/bin/openssl
[ -x "$OPENSSL" ] || OPENSSL="$(command -v openssl)"

die() { echo "Ошибка: $*" >&2; exit 1; }

prepare_dir() {
    mkdir -p "$DIR"
    chmod 700 "$DIR"
}

cmd_csr() {
    prepare_dir
    [ -e "$KEY" ] && die "$KEY уже существует. Если сертификат по нему ещё не выпускали, удалите файл и повторите."
    ( umask 077; "$OPENSSL" genrsa -out "$KEY" 2048 2>/dev/null )
    "$OPENSSL" req -new -key "$KEY" -out "$CSR" -subj "/CN=CoughScan Distribution/O=CoughScan/C=RU"
    cat <<EOF
Готово:
  закрытый ключ: $KEY   (никому не отправлять)
  запрос (CSR):  $CSR

Дальше: developer.apple.com → Certificates → «+» → Apple Distribution → загрузите $CSR,
скачайте .cer и выполните:
  scripts/testflight-signing.sh p12 ~/Downloads/distribution.cer
EOF
}

cmd_p12() {
    local cer="${1:-}"
    [ -f "$cer" ] || die "укажите путь к скачанному .cer"
    [ -f "$KEY" ] || die "нет $KEY — сначала выполните шаг csr"
    prepare_dir

    local pem="$DIR/distribution.pem"
    "$OPENSSL" x509 -inform DER -in "$cer" -out "$pem" 2>/dev/null \
        || "$OPENSSL" x509 -in "$cer" -out "$pem" \
        || die "не удалось прочитать сертификат $cer"

    # Сертификат должен соответствовать нашему закрытому ключу.
    local cert_mod key_mod
    cert_mod="$("$OPENSSL" x509 -noout -modulus -in "$pem" | "$OPENSSL" sha256)"
    key_mod="$("$OPENSSL" rsa -noout -modulus -in "$KEY" 2>/dev/null | "$OPENSSL" sha256)"
    [ "$cert_mod" = "$key_mod" ] || die "сертификат выпущен не по этому ключу ($KEY)"

    local pass
    pass="$("$OPENSSL" rand -hex 16)"
    ( umask 077
      "$OPENSSL" pkcs12 -export -inkey "$KEY" -in "$pem" -out "$P12" \
          -name "CoughScan Distribution" -passout "pass:$pass" \
          -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1
      printf '%s' "$pass" > "$P12_PASS_FILE" )
    rm -f "$pem"
    echo "Готово: $P12 (пароль в $P12_PASS_FILE)"
    echo "Дальше: создайте профиль App Store Connect и ключ API, затем выполните шаг secrets."
}

cmd_secrets() {
    local profile="${1:-}" p8="${2:-}" p12="${3:-$P12}"
    [ -f "$profile" ] || die "укажите путь к .mobileprovision"
    [ -f "$p8" ] || die "укажите путь к AuthKey_XXXXXXXXXX.p8"
    [ -f "$p12" ] || die "нет $p12 — выполните шаги csr и p12 или передайте свой .p12 третьим аргументом"
    prepare_dir

    local pass
    if [ "$p12" = "$P12" ] && [ -f "$P12_PASS_FILE" ]; then
        pass="$(cat "$P12_PASS_FILE")"
    else
        read -r -s -p "Пароль от $p12: " pass; echo
    fi

    local key_id
    key_id="$(basename "$p8" | sed -nE 's/^AuthKey_([A-Z0-9]+)\.p8$/\1/p')"
    [ -n "$key_id" ] || die "имя ключа API должно быть вида AuthKey_<KEY_ID>.p8 (как его скачивает App Store Connect)"

    # Сертификат из .p12 (SHA-1) — должен входить в профиль.
    local cert_sha1
    cert_sha1="$("$OPENSSL" pkcs12 -in "$p12" -passin "pass:$pass" -nokeys -clcerts 2>/dev/null \
        | "$OPENSSL" x509 -noout -fingerprint -sha1 | sed 's/.*=//; s/://g' | tr 'a-f' 'A-F')"
    [ -n "$cert_sha1" ] || die "не удалось открыть $p12 (неверный пароль?)"

    local plist="$DIR/.profile.plist"
    security cms -D -i "$profile" > "$plist" || die "не удалось прочитать профиль $profile"
    /usr/bin/python3 -I - "$plist" "$cert_sha1" <<'PY' || { rm -f "$plist"; exit 1; }
import hashlib, plistlib, sys
with open(sys.argv[1], "rb") as f:
    p = plistlib.load(f)
team = p["TeamIdentifier"][0]
app_id = p["Entitlements"]["application-identifier"]
bundle = app_id[len(team) + 1:]
certs = {hashlib.sha1(c).hexdigest().upper() for c in p.get("DeveloperCertificates", [])}
print(f"Профиль:   {p['Name']}")
print(f"Команда:   {team}")
print(f"Bundle ID: {bundle}")
print(f"Истекает:  {p['ExpirationDate']:%d.%m.%Y}")
errors = []
if p.get("ProvisionedDevices"):
    errors.append("профиль привязан к устройствам — нужен тип App Store Connect, а не Development/Ad Hoc")
if p.get("ProvisionsAllDevices"):
    errors.append("это Enterprise-профиль — для TestFlight нужен тип App Store Connect")
if "*" in bundle:
    errors.append("профиль выпущен на wildcard App ID — нужен явный Bundle ID")
if sys.argv[2] not in certs:
    errors.append("сертификат из .p12 не входит в профиль — отредактируйте профиль на developer.apple.com, "
                  "отметьте нужный сертификат и скачайте профиль заново")
for e in errors:
    print(f"Ошибка: {e}", file=sys.stderr)
sys.exit(1 if errors else 0)
PY
    rm -f "$plist"

    ( umask 077
      mkdir -p "$OUT"
      base64 -i "$p12" | tr -d '\n' > "$OUT/IOS_DIST_CERT_P12_BASE64.txt"
      printf '%s' "$pass" > "$OUT/IOS_DIST_CERT_PASSWORD.txt"
      base64 -i "$profile" | tr -d '\n' > "$OUT/IOS_PROVISION_PROFILE_BASE64.txt"
      base64 -i "$p8" | tr -d '\n' > "$OUT/ASC_KEY_P8_BASE64.txt"
      printf '%s' "$key_id" > "$OUT/ASC_KEY_ID.txt" )

    cat <<EOF

Проверка пройдена. Значения секретов лежат в $OUT:
$(cd "$OUT" && ls -1 | sed 's/^/  /')

Добавьте их в GitHub: репозиторий → Settings → Secrets and variables → Actions → New repository secret.
Имя секрета = имя файла без .txt, значение = содержимое файла. Скопировать файл в буфер обмена:
  pbcopy < "$OUT/IOS_DIST_CERT_P12_BASE64.txt"
Отдельно добавьте ASC_ISSUER_ID — Issuer ID со страницы ключей App Store Connect API.
После добавления секретов папку $OUT можно удалить.
EOF
}

case "${1:-}" in
    csr) cmd_csr ;;
    p12) shift; cmd_p12 "$@" ;;
    secrets) shift; cmd_secrets "$@" ;;
    *) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
