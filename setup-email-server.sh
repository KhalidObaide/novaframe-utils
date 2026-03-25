#!/bin/bash
# =============================================================================
# setup-email-server.sh — Full deploy: Mailcow + Email Controller API
# =============================================================================
#
# Usage:
#   bash setup-email-server.sh \
#     --domain mail.novaframe.cloud \
#     --api-key 'SECRET' \
#     --github-token 'ghp_xxx'
#
# Prerequisites:
#   - Fresh Ubuntu 24.04 VPS/VDS
#   - DNS records already pointing to this server:
#       A record:  mail.novaframe.cloud -> <server-ip>
#       MX record: novaframe.cloud -> mail.novaframe.cloud (priority 10)
#   - Ports 22, 25, 80, 443, 587, 993, 995, 4190, 8443 open
#
# This script:
#   1. Installs Docker + Docker Compose
#   2. Clones and configures Mailcow
#   3. Generates mailcow.conf
#   4. Starts Mailcow services
#   5. Clones and deploys the email-controller API
#   6. Configures firewall (ufw)
#   7. Outputs credentials and next steps
#
# If Mailcow is already installed, it will update and restart.
# The email-controller can be reset independently.
#
# Must be run as root.
# =============================================================================

set -euo pipefail

# ---- Defaults ----
DOMAIN=""
API_KEY=""
GITHUB_TOKEN=""
MAILCOW_API_KEY=""
INSTALL_DIR="/opt/mailcow-dockerized"
EC_INSTALL_DIR="/opt/email-controller"
TIMEZONE="UTC"
RESET_MAILCOW=false

# ---- Parse arguments ----
while [[ $# -gt 0 ]]; do
    case "$1" in
        --domain)        DOMAIN="$2";        shift 2 ;;
        --api-key)       API_KEY="$2";       shift 2 ;;
        --github-token)  GITHUB_TOKEN="$2";  shift 2 ;;
        --mailcow-api-key) MAILCOW_API_KEY="$2"; shift 2 ;;
        --timezone)      TIMEZONE="$2";      shift 2 ;;
        --reset)         RESET_MAILCOW=true; shift ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root"; exit 1
fi
if [[ -z "$DOMAIN" ]]; then
    echo "Error: --domain is required (e.g. mail.novaframe.cloud)"; exit 1
fi
if [[ -z "$GITHUB_TOKEN" ]]; then
    echo "Error: --github-token is required (for cloning email-controller repo)"; exit 1
fi
if [[ -z "$API_KEY" ]]; then
    API_KEY=$(openssl rand -hex 32)
    echo "Generated Email Controller API key: $API_KEY"
fi
if [[ -z "$MAILCOW_API_KEY" ]]; then
    MAILCOW_API_KEY=$(openssl rand -hex 32)
    echo "Generated Mailcow API key: $MAILCOW_API_KEY"
fi

SERVER_IP=$(hostname -I | awk '{print $1}')

echo "============================================"
echo " NovaFrame Email Server Full Deploy"
echo "============================================"
echo " Domain:             $DOMAIN"
echo " Server IP:          $SERVER_IP"
echo " Mailcow dir:        $INSTALL_DIR"
echo " Email Controller:   $EC_INSTALL_DIR"
echo " Reset Mailcow:      $RESET_MAILCOW"
echo "============================================"
echo ""

# ===================================================================
# Step 1: System updates
# ===================================================================
echo "[1/8] Updating system..."
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq

# ===================================================================
# Step 2: Install Docker
# ===================================================================
echo "[2/8] Installing Docker..."
if ! command -v docker &>/dev/null; then
    curl -fsSL https://get.docker.com | sh
    systemctl enable --now docker
fi
if ! docker compose version &>/dev/null; then
    apt-get install -y -qq docker-compose-plugin
fi

# ===================================================================
# Step 3: Set hostname and timezone
# ===================================================================
echo "[3/8] Configuring hostname and timezone..."
hostnamectl set-hostname "$DOMAIN"
timedatectl set-timezone "$TIMEZONE"
if ! grep -q "$DOMAIN" /etc/hosts; then
    echo "127.0.0.1 $DOMAIN" >> /etc/hosts
fi

# ===================================================================
# Step 4: Handle reset if requested
# ===================================================================
if [[ "$RESET_MAILCOW" == true ]] && [[ -d "$INSTALL_DIR" ]]; then
    echo "[4/8] Resetting Mailcow..."
    cd "$INSTALL_DIR"
    docker compose down -v 2>/dev/null || true
    cd /
    rm -rf "$INSTALL_DIR"
    echo "  Mailcow data wiped."
else
    echo "[4/8] Skipping reset (not requested or fresh install)"
fi

# ===================================================================
# Step 5: Install/Update Mailcow
# ===================================================================
echo "[5/8] Installing Mailcow..."
if [[ -d "$INSTALL_DIR" ]]; then
    echo "  Mailcow directory exists, updating..."
    cd "$INSTALL_DIR"
    git pull --quiet 2>/dev/null || true
else
    umask 0022
    cd /opt
    git clone https://github.com/mailcow/mailcow-dockerized.git
    cd "$INSTALL_DIR"
fi

# Generate mailcow.conf
if [[ ! -f mailcow.conf ]] || [[ "$RESET_MAILCOW" == true ]]; then
    cat > mailcow.conf <<CONF
MAILCOW_HOSTNAME=${DOMAIN}
MAILCOW_PASS_SCHEME=BLF-CRYPT
DBNAME=mailcow
DBUSER=mailcow
DBPASS=$(openssl rand -hex 16)
DBROOT=$(openssl rand -hex 16)
HTTP_PORT=80
HTTP_BIND=0.0.0.0
HTTPS_PORT=443
HTTPS_BIND=0.0.0.0
SMTP_PORT=25
SMTPS_PORT=465
SUBMISSION_PORT=587
IMAP_PORT=143
IMAPS_PORT=993
POP_PORT=110
POPS_PORT=995
SIEVE_PORT=4190
DOVEADM_PORT=127.0.0.1:19991
SQL_PORT=127.0.0.1:13306
SOLR_PORT=127.0.0.1:18983
REDIS_PORT=127.0.0.1:7654
API_KEY=${MAILCOW_API_KEY}
API_KEY_READ_ONLY=${MAILCOW_API_KEY}
API_ALLOW_FROM=0.0.0.0/0
TZ=${TIMEZONE}
COMPOSE_PROJECT_NAME=mailcowdockerized
SKIP_LETS_ENCRYPT=n
SKIP_CLAMD=n
SKIP_SOGO=n
SKIP_SOLR=y
SKIP_FTS=y
ENABLE_FTSSOLR=n
ALLOW_ADMIN_EMAIL_LOGIN=y
ACL_ANYONE=disallow
MAILDIR_GC_TIME=7200
ADDITIONAL_SAN=
IPV4_NETWORK=172.22.1
IPV6_NETWORK=fd4d:6169:6c63:6f77::/64
LOG_LINES=9999
WATCHDOG_NOTIFY_EMAIL=
WATCHDOG_NOTIFY_BAN=n
WATCHDOG_EXTERNAL_CHECKS=n
WATCHDOG_SUBJECT=Watchdog ALERT
SNAT_TO_SOURCE=
SNAT6_TO_SOURCE=
COMPOSE_HTTP_TIMEOUT=600
DOCKER_COMPOSE_VERSION=native
CONF
    echo "  mailcow.conf generated"
else
    echo "  mailcow.conf exists, updating API key..."
    sed -i "s/^API_KEY=.*/API_KEY=${MAILCOW_API_KEY}/" mailcow.conf
    sed -i "s/^API_KEY_READ_ONLY=.*/API_KEY_READ_ONLY=${MAILCOW_API_KEY}/" mailcow.conf
    # Capture existing key for email-controller
    MAILCOW_API_KEY=$(grep "^API_KEY=" mailcow.conf | head -1 | cut -d= -f2-)
fi

# ===================================================================
# Step 6: Start Mailcow
# ===================================================================
echo "[6/8] Starting Mailcow (may take 5-10 min on first run)..."
docker compose pull --quiet 2>/dev/null || true
docker compose up -d

echo "  Waiting for Mailcow API..."
sleep 30
for i in {1..30}; do
    if curl -sk "https://127.0.0.1/api/v1/get/status/containers" \
        -H "X-API-Key: ${MAILCOW_API_KEY}" 2>/dev/null | grep -q "type"; then
        echo "  Mailcow API is responding!"
        break
    fi
    echo "  Waiting... ($i/30)"
    sleep 10
done

# ===================================================================
# Step 7: Deploy Email Controller
# ===================================================================
echo "[7/8] Deploying Email Controller API..."

DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3 python3-pip python3-venv nginx

AUTH_URL="https://x-access-token:${GITHUB_TOKEN}@github.com/KhalidObaide/email-controller.git"
if [[ -d "$EC_INSTALL_DIR" ]]; then
    echo "  $EC_INSTALL_DIR exists, pulling latest..."
    git -C "$EC_INSTALL_DIR" pull --quiet
else
    git clone --quiet "$AUTH_URL" "$EC_INSTALL_DIR"
fi

# Run the email-controller's own setup
bash "$EC_INSTALL_DIR/setup.sh" \
    --api-key "$API_KEY" \
    --mailcow-api-key "$MAILCOW_API_KEY" \
    --domain "$DOMAIN"

# ===================================================================
# Step 8: Configure firewall
# ===================================================================
echo "[8/8] Configuring firewall..."
if command -v ufw &>/dev/null; then
    ufw --force reset >/dev/null 2>&1
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow 22/tcp     # SSH
    ufw allow 80/tcp     # HTTP (Let's Encrypt + Mailcow)
    ufw allow 443/tcp    # HTTPS (Mailcow webmail + API)
    ufw allow 25/tcp     # SMTP
    ufw allow 465/tcp    # SMTPS
    ufw allow 587/tcp    # Submission
    ufw allow 993/tcp    # IMAPS
    ufw allow 995/tcp    # POP3S
    ufw allow 143/tcp    # IMAP
    ufw allow 110/tcp    # POP3
    ufw allow 4190/tcp   # Sieve
    ufw allow 8443/tcp   # Email Controller API
    ufw --force enable
    echo "  Firewall configured"
fi

# ===================================================================
# Done
# ===================================================================
echo ""
echo "============================================"
echo " SETUP COMPLETE"
echo "============================================"
echo ""
echo " Mailcow:            https://${DOMAIN}"
echo " Mailcow Admin:      admin / moohoo (CHANGE THIS!)"
echo " Mailcow API Key:    ${MAILCOW_API_KEY}"
echo ""
echo " Email Controller:   https://${DOMAIN}:8443"
echo " Controller API Key: ${API_KEY}"
echo ""
echo " MANUAL STEPS REQUIRED:"
echo ""
echo " 1. DNS Records (in Cloudflare):"
echo "    A     ${DOMAIN}             -> ${SERVER_IP}"
echo "    MX    novaframe.cloud       -> ${DOMAIN} (priority 10)"
echo "    TXT   novaframe.cloud       -> v=spf1 a mx ip4:${SERVER_IP} ~all"
echo "    TXT   _dmarc.novaframe.cloud -> v=DMARC1; p=quarantine; rua=mailto:postmaster@novaframe.cloud"
echo ""
echo " 2. Reverse DNS (PTR record):"
echo "    Set PTR for ${SERVER_IP} -> ${DOMAIN}"
echo "    (In your VPS provider's panel)"
echo ""
echo " 3. Change Mailcow admin password at https://${DOMAIN}"
echo ""
echo " 4. Environment variables for NovaFrame portal:"
echo "    (Use the Email Controller, not Mailcow directly)"
echo ""
echo " Test:"
echo "    curl -sk https://${DOMAIN}:8443/health"
echo "    curl -sk -H 'X-API-Key: ${API_KEY}' https://${DOMAIN}:8443/info"
echo ""
echo "============================================"
