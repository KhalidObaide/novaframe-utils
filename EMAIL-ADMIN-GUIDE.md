# NovaFrame Email Server — Admin Guide

## Server Details

| Item | Value |
|------|-------|
| **Server IP** | `158.220.111.45` |
| **SSH Access** | `ssh root@158.220.111.45` |
| **Hostname** | `mail.novaframe.cloud` |
| **OS** | Ubuntu 24.04 |
| **Software** | Mailcow Dockerized + Roundcube |
| **Install Dir** | `/opt/mailcow-dockerized` |

---

## Dashboards & URLs

### Admin Access

| Dashboard | URL | Credentials |
|-----------|-----|-------------|
| **Mailcow Admin** | `https://mail.novaframe.cloud` | `admin` / `moohoo` (**CHANGE THIS**) |
| **Rspamd (Spam Filter)** | `https://mail.novaframe.cloud/rspamd/` | Uses Mailcow admin login |

From Mailcow Admin you can:
- Manage all domains and mailboxes
- View mail queue and logs
- Configure rate limits, spam filters, quarantine
- Manage DKIM keys
- View container health and resource usage

### User Access

| Service | URL | Credentials |
|---------|-----|-------------|
| **Roundcube Webmail** | `https://mail.novaframe.cloud/mail/` | Full email address + mailbox password |
| **SOGo Webmail** (legacy) | `https://mail.novaframe.cloud/SOGo/` | Full email address + mailbox password |

---

## API Access

| Item | Value |
|------|-------|
| **API Base URL** | `https://mail.novaframe.cloud/api/v1` |
| **API Key (read-write)** | `eaafb35282fdd85ba825af8590f5fd008e006ab65586a6478826f773a367ae5a` |
| **API Key (read-only)** | Same as above (should be changed to separate key) |
| **Auth Header** | `X-API-Key: <key>` |

### Useful API endpoints

```bash
# List all domains
curl -s https://mail.novaframe.cloud/api/v1/get/domain/all \
  -H 'X-API-Key: <key>'

# List mailboxes for a domain
curl -s https://mail.novaframe.cloud/api/v1/get/mailbox/all/example.com \
  -H 'X-API-Key: <key>'

# Check container health
curl -s https://mail.novaframe.cloud/api/v1/get/status/containers \
  -H 'X-API-Key: <key>'

# Get DKIM for a domain
curl -s https://mail.novaframe.cloud/api/v1/get/dkim/example.com \
  -H 'X-API-Key: <key>'
```

---

## Database Credentials

### Mailcow MySQL (internal)

| Item | Value |
|------|-------|
| **Host** | `mysql-mailcow` (container) / `127.0.0.1:13306` (from host) |
| **Database** | `mailcow` |
| **User** | `mailcow` |
| **Password** | `Dk4XV4ZImfi6jEgcxaTfOm0vklzB` |
| **Root Password** | `gfDM0NFnBupPEsPqxboIO9LMlLY5` |

### Roundcube MySQL

| Item | Value |
|------|-------|
| **Host** | `mysql-mailcow` (shared MySQL instance) |
| **Database** | `roundcubemail` |
| **User** | `roundcube` |
| **Password** | `roundcube_secret_2026` |

---

## NovaFrame Environment Variables

These must be set in the NovaFrame customer portal (`.env` / Vercel / deployment):

```env
MAILCOW_API_URL=https://mail.novaframe.cloud/api/v1
MAILCOW_API_KEY=eaafb35282fdd85ba825af8590f5fd008e006ab65586a6478826f773a367ae5a
```

---

## Docker Containers

Running 20 containers total. Key ones:

| Container | Purpose |
|-----------|---------|
| `nginx-mailcow` | Reverse proxy, SSL termination |
| `dovecot-mailcow` | IMAP/POP3 server |
| `postfix-mailcow` | SMTP server |
| `mysql-mailcow` | Database |
| `redis-mailcow` | Cache |
| `rspamd-mailcow` | Spam filter |
| `clamd-mailcow` | Antivirus |
| `acme-mailcow` | Let's Encrypt SSL |
| `sogo-mailcow` | SOGo webmail (legacy) |
| `roundcube` | Roundcube webmail (primary) |

### Common Docker commands

```bash
cd /opt/mailcow-dockerized

# View all containers
docker compose ps

# View logs
docker compose logs -f --tail=50              # All
docker compose logs -f postfix-mailcow        # SMTP only
docker compose logs -f dovecot-mailcow        # IMAP only
docker compose logs -f roundcube              # Roundcube

# Restart a specific service
docker compose restart postfix-mailcow

# Restart everything
docker compose down && docker compose up -d

# Update Mailcow
./update.sh
```

---

## Configuration Files

| File | Purpose |
|------|---------|
| `/opt/mailcow-dockerized/mailcow.conf` | Main Mailcow config (ports, API keys, features) |
| `/opt/mailcow-dockerized/docker-compose.override.yml` | Roundcube container definition |
| `/opt/mailcow-dockerized/data/conf/nginx/site.roundcube.custom` | Nginx proxy for Roundcube at `/mail/` |

---

## Email Client Settings (for end users)

### Incoming Mail (IMAP)

| Setting | Value |
|---------|-------|
| Server | `mail.novaframe.cloud` |
| Port | `993` |
| Security | SSL/TLS |
| Username | Full email (e.g. `user@domain.com`) |

### Outgoing Mail (SMTP)

| Setting | Value |
|---------|-------|
| Server | `mail.novaframe.cloud` |
| Port | `587` |
| Security | STARTTLS |
| Username | Full email (e.g. `user@domain.com`) |

---

## DNS Records (per customer domain)

Each customer domain needs these records:

| Type | Name | Value |
|------|------|-------|
| MX | `@` | `mail.novaframe.cloud` (priority 10) |
| TXT | `@` | `v=spf1 a mx include:mail.novaframe.cloud ~all` |
| TXT | `dkim._domainkey` | DKIM public key (from Mailcow API) |
| TXT | `_dmarc` | `v=DMARC1; p=none; rua=mailto:dmarc@<domain>` |

### NovaFrame's own DNS (mail.novaframe.cloud)

| Type | Name | Value |
|------|------|-------|
| A | `mail.novaframe.cloud` | `158.220.111.45` (DNS only, NOT proxied) |
| TXT | `novaframe.cloud` | SPF includes `ip4:158.220.111.45` |
| PTR | `158.220.111.45` | `mail.novaframe.cloud` (set in VPS provider panel) |

**Important:** Do NOT change the MX record for `novaframe.cloud` itself — it uses Spacemail for `@novaframe.cloud` addresses.

---

## Maintenance

### SSL Certificates
- Managed automatically by Mailcow's ACME container (Let's Encrypt)
- Renewals happen automatically every ~60 days
- Check status: `docker compose logs acme-mailcow`

### Backups
- Mailcow data lives in Docker volumes
- Backup the entire `/opt/mailcow-dockerized` directory + Docker volumes
- Mailcow includes a backup script: `./helper-scripts/backup_and_restore.sh backup`

### IP Change Procedure
If the server IP changes:
1. Update `A` record for `mail.novaframe.cloud` in Cloudflare
2. Update PTR/rDNS in VPS provider panel
3. Update SPF TXT record for `novaframe.cloud` with new IP
4. Wait for DNS propagation (~5-30 min)
5. Restart Mailcow: `cd /opt/mailcow-dockerized && docker compose restart`

### Monitoring
- Mailcow Watchdog monitors all containers automatically
- Rspamd dashboard shows spam stats: `https://mail.novaframe.cloud/rspamd/`
- Check container health: `docker compose ps`

---

## Immediate TODO

- [ ] **Change Mailcow admin password** — login at `https://mail.novaframe.cloud` with `admin`/`moohoo` and change it
- [ ] **Change API read-only key** — currently same as read-write key; set a separate one in `mailcow.conf`
- [ ] **Add MAILCOW env vars to production** — `MAILCOW_API_URL` and `MAILCOW_API_KEY` in Vercel/deployment
- [ ] **Create email plans** in admin panel at `/hardware-admin/email-plans`
- [ ] **Set up monitoring alerts** — configure Watchdog email in `mailcow.conf` (`WATCHDOG_NOTIFY_EMAIL`)
