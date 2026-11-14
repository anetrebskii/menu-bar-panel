#!/bin/zsh
set -euo pipefail
if (( $# < 3 )); then
    print -u2 "usage: $0 <notary key id> <issuer id> <AuthKey .p8 path> [keychain]"
    exit 1
fi
KEY_ID=$1 ISSUER=$2 KEY_PATH=$3 KEYCHAIN=${4:-login.keychain-db}
REPO=${REPO:-anetrebskii/menu-bar-panel}
SSL=/usr/bin/openssl
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
EXPORT_PW=$($SSL rand -hex 16)
P12_PW=$($SSL rand -hex 16)
security export -k "$KEYCHAIN" -t identities -f pkcs12 -P "$EXPORT_PW" -o "$TMP/all.p12"
$SSL pkcs12 -in "$TMP/all.p12" -passin "pass:$EXPORT_PW" -nodes -out "$TMP/all.pem" 2>/dev/null
python3 -I - "$TMP" <<'PY'
import re, sys
d = sys.argv[1]
text = open(f"{d}/all.pem").read()
blocks = re.findall(r"(Bag Attributes.*?-----END [A-Z ]+-----)", text, re.S)
def key_id(b):
    m = re.search(r"localKeyID: ([0-9A-F ]+)", b)
    return m and m.group(1).strip()
certs = [b for b in blocks if "BEGIN CERTIFICATE" in b and "Developer ID Application" in b.split("-----BEGIN")[0]]
if len(certs) != 1:
    sys.exit(f"expected one Developer ID Application identity, found {len(certs)}")
kid = key_id(certs[0])
keys = [b for b in blocks if "PRIVATE KEY" in b and key_id(b) == kid]
if len(keys) != 1:
    sys.exit("private key for the Developer ID Application certificate not found")
pem = lambda b: b[b.index("-----BEGIN"):] + "\n"
open(f"{d}/cert.pem", "w").write(pem(certs[0]))
open(f"{d}/key.pem", "w").write(pem(keys[0]))
print(re.search(r"subject=(.*)", certs[0]).group(1).strip())
PY
$SSL pkcs12 -export -in "$TMP/cert.pem" -inkey "$TMP/key.pem" -passout "pass:$P12_PW" -out "$TMP/devid.p12"
base64 -i "$TMP/devid.p12" | gh secret set DEVELOPER_ID_P12 -R "$REPO"
print -n "$P12_PW" | gh secret set DEVELOPER_ID_P12_PASSWORD -R "$REPO"
gh secret set NOTARY_KEY_P8 -R "$REPO" < "$KEY_PATH"
print -n "$KEY_ID" | gh secret set NOTARY_KEY_ID -R "$REPO"
print -n "$ISSUER" | gh secret set NOTARY_ISSUER_ID -R "$REPO"
gh secret list -R "$REPO"
