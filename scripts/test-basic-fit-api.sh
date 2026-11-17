#!/usr/bin/env bash

set -euo pipefail

CLIENT_ID="${BASIC_FIT_CLIENT_ID:-q6KqjlQINmjOC86rqt9JdU_i41nhD_Z4DwygpBxGiIs}"
REDIRECT_URI="${BASIC_FIT_REDIRECT_URI:-com.basicfit.bfa:/oauthredirect}"
USER_AGENT="${BASIC_FIT_USER_AGENT:-Basic Fit App/1.79.5.2738 (Android)}"
AUTH_URL="https://login.basic-fit.com/"
TOKEN_URL="https://auth.basic-fit.com/token"
MEMBER_INFO_URL="https://bfa.basic-fit.com/api/member/info"
BFA_VERSION="1.79.5.2738"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'Missing required command: %s\n' "$1" >&2
    exit 1
  }
}

for command in curl openssl python3; do
  require_command "$command"
done

urlencode() {
  python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.stdin.read().strip(), safe=""))'
}

redact_json() {
  python3 - "$1" <<'PY'
import json
import sys

path = sys.argv[1]
try:
    value = json.load(open(path, encoding="utf-8"))
except (OSError, ValueError):
    print(open(path, encoding="utf-8", errors="replace").read()[:2000])
    raise SystemExit

secret_keys = {
    "access_token",
    "refresh_token",
    "token",
    "code",
    "code_verifier",
}

def redact(value):
    if isinstance(value, dict):
        return {
            key: ("<redacted>" if key.lower() in secret_keys else redact(item))
            for key, item in value.items()
        }
    if isinstance(value, list):
        return [redact(item) for item in value]
    return value

print(json.dumps(redact(value), indent=2, sort_keys=True)[:8000])
PY
}

run_request() {
  local name="$1"
  shift
  local headers="$tmp_dir/${name}.headers"
  local body="$tmp_dir/${name}.body"
  local status

  printf '\n=== %s ===\n' "$name"
  status="$(curl --silent --show-error --http2 -D "$headers" -o "$body" -w '%{http_code}' "$@")"
  printf 'HTTP status: %s\n' "$status"
  printf 'Response headers:\n'
  sed -n '1,25p' "$headers"
  printf 'Response body (secrets redacted):\n'
  redact_json "$body"

  if [[ "$status" != 2* ]]; then
    printf 'FAIL: %s returned HTTP %s\n' "$name" "$status" >&2
    return 1
  fi
}

verifier="$(openssl rand -hex 64)"
challenge="$(
  printf '%s' "$verifier" |
    openssl dgst -sha256 -binary |
    openssl base64 -A |
    tr '+/' '-_' |
    tr -d '='
)"

auth_uri="${AUTH_URL}?redirect_uri=$(printf '%s' "$REDIRECT_URI" | urlencode)"
auth_uri+="&client_id=$(printf '%s' "$CLIENT_ID" | urlencode)"
auth_uri+="&response_type=code&app=true"
auth_uri+="&code_challenge=$(printf '%s' "$challenge" | urlencode)"
auth_uri+="&code_challenge_method=S256"

printf 'Basic-Fit endpoint tester\n\n'
printf 'Client ID:    %s\n' "$CLIENT_ID"
printf 'Redirect URI: %s\n' "$REDIRECT_URI"
printf 'User-Agent:   %s\n\n' "$USER_AGENT"
printf 'Opening the authorization URL:\n%s\n\n' "$auth_uri"

if command -v xdg-open >/dev/null 2>&1; then
  xdg-open "$auth_uri" >/dev/null 2>&1 || true
elif command -v open >/dev/null 2>&1; then
  open "$auth_uri" >/dev/null 2>&1 || true
elif command -v cmd.exe >/dev/null 2>&1; then
  cmd.exe /c start "" "$auth_uri" >/dev/null 2>&1 || true
else
  printf 'Open the URL manually in a browser.\n'
fi

printf 'Paste the complete callback URL after login.\n> '
read -r callback_uri

code="$(
  python3 - "$callback_uri" <<'PY'
import sys
import urllib.parse

uri = urllib.parse.urlparse(sys.argv[1])
query = urllib.parse.parse_qs(uri.query)
if "error" in query:
    print(
        f"Authorization failed: {query['error'][0]} "
        f"{query.get('error_description', [''])[0]}",
        file=sys.stderr,
    )
    raise SystemExit(2)
if "code" not in query:
    print("Callback URL does not contain an authorization code.", file=sys.stderr)
    raise SystemExit(2)
print(query["code"][0])
PY
)"

printf '\nAuthorization code received; it will not be printed.\n'

run_request "authorization-code-exchange" \
  --request POST "$TOKEN_URL" \
  --header 'Content-Type: application/x-www-form-urlencoded' \
  --header "User-Agent: $USER_AGENT" \
  --data-urlencode "redirect_uri=$REDIRECT_URI" \
  --data-urlencode "client_id=$CLIENT_ID" \
  --data-urlencode 'grant_type=authorization_code' \
  --data-urlencode "code=$code" \
  --data-urlencode "code_verifier=$verifier"

python3 - "$tmp_dir/authorization-code-exchange.body" "$tmp_dir/tokens.env" <<'PY'
import json
import sys

response = json.load(open(sys.argv[1], encoding="utf-8"))
for key in ("access_token", "refresh_token"):
    value = response.get(key)
    if not isinstance(value, str) or not value:
        raise SystemExit(f"Token response is missing {key}")
with open(sys.argv[2], "w", encoding="utf-8") as output:
    output.write(f"ACCESS_TOKEN={response['access_token']}\n")
    output.write(f"REFRESH_TOKEN={response['refresh_token']}\n")
PY

# shellcheck disable=SC1091
source "$tmp_dir/tokens.env"

run_request "member-info" \
  --request GET "$MEMBER_INFO_URL" \
  --header "Authorization: Bearer $ACCESS_TOKEN" \
  --header "Bfa-Version: $BFA_VERSION" \
  --header "User-Agent: $USER_AGENT" \
  --header "Client-Id: $CLIENT_ID" \
  --header "Redirect-Uri: $REDIRECT_URI"

printf '\nMember-info fields needed by the QR generator:\n'
python3 - "$tmp_dir/member-info.body" <<'PY'
import json
import sys

try:
    member = json.load(open(sys.argv[1], encoding="utf-8")).get("member", {})
except (OSError, ValueError):
    print("Unable to parse the member-info response.")
    raise SystemExit

for field in ("deviceId", "cardnumber"):
    value = member.get(field)
    print(f"  {field}: {'present' if value else 'missing'}")
PY

printf '\nThe refresh request rotates the refresh token. Test it now? [y/N] '
read -r refresh_choice
if [[ "$refresh_choice" =~ ^[Yy]$ ]]; then
  run_request "refresh-token" \
    --request POST "$TOKEN_URL" \
    --header 'Content-Type: application/x-www-form-urlencoded' \
    --header 'Accept: application/json' \
    --header "User-Agent: $USER_AGENT" \
    --data-urlencode "refresh_token=$REFRESH_TOKEN" \
    --data-urlencode 'grant_type=refresh_token' \
    --data-urlencode "redirect_uri=$REDIRECT_URI" \
    --data-urlencode "client_id=$CLIENT_ID"
fi

printf '\nAll selected endpoint checks completed.\n'
