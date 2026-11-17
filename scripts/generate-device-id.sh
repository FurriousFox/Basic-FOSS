#!/usr/bin/env bash

set -euo pipefail

if command -v openssl >/dev/null 2>&1; then
  openssl rand -hex 18
elif command -v python3 >/dev/null 2>&1; then
  python3 -c 'import secrets; print(secrets.token_hex(18))'
else
  printf 'This script requires openssl or python3.\n' >&2
  exit 1
fi
