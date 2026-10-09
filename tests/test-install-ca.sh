#!/usr/bin/env bash
# install.sh trusts exactly the certificate whose fingerprint it checked:
# another PEM block in the platform's answer (a TRUSTED CERTIFICATE, which
# curl and OpenSSL also read) never reaches the agent's trusted file, and
# two certificates are refused. Needs openssl.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
g=$ROOT/install.sh
d=$(mktemp -d); trap 'rm -rf "$d"' EXIT
fail() { echo "FAIL: $*"; exit 1; }
mkcert() { openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -keyout "$d/$1.key" -out "$d/$1.pem" -subj "/CN=$1" -days 1 2>/dev/null; }
mkcert real; mkcert evil
fp=$(openssl x509 -in "$d/real.pem" -outform DER | sha256sum | cut -d' ' -f1)

[[ $(sh "$g" --canonical-ca "$d/real.pem" "$d/out.pem") == "$fp" ]] || fail "fingerprint not printed"
[[ $(openssl x509 -in "$d/out.pem" -outform DER | sha256sum | cut -d' ' -f1) == "$fp" ]] || fail "real CA not kept"
echo "ok real CA kept, fingerprint printed"

# The real CA plus an attacker's certificate in a form a plain-CERTIFICATE range skips.
{ cat "$d/real.pem"; sed 's/BEGIN CERTIFICATE/BEGIN TRUSTED CERTIFICATE/; s/END CERTIFICATE/END TRUSTED CERTIFICATE/' "$d/evil.pem"; } > "$d/mixed.pem"
if sh "$g" --canonical-ca "$d/mixed.pem" "$d/out2.pem" >/dev/null 2>&1; then
    [[ $(grep -c BEGIN "$d/out2.pem") == 1 ]] || fail "an extra PEM block reached the trusted file"
fi
echo "ok mixed answer refused or reduced to the checked certificate"

cat "$d/real.pem" "$d/evil.pem" > "$d/two.pem"
if sh "$g" --canonical-ca "$d/two.pem" "$d/out3.pem" >/dev/null 2>&1; then fail "two certificates accepted"; fi
echo "ok two certificates refused"
echo "test-install-ca: all checks passed"
