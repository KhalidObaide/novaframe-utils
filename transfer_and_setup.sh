#!/bin/bash

# Usage: ./transfer_and_setup.sh <server> --domain <domain> --api-key <key> --github-token <token>

if [ $# -lt 7 ]; then
  echo "Usage: $0 <server> --domain <domain> --api-key <key> --github-token <token>"
  exit 1
fi

SERVER="$1"
shift

API_KEY=""
GITHUB_TOKEN=""
DOMAIN=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --api-key)
      API_KEY="$2"
      shift 2
      ;;
    --github-token)
      GITHUB_TOKEN="$2"
      shift 2
      ;;
    --domain)
      DOMAIN="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

if [[ -z "$API_KEY" ]]; then
  echo "Error: --api-key is required"
  exit 1
fi

if [[ -z "$GITHUB_TOKEN" ]]; then
  echo "Error: --github-token is required"
  exit 1
fi

if [[ -z "$DOMAIN" ]]; then
  echo "Error: --domain is required (e.g. vds1.novaframe.cloud)"
  exit 1
fi

echo "Transferring setup script to $SERVER..."
# Copy the script and run it on the remote server
# Use printf '%q' to safely escape any special characters in the values
# before they are interpreted by the remote shell.
SAFE_DOMAIN=$(printf '%q' "$DOMAIN")
SAFE_API_KEY=$(printf '%q' "$API_KEY")
SAFE_GITHUB_TOKEN=$(printf '%q' "$GITHUB_TOKEN")
scp setup-vds.sh root@"$SERVER":/root/ && \
echo "Running setup on remote server..." && \
ssh root@"$SERVER" "bash /root/setup-vds.sh --domain $SAFE_DOMAIN --api-key $SAFE_API_KEY --github-token $SAFE_GITHUB_TOKEN"
