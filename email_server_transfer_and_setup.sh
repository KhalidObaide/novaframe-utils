#!/bin/bash
# =============================================================================
# email_server_transfer_and_setup.sh — Remote deploy: Mailcow + Email Controller
# =============================================================================
#
# Usage:
#   ./email_server_transfer_and_setup.sh root@158.220.111.45 \
#     --domain mail.novaframe.cloud \
#     --api-key 'SECRET' \
#     --github-token 'ghp_xxx'
#
# Flags:
#   --reset    Wipe existing Mailcow data and start fresh

if [ $# -lt 2 ]; then
    echo "Usage: $0 <server> --domain <domain> --github-token <token> [--api-key <key>] [--reset]"
    exit 1
fi

SERVER="$1"
shift

DOMAIN=""
API_KEY=""
GITHUB_TOKEN=""
EXTRA_ARGS=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --domain)       DOMAIN="$2";       shift 2 ;;
        --api-key)      API_KEY="$2";      shift 2 ;;
        --github-token) GITHUB_TOKEN="$2"; shift 2 ;;
        --reset)        EXTRA_ARGS="$EXTRA_ARGS --reset"; shift ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

if [[ -z "$DOMAIN" ]]; then
    echo "Error: --domain is required (e.g. mail.novaframe.cloud)"
    exit 1
fi
if [[ -z "$GITHUB_TOKEN" ]]; then
    echo "Error: --github-token is required"
    exit 1
fi
if [[ -z "$API_KEY" ]]; then
    API_KEY=$(openssl rand -hex 32)
    echo "Generated API key: $API_KEY"
fi

SAFE_DOMAIN=$(printf '%q' "$DOMAIN")
SAFE_API_KEY=$(printf '%q' "$API_KEY")
SAFE_GITHUB_TOKEN=$(printf '%q' "$GITHUB_TOKEN")

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Transferring setup script to $SERVER..."
scp "$SCRIPT_DIR/setup-email-server.sh" "$SERVER":/root/ && \
echo "Running setup on remote server..." && \
ssh "$SERVER" "bash /root/setup-email-server.sh \
    --domain $SAFE_DOMAIN \
    --api-key $SAFE_API_KEY \
    --github-token $SAFE_GITHUB_TOKEN \
    $EXTRA_ARGS"
