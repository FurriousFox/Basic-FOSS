#!/usr/bin/env bash

set -euo pipefail

CLIENT_ID="${BASIC_FIT_CLIENT_ID:-q6KqjlQINmjOC86rqt9JdU_i41nhD_Z4DwygpBxGiIs}"
REDIRECT_URI="${BASIC_FIT_REDIRECT_URI:-com.basicfit.bfa:/oauthredirect}"
AUTH_URL="https://login.basic-fit.com/"
TOKEN_URL="https://auth.basic-fit.com/token"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

if ! command -v openssl >/dev/null 2>&1 ||
  ! command -v curl >/dev/null 2>&1 ||
  ! command -v python3 >/dev/null 2>&1; then
  printf 'This script requires openssl, curl, and python3.\n' >&2
  exit 1
fi

verifier="$(openssl rand -hex 64)"
challenge="$(
  printf '%s' "$verifier" |
    openssl dgst -sha256 -binary |
    openssl base64 -A |
    tr '+/' '-_' |
    tr -d '='
)"

auth_uri="${AUTH_URL}?redirect_uri=$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.stdin.read().strip(), safe=""))' <<<"$REDIRECT_URI")"
auth_uri+="&client_id=$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.stdin.read().strip(), safe=""))' <<<"$CLIENT_ID")"
auth_uri+="&response_type=code&app=true"
auth_uri+="&code_challenge=$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.stdin.read().strip(), safe=""))' <<<"$challenge")"
auth_uri+="&code_challenge_method=S256"

printf 'Basic-Fit PKCE diagnostic\n\n'
printf 'Client ID:    %s\n' "$CLIENT_ID"
printf 'Redirect URI: %s\n' "$REDIRECT_URI"
printf 'Verifier:     %s\n' "$verifier"
printf 'Challenge:    %s\n\n' "$challenge"
printf 'The verifier/challenge pair above is temporary and will be discarded.\n\n'
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

printf '\nAfter completing login, paste the complete callback URL.\n'
printf 'It should start with %s and contain ?code=...\n' "$REDIRECT_URI"
read -r -p '> ' callback_uri

code="$(
  python3 - "$callback_uri" <<'PY'
import sys
import urllib.parse

uri = urllib.parse.urlparse(sys.argv[1])
query = urllib.parse.parse_qs(uri.query)
if "error" in query:
    print(f"AUTH_ERROR:{query['error'][0]}", file=sys.stderr)
    if "error_description" in query:
        print(query["error_description"][0], file=sys.stderr)
    raise SystemExit(2)
if "code" not in query:
    print("The callback URL does not contain an authorization code.", file=sys.stderr)
    raise SystemExit(2)
print(query["code"][0])
PY
)"

printf '\nThe authorization code was received. It will not be printed.\n'
printf 'Choose the token-exchange User-Agent:\n'
printf '  1) Match the Dart app (Basic-Fit app User-Agent)\n'
printf '  2) No explicit User-Agent\n'
printf '  3) curl default User-Agent\n'
printf '  4) Custom User-Agent\n'
read -r -p 'Choice [1]: ' user_agent_choice
user_agent_choice="${user_agent_choice:-1}"

curl_args=(
  -sS
  -D "$tmp_dir/headers"
  -o "$tmp_dir/body"
  -w '%{http_code}'
  -X POST "$TOKEN_URL"
  -H 'Content-Type: application/x-www-form-urlencoded'
  --data-urlencode "redirect_uri=$REDIRECT_URI"
  --data-urlencode "client_id=$CLIENT_ID"
  --data-urlencode 'grant_type=authorization_code'
  --data-urlencode "code=$code"
  --data-urlencode "code_verifier=$verifier"
)

case "$user_agent_choice" in
  1)
    curl_args+=(-H 'User-Agent: Basic Fit App/1.79.5.2738 (Android)')
    user_agent_description='Basic-Fit app User-Agent (Dart app)'
    ;;
  2)
    curl_args+=(-H 'User-Agent:')
    user_agent_description='no explicit User-Agent'
    ;;
  3)
    user_agent_description='curl default User-Agent'
    ;;
  4)
    read -r -p 'User-Agent: ' custom_user_agent
    curl_args+=(-H "User-Agent: $custom_user_agent")
    user_agent_description="$custom_user_agent"
    ;;
  *)
    printf 'Invalid choice.\n' >&2
    exit 1
    ;;
esac

printf '\nExchanging the code with %s...\n' "$user_agent_description"
status_code="$(curl "${curl_args[@]}")"

printf '\nHTTP status: %s\n' "$status_code"
printf '%s\n' 'Response headers:'
sed -n '1,30p' "$tmp_dir/headers"
printf '%s\n' 'Response body:'
cat "$tmp_dir/body"
printf '\n'

if [[ "$status_code" == "200" ]]; then
  printf 'PKCE exchange succeeded with this User-Agent.\n'
else
  printf 'PKCE exchange failed with this User-Agent.\n'
fi
