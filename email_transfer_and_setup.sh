#!/bin/bash

# Usage:
#   ./email_transfer_and_setup.sh <server> \
#     --domain mail.novaframe.cloud \
#     --api-key <key>
#
# Example:
#   ./email_transfer_and_setup.sh root@158.220.111.45 \
#     --domain mail.novaframe.cloud \
#     --api-key $(openssl rand -hex 32)

if [ $# -lt 2 ]; then
  echo "Usage: $0 <server> --domain <domain> [--api-key <key>]"
  exit 1
fi

SERVER="$1"
shift

DOMAIN=""
API_KEY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain)   DOMAIN="$2";   shift 2 ;;
    --api-key)  API_KEY="$2";  shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

if [[ -z "$DOMAIN" ]]; then
  echo "Error: --domain is required (e.g. mail.novaframe.cloud)"
  exit 1
fi

# Generate API key if not provided
if [[ -z "$API_KEY" ]]; then
  API_KEY=$(openssl rand -hex 32)
  echo "Generated API key: $API_KEY"
fi

SAFE_DOMAIN=$(printf '%q' "$DOMAIN")
SAFE_API_KEY=$(printf '%q' "$API_KEY")

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Transferring setup script to $SERVER..."
scp "$SCRIPT_DIR/setup-email.sh" root@"$SERVER":/root/ && \
echo "Running setup on remote server..." && \
ssh root@"$SERVER" "bash /root/setup-email.sh \
  --domain $SAFE_DOMAIN \
  --api-key $SAFE_API_KEY"
