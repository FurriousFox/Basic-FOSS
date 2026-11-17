#!/usr/bin/env bash

set -euo pipefail

CLIENT_ID="${BASIC_FIT_CLIENT_ID:-q6KqjlQINmjOC86rqt9JdU_i41nhD_Z4DwygpBxGiIs}"
REDIRECT_URI="${BASIC_FIT_REDIRECT_URI:-com.basicfit.bfa:/oauthredirect}"
USER_AGENT="${BASIC_FIT_USER_AGENT:-Basic Fit App/1.79.5.2738 (Android)}"
BFA_VERSION="1.79.5.2738"
DEVICE_INFO_URL="https://bfa.basic-fit.com/api/member/deviceInfo"
MEMBER_INFO_URL="https://bfa.basic-fit.com/api/member/info"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

if ! command -v curl >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1; then
  printf 'This script requires curl and python3.\n' >&2
  exit 1
fi

if [[ -n "${BASIC_FIT_ACCESS_TOKEN:-}" ]]; then
  access_token="$BASIC_FIT_ACCESS_TOKEN"
else
  read -r -s -p 'Basic-Fit access token: ' access_token
  printf '\n'
fi

if [[ -z "$access_token" ]]; then
  printf 'An access token is required.\n' >&2
  exit 1
fi

read -r -p 'New device ID [generate securely]: ' device_id
if [[ -z "$device_id" ]]; then
  if [[ -x "$(dirname "$0")/generate-device-id.sh" ]]; then
    device_id="$("$(dirname "$0")/generate-device-id.sh")"
  else
    device_id="$(python3 -c 'import secrets; print(secrets.token_hex(18))')"
  fi
fi

if [[ ! "$device_id" =~ ^[0-9a-f]{36}$ ]]; then
  printf 'Device ID must contain exactly 36 lowercase hexadecimal characters.\n' >&2
  exit 1
fi

read -r -p 'Device description [Basic-FOSS]: ' device_description
device_description="${device_description:-Basic-FOSS}"

python3 - "$tmp_dir/request.json" "$device_id" "$device_description" <<'PY'
import json
import sys

with open(sys.argv[1], "w", encoding="utf-8") as output:
    json.dump(
        {
            "deviceId": sys.argv[2],
            "deviceDescription": sys.argv[3],
        },
        output,
    )
PY

printf '\nSetting device ID %s...\n' "$device_id"
status_code="$(
  curl --silent --show-error --http2 \
    --request POST "$DEVICE_INFO_URL" \
    --header "Authorization: Bearer $access_token" \
    --header "Bfa-Version: $BFA_VERSION" \
    --header "User-Agent: $USER_AGENT" \
    --header "Client-Id: $CLIENT_ID" \
    --header "Redirect-Uri: $REDIRECT_URI" \
    --header 'Content-Type: application/json' \
    --data-binary "@$tmp_dir/request.json" \
    --output "$tmp_dir/response.body" \
    --dump-header "$tmp_dir/response.headers" \
    --write-out '%{http_code}'
)"

printf 'HTTP status: %s\n' "$status_code"
sed -n '1,25p' "$tmp_dir/response.headers"

if [[ "$status_code" != "204" && "$status_code" != "424" ]]; then
  printf 'Response body:\n'
  sed -n '1,100p' "$tmp_dir/response.body"
  printf 'The device ID was not confirmed as set.\n' >&2
  exit 1
fi

if [[ "$status_code" == "424" ]]; then
  printf 'Server returned 424; the documented behavior allows a non-empty ID to still be applied.\n'
else
  printf 'Device ID update accepted.\n'
fi
printf 'Fetching member info to verify the stored device ID...\n'

curl --silent --show-error --http2 \
  --request GET "$MEMBER_INFO_URL" \
  --header "Authorization: Bearer $access_token" \
  --header "Bfa-Version: $BFA_VERSION" \
  --header "User-Agent: $USER_AGENT" \
  --header "Client-Id: $CLIENT_ID" \
  --header "Redirect-Uri: $REDIRECT_URI" \
  --output "$tmp_dir/member-info.body" \
  --dump-header "$tmp_dir/member-info.headers" \
  --write-out 'Member-info HTTP status: %{http_code}\n'

python3 - "$tmp_dir/member-info.body" "$device_id" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as input_file:
        member = json.load(input_file).get("member", {})
except (OSError, ValueError) as error:
    raise SystemExit(f"Could not parse member info: {error}")

actual = member.get("deviceId")
if actual != sys.argv[2]:
    raise SystemExit("Member info did not return the requested device ID.")
print("Verified: member info contains the new device ID.")
PY
