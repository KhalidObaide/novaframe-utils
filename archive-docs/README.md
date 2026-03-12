# RedCloud — VDS Container Hosting

Virtualize a VDS into isolated LXD containers, each with its own public IP (like AWS Elastic IPs).

## Architecture

```
Internet
    │
    ▼
┌─────────────────────────────────────────────┐
│  VDS Host (eth0)                            │
│                                             │
│  ┌─────────────────────────────────┐        │
│  │  lxdbr0 (10.10.10.1/24)        │        │
│  │                                 │        │
│  │  web1:  10.10.10.101            │        │
│  │    ↔ Public: 157.173.122.74     │        │
│  │                                 │        │
│  │  web2:  10.10.10.102            │        │
│  │    ↔ Public: 157.173.122.75     │        │
│  └─────────────────────────────────┘        │
│                                             │
│  1:1 NAT (iptables DNAT/SNAT)              │
└─────────────────────────────────────────────┘
```

Each container gets a private IP on the internal bridge. Public IPs are mapped via 1:1 NAT — all inbound traffic to the public IP is forwarded to the container, and all outbound traffic from the container appears to come from its public IP.

## Prerequisites

- A VDS running **Ubuntu 24.04**
- Additional public IPs purchased and assigned to the VDS via the data center control panel
- Root SSH access to the VDS

## Quick Start

### 1. Set up the VDS (run once on a fresh server)

```bash
# Copy files to the server
scp setup-vds.sh root@<VDS_IP>:/root/

# SSH in and run setup
ssh root@<VDS_IP>
bash setup-vds.sh
```

### 2. Create containers

```bash
# Create with auto-assigned private IP (starts from 10.10.10.101)
python3 create_container.py -n web1 -p 'MySecurePass123'

# Create another (auto-assigns 10.10.10.102)
python3 create_container.py -n web2 -p 'AnotherPass456'

# Or specify a private IP manually
python3 create_container.py -n db1 --ip 10.10.10.200 -p 'DbPass789'

# Use a different image
python3 create_container.py -n legacy --image ubuntu:22.04 -p 'LegacyPass'
```

Each container automatically gets:
- `openssh-server` installed and running on port 22
- Root password set to the value of `--password`
- `PermitRootLogin` and `PasswordAuthentication` enabled

### 3. Assign public IPs

```bash
# Assign IPv4
python3 assign_public_ip.py -c web1 -i 157.173.122.74

# Assign IPv4 + IPv6
python3 assign_public_ip.py -c web2 -i 157.173.122.75 --ipv6 2a02:c207:2310:8895::102
```

### 4. Verify & SSH in

```bash
# Check the container sees its public IP
lxc exec web1 -- curl -s ifconfig.me
# → 157.173.122.74

# Ping from outside
ping 157.173.122.74

# SSH directly into the container via its public IP
ssh root@157.173.122.74

# Or access via the host
lxc exec web1 -- bash
```

## Script Reference

### setup-vds.sh

Sets up a fresh Ubuntu VDS with LXD, bridge networking, IP forwarding, and iptables persistence.

```
Usage: bash setup-vds.sh [OPTIONS]

Options:
  --interface IFACE       Network interface (default: eth0)
  --bridge-subnet CIDR    Bridge subnet (default: 10.10.10.1/24)
```

**What it does:**
- Updates system packages
- Installs LXD (via snap), iptables-persistent, python3
- Initializes LXD with a bridge (`lxdbr0`) — NAT disabled (we manage it manually)
- Enables IPv4/IPv6 forwarding persistently
- Saves base iptables rules

### create_container.py

Creates an LXD container with a static private IP on the bridge network.

```
Usage: python3 create_container.py [OPTIONS]

Options:
  -n, --name NAME         Container name (required)
  -p, --password PASS     Root password for SSH access (required)
  -i, --ip IP             Static private IP (auto-assigned from 10.10.10.101+ if omitted)
  --image IMAGE           LXD image (default: ubuntu:24.04)
  -l, --list              List all existing containers
```

**Examples:**
```bash
python3 create_container.py -n web1 -p 'Pass123'                      # auto IP
python3 create_container.py -n web1 -p 'Pass123' --ip 10.10.10.150    # manual IP
python3 create_container.py -n web1 -p 'Pass123' --image ubuntu:22.04 # different image
python3 create_container.py --list                                     # list containers
```

The container is ready for SSH immediately after creation (once a public IP is assigned).

### assign_public_ip.py

Assigns a public IP to a container by setting up 1:1 NAT (DNAT + SNAT + FORWARD rules) and persists the configuration across reboots.

```
Usage: python3 assign_public_ip.py [OPTIONS]

Options:
  -c, --container NAME    Container name (required)
  -i, --ip IP             Public IPv4 address (required)
  --ipv6 IPV6             Public IPv6 address (optional)
  -s, --status            Show current IP assignments
```

**Examples:**
```bash
python3 assign_public_ip.py -c web1 -i 157.173.122.74
python3 assign_public_ip.py -c web1 -i 157.173.122.74 --ipv6 2a02:c207:2310:8895::101
python3 assign_public_ip.py --status
```

**What it does:**
1. Adds the public IP to `eth0` (as /32 for IPv4, /128 for IPv6)
2. Creates DNAT rule — inbound traffic to public IP → container private IP
3. Creates SNAT rule — outbound traffic from container → public IP
4. Creates FORWARD rules to allow traffic through
5. Persists the IP in `/etc/netplan/99-additional-ips.yaml`
6. Saves iptables rules to `/etc/iptables/rules.v4` (and `rules.v6` for IPv6)

## Full Workflow Example

```bash
# --- On your local machine ---
scp setup-vds.sh create_container.py assign_public_ip.py root@85.190.254.209:/root/
ssh root@85.190.254.209

# --- On the VDS ---

# 1. Initial setup (only once)
bash setup-vds.sh

# 2. Create two containers
python3 create_container.py -n client-a -p 'SecurePass1'
python3 create_container.py -n client-b -p 'SecurePass2'

# 3. Assign public IPs
python3 assign_public_ip.py -c client-a -i 157.173.122.74
python3 assign_public_ip.py -c client-b -i 157.173.122.75

# 4. Verify
lxc exec client-a -- curl -s ifconfig.me   # → 157.173.122.74
lxc exec client-b -- curl -s ifconfig.me   # → 157.173.122.75

# 5. SSH in from anywhere
ssh root@157.173.122.74   # password: SecurePass1
ssh root@157.173.122.75   # password: SecurePass2

# 6. Check status
python3 assign_public_ip.py --status
python3 create_container.py --list
```

## Important Notes

- **Public IPs must be purchased and assigned** to your VDS in the data center control panel before using them.
- All scripts must be run as **root** on the VDS.
- The bridge uses `10.10.10.0/24` — containers get IPs starting from `.101`.
- NAT rules and netplan configs **survive reboots** thanks to `iptables-persistent` and netplan.
- IPv6 uses ULA (fd42::) internally with 1:1 NAT to public IPv6 addresses.

## Files on Server (after setup)

```
/root/
├── setup-vds.sh           # VDS setup script
├── create_container.py    # Container creation
└── assign_public_ip.py    # Public IP assignment

/etc/
├── netplan/
│   ├── 50-cloud-init.yaml          # Main network config (don't edit)
│   └── 99-additional-ips.yaml      # Additional public IPs (managed by scripts)
├── iptables/
│   ├── rules.v4                    # Persisted IPv4 NAT rules
│   └── rules.v6                    # Persisted IPv6 NAT rules
└── sysctl.d/
    └── 99-ip-forward.conf          # IP forwarding config
```
