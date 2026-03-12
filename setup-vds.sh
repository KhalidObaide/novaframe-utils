#!/bin/bash
# =============================================================================
# setup-vds.sh — One-command deploy for a fresh VDS
# =============================================================================
#
# Usage:
#   bash setup-vds.sh --domain vds1.novaframe.cloud --api-key 'SECRET' --github-token 'ghp_xxx' [--influx-token 'TOKEN']
#
# Prerequisites:
#   - Fresh Ubuntu 24.04 VDS
#   - DNS A record for --domain already pointing to this server's IP
#
# This script:
#   1. Sets up LXD, bridge networking, IP forwarding, iptables
#   2. Installs Docker + InfluxDB (container metrics storage)
#   3. Clones the hardware-controller repo from GitHub
#   4. Installs Python deps in a venv
#   5. Obtains a Let's Encrypt SSL certificate via certbot
#   6. Configures nginx as an HTTPS reverse proxy (API + WebSocket console)
#   7. Creates and starts systemd services
#
# After running this, log out. Manage everything via the HTTPS API.
# Must be run as root.
# =============================================================================

set -euo pipefail

# ---- Defaults ----
INTERFACE="eth0"
BRIDGE_NAME="lxdbr0"
BRIDGE_SUBNET="10.10.10.1/24"
BRIDGE_IPV6="fd42::1/64"
INSTALL_DIR="/opt/hardware-controller"
API_KEY=""
GITHUB_TOKEN=""
DOMAIN=""
API_PORT=5000
INFLUX_TOKEN=""

# ---- Parse arguments ----
while [[ $# -gt 0 ]]; do
    case "$1" in
        --api-key)       API_KEY="$2";       shift 2 ;;
        --github-token)  GITHUB_TOKEN="$2";  shift 2 ;;
        --domain)        DOMAIN="$2";        shift 2 ;;
        --interface)     INTERFACE="$2";     shift 2 ;;
        --influx-token)  INFLUX_TOKEN="$2";  shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Generate a random InfluxDB token if not provided
if [[ -z "$INFLUX_TOKEN" ]]; then
    INFLUX_TOKEN=$(openssl rand -hex 32)
fi

if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root"; exit 1
fi
if [[ -z "$API_KEY" ]]; then
    echo "Error: --api-key is required"; exit 1
fi
if [[ -z "$GITHUB_TOKEN" ]]; then
    echo "Error: --github-token is required (GitHub personal access token)"; exit 1
fi
if [[ -z "$DOMAIN" ]]; then
    echo "Error: --domain is required (e.g. vds1.novaframe.cloud)"; exit 1
fi

MAIN_IP=$(hostname -I | awk '{print $1}')

echo "============================================"
echo "  VDS Full Deploy"
echo "============================================"
echo "  Domain:       $DOMAIN"
echo "  Main IP:      $MAIN_IP"
echo "  Interface:    $INTERFACE"
echo "  Bridge:       $BRIDGE_NAME ($BRIDGE_SUBNET)"
echo "  Install dir:  $INSTALL_DIR"
echo "  API:          https://$DOMAIN"
echo "============================================"
echo ""

# ===================================================================
# 1. Update system
# ===================================================================
echo "[1/14] Updating system packages..."
apt-get update -qq
apt-get upgrade -y -qq

# ===================================================================
# 2. Install system dependencies
# ===================================================================
echo "[2/14] Installing system dependencies..."
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    iptables-persistent \
    python3 \
    python3-pip \
    python3-venv \
    nginx \
    certbot \
    git \
    snapd \
    zfsutils-linux \
    ca-certificates \
    curl

# ===================================================================
# 2b. Install Docker (for InfluxDB)
# ===================================================================
echo "[2b/14] Installing Docker..."
if ! command -v docker &>/dev/null; then
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
        > /etc/apt/sources.list.d/docker.list
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
    systemctl enable docker
    systemctl start docker
else
    echo "  Docker already installed"
fi

# ===================================================================
# 3. Install LXD
# ===================================================================
echo "[3/14] Installing LXD..."
snap install lxd 2>/dev/null || echo "  LXD already installed"
lxd waitready --timeout=30

# ===================================================================
# 4. Initialize LXD
# ===================================================================
echo "[4/14] Initializing LXD with ZFS storage..."

# Calculate available disk space and reserve 10GB for VDS operations
AVAIL_GB=$(df / --output=avail -BG | tail -n1 | tr -d 'G')
REQUIRED_HEADROOM=10
ZFS_SIZE_GB=$((AVAIL_GB - REQUIRED_HEADROOM))

# Ensure we have at least 20GB for ZFS
if [[ $ZFS_SIZE_GB -lt 20 ]]; then
    echo "Error: Not enough disk space. Need at least 30GB total (20GB for ZFS + 10GB headroom)"
    exit 1
fi

echo "  Available disk: ${AVAIL_GB}GB"
echo "  ZFS pool size: ${ZFS_SIZE_GB}GB (${REQUIRED_HEADROOM}GB reserved for VDS operations)"

cat <<EOF | lxd init --preseed
networks:
- config:
    ipv4.address: ${BRIDGE_SUBNET}
    ipv4.nat: "false"
    ipv6.address: ${BRIDGE_IPV6}
  name: ${BRIDGE_NAME}
  type: bridge
storage_pools:
- config:
    size: ${ZFS_SIZE_GB}GB
  name: default
  driver: zfs
profiles:
- devices:
    eth0:
      name: eth0
      network: ${BRIDGE_NAME}
      type: nic
    root:
      path: /
      pool: default
      type: disk
  name: default
EOF

# ===================================================================
# 5. Enable IP forwarding
# ===================================================================
echo "[5/14] Enabling IP forwarding..."
cat > /etc/sysctl.d/99-ip-forward.conf <<EOF
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.ipv6.conf.${INTERFACE}.proxy_ndp = 1
EOF
sysctl -p /etc/sysctl.d/99-ip-forward.conf

# ===================================================================
# 6. Bind host sshd to main IP only
# ===================================================================
echo "[6/14] Binding host sshd to $MAIN_IP only..."
echo "ListenAddress $MAIN_IP" > /etc/ssh/sshd_config.d/99-listen-main-ip.conf
# Ubuntu 24.04 uses socket activation — override ssh.socket too
mkdir -p /etc/systemd/system/ssh.socket.d
cat > /etc/systemd/system/ssh.socket.d/override.conf <<SSHEOF
[Socket]
ListenStream=
ListenStream=${MAIN_IP}:22
SSHEOF
systemctl daemon-reload
systemctl restart ssh.socket
systemctl restart ssh

# ===================================================================
# 7. Save base iptables
# ===================================================================
echo "[7/14] Setting up iptables rules..."

# Fallback MASQUERADE — gives containers internet during provisioning
# (specific SNAT rules for public IPs are inserted before this)
iptables -t nat -C POSTROUTING -s 10.10.10.0/24 ! -d 10.10.10.0/24 -o ${INTERFACE} -j MASQUERADE 2>/dev/null \
  || iptables -t nat -A POSTROUTING -s 10.10.10.0/24 ! -d 10.10.10.0/24 -o ${INTERFACE} -j MASQUERADE

iptables-save > /etc/iptables/rules.v4
ip6tables-save > /etc/iptables/rules.v6

# ===================================================================
# 7. Clone the hardware-controller repo
# ===================================================================
echo "[8/14] Cloning hardware-controller..."
AUTH_URL="https://x-access-token:${GITHUB_TOKEN}@github.com/KhalidObaide/hardware-controller.git"
if [[ -d "$INSTALL_DIR" ]]; then
    echo "  $INSTALL_DIR already exists, pulling latest..."
    git -C "$INSTALL_DIR" pull --quiet
else
    git clone --quiet "$AUTH_URL" "$INSTALL_DIR"
fi

# ===================================================================
# 8. Install Python dependencies
# ===================================================================
echo "[9/14] Installing Python dependencies..."
python3 -m venv "$INSTALL_DIR/venv"
"$INSTALL_DIR/venv/bin/pip" install --quiet -r "$INSTALL_DIR/requirements.txt"

# ===================================================================
# 9. Start InfluxDB (metrics storage)
# ===================================================================
echo "[10/14] Starting InfluxDB for container metrics..."
INFLUXDB_TOKEN="$INFLUX_TOKEN" docker compose -f "$INSTALL_DIR/docker-compose.yml" up -d
echo "  InfluxDB running on 127.0.0.1:8086"

# ===================================================================
# 10. Set API key
# ===================================================================
echo "[11/14] Configuring API key..."
sed -i "s|CHANGE-ME-TO-A-SECURE-KEY|${API_KEY}|" "$INSTALL_DIR/config.py"

# ===================================================================
# 10. Obtain Let's Encrypt SSL certificate
# ===================================================================
echo "[12/14] Obtaining Let's Encrypt SSL certificate for $DOMAIN..."

# Stop nginx so certbot can bind to port 80 for HTTP-01 challenge
systemctl stop nginx

certbot certonly \
    --standalone \
    -d "$DOMAIN" \
    --non-interactive --agree-tos --register-unsafely-without-email

# ===================================================================
# 12. Configure nginx + systemd
# ===================================================================
echo "[13/14] Configuring nginx and systemd services..."

SSL_CERT="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
SSL_KEY="/etc/letsencrypt/live/$DOMAIN/privkey.pem"

ln -sf /etc/nginx/sites-available/hardware-controller /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
systemctl enable nginx

cat > /etc/nginx/sites-available/hardware-controller <<NGINXEOF
server {
    listen 443 ssl;
    server_name $DOMAIN;

    ssl_certificate     $SSL_CERT;
    ssl_certificate_key $SSL_KEY;
    ssl_protocols       TLSv1.2 TLSv1.3;

    # WebSocket console — proxied to local ws_console.py
    location /ws-console {
        proxy_pass http://127.0.0.1:5001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }

    # API — proxied to gunicorn
    location / {
        proxy_pass http://127.0.0.1:${API_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}

server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}
NGINXEOF

nginx -t
systemctl restart nginx

# Symlink certs into install dir so config.py can find them (for direct SSL fallback)
mkdir -p "$INSTALL_DIR/ssl"
ln -sf "$SSL_CERT" "$INSTALL_DIR/ssl/cert.pem"
ln -sf "$SSL_KEY"  "$INSTALL_DIR/ssl/key.pem"

# systemd — gunicorn (binds to localhost only, nginx handles SSL)
cat > /etc/systemd/system/hardware-controller.service <<EOF
[Unit]
Description=Hardware Controller API
After=network.target snap.lxd.daemon.service docker.service
Requires=docker.service

[Service]
Type=simple
WorkingDirectory=${INSTALL_DIR}
Environment=INFLUXDB_TOKEN=${INFLUX_TOKEN}
ExecStart=${INSTALL_DIR}/venv/bin/gunicorn -w 2 -b 127.0.0.1:${API_PORT} app:app
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# systemd — WebSocket console server (no SSL, localhost only — nginx proxies)
cat > /etc/systemd/system/hardware-console.service <<EOF
[Unit]
Description=Hardware Controller WebSocket Console
After=network.target snap.lxd.daemon.service hardware-controller.service

[Service]
Type=simple
WorkingDirectory=${INSTALL_DIR}
ExecStart=${INSTALL_DIR}/venv/bin/python ${INSTALL_DIR}/ws_console.py --no-ssl --bind 127.0.0.1
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

echo "[14/14] Starting services..."
systemctl daemon-reload
systemctl enable hardware-controller hardware-console
systemctl start hardware-controller
systemctl start hardware-console

# ===================================================================
# Done
# ===================================================================
echo ""
echo "============================================"
echo "  Deploy Complete!"
echo "============================================"
echo "  LXD:        $(lxd --version)"
echo "  Bridge:     $(ip addr show $BRIDGE_NAME 2>/dev/null | grep 'inet ' | awk '{print $2}' || echo 'pending')"
echo "  InfluxDB:   $(docker ps --filter name=hc-influxdb --format '{{.Status}}' 2>/dev/null || echo 'check manually')"
echo ""
echo "  Domain:     $DOMAIN"
echo "  API:        https://$DOMAIN"
echo "  Console WS: wss://$DOMAIN/ws-console"
echo "  Auth:       X-API-Key header"
echo "  SSL:        Let's Encrypt (auto-renews)"
echo "  Metrics:    InfluxDB on 127.0.0.1:8086 (30-day retention)"
echo ""
echo "  Test:"
echo "    curl https://$DOMAIN/health"
echo "    curl -H 'X-API-Key: $API_KEY' https://$DOMAIN/info"
echo ""
echo "  Logs:"
echo "    journalctl -u hardware-controller -f"
echo "    journalctl -u hardware-console -f"
echo "    docker logs hc-influxdb"
echo "============================================"
