#!/bin/bash

# Usage:
#   ./storage_transfer_and_setup.sh <server> \
#     --domain storage1.novaframe.cloud \
#     --api-key <key> \
#     --github-token <token> \
#     --minio-root-user <user> \
#     --minio-root-password <password> \
#     --cf-api-token <cloudflare_token>

if [ $# -lt 2 ]; then
  echo "Usage: $0 <server> --domain <domain> --api-key <key> --github-token <token> --minio-root-user <user> --minio-root-password <password> --cf-api-token <cf_token>"
  exit 1
fi

SERVER="$1"
shift

API_KEY=""
GITHUB_TOKEN=""
DOMAIN=""
MINIO_ROOT_USER=""
MINIO_ROOT_PASSWORD=""
CF_API_TOKEN=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --api-key)             API_KEY="$2";             shift 2 ;;
    --github-token)        GITHUB_TOKEN="$2";        shift 2 ;;
    --domain)              DOMAIN="$2";              shift 2 ;;
    --minio-root-user)     MINIO_ROOT_USER="$2";     shift 2 ;;
    --minio-root-password) MINIO_ROOT_PASSWORD="$2"; shift 2 ;;
    --cf-api-token)        CF_API_TOKEN="$2";        shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

for var in API_KEY GITHUB_TOKEN DOMAIN MINIO_ROOT_USER MINIO_ROOT_PASSWORD CF_API_TOKEN; do
  if [[ -z "${!var}" ]]; then
    echo "Error: --${var//_/-} is required"; exit 1
  fi
done

SAFE_DOMAIN=$(printf '%q' "$DOMAIN")
SAFE_API_KEY=$(printf '%q' "$API_KEY")
SAFE_GITHUB_TOKEN=$(printf '%q' "$GITHUB_TOKEN")
SAFE_MINIO_USER=$(printf '%q' "$MINIO_ROOT_USER")
SAFE_MINIO_PASS=$(printf '%q' "$MINIO_ROOT_PASSWORD")
SAFE_CF_TOKEN=$(printf '%q' "$CF_API_TOKEN")

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Transferring setup script to $SERVER..."
scp "$SCRIPT_DIR/storage-controller/setup-storage.sh" root@"$SERVER":/root/ && \
echo "Running setup on remote server..." && \
ssh root@"$SERVER" "bash /root/setup-storage.sh \
  --domain $SAFE_DOMAIN \
  --api-key $SAFE_API_KEY \
  --github-token $SAFE_GITHUB_TOKEN \
  --minio-root-user $SAFE_MINIO_USER \
  --minio-root-password $SAFE_MINIO_PASS \
  --cf-api-token $SAFE_CF_TOKEN"
