# VDS Virtualization POC — LXD + Public IP Assignment

## Overview

This document describes the proof-of-concept for virtualizing a VDS (Virtual Dedicated Server)
and assigning individual public IPs to LXD containers — functioning like AWS Elastic IPs.

## Architecture

```
Internet
    │
    ▼
Data Center Gateway (85.190.254.1)
    │
    ▼
┌─────────────────────────────────────────────┐
│  VDS Host: 85.190.254.209 (eth0)            │
│  Additional IPs: 157.173.122.74-78          │
│                                             │
│  ┌─────────────────────────────────┐        │
│  │  lxdbr0 (10.10.10.1/24)        │        │
│  │                                 │        │
│  │  container-1: 10.10.10.101     │        │
│  │    ↔ Public: 157.173.122.74    │        │
│  │                                 │        │
│  │  container-2: 10.10.10.102     │        │
│  │    ↔ Public: 157.173.122.75    │        │
│  │                                 │        │
│  │  container-N: 10.10.10.10N     │        │
│  │    ↔ Public: 157.173.122.7N    │        │
│  └─────────────────────────────────┘        │
│                                             │
│  1:1 NAT (iptables DNAT/SNAT)              │
└─────────────────────────────────────────────┘
```

## Server Details

- **Host**: vmi3108895
- **OS**: Ubuntu 24.04.4 LTS
- **Main IP**: 85.190.254.209/24
- **Gateway**: 85.190.254.1
- **Interface**: eth0 (MAC: 00:50:56:61:a3:d8)
- **Additional IPs**: 157.173.122.74-78 (subnet 157.173.112.0/20)
- **LXD Version**: 5.21.4 LTS

## Setup Procedure (Step by Step)

### 1. Install LXD

```bash
snap install lxd
```

### 2. Initialize LXD with Bridge Network

```yaml
# lxd init --preseed with this config:
networks:
- config:
    ipv4.address: 10.10.10.1/24
    ipv4.nat: "false"       # We manage NAT manually for 1:1 mapping
    ipv6.address: none
  name: lxdbr0
  type: bridge
storage_pools:
- config: {}
  name: default
  driver: dir
profiles:
- devices:
    eth0:
      name: eth0
      network: lxdbr0
      type: nic
    root:
      path: /
      pool: default
      type: disk
  name: default
```

**Important**: Set `ipv4.nat: "false"` on the bridge to avoid conflicting with our manual 1:1 NAT rules.

### 3. Enable IP Forwarding (Persistent)

```bash
echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/99-ip-forward.conf
sysctl -p /etc/sysctl.d/99-ip-forward.conf
```

### 4. Add Public IPs to Host

```bash
# Immediate (non-persistent)
ip addr add 157.173.122.74/32 dev eth0
ip addr add 157.173.122.75/32 dev eth0

# Persistent via netplan
cat > /etc/netplan/99-additional-ips.yaml << 'EOF'
network:
  version: 2
  ethernets:
    eth0:
      addresses:
        - 157.173.122.74/32
        - 157.173.122.75/32
        - 157.173.122.76/32
        - 157.173.122.77/32
        - 157.173.122.78/32
EOF
chmod 600 /etc/netplan/99-additional-ips.yaml
netplan apply
```

### 5. Create Container with Static Private IP

```bash
# Launch container
lxc launch ubuntu:24.04 container-1

# Assign static private IP
lxc config device override container-1 eth0 ipv4.address=10.10.10.101

# Restart to apply
lxc restart container-1
```

### 6. Set Up 1:1 NAT (Public IP ↔ Container)

```bash
# DNAT: incoming traffic to public IP → container private IP
iptables -t nat -A PREROUTING -d 157.173.122.74 -j DNAT --to-destination 10.10.10.101

# SNAT: outbound traffic from container → public IP
iptables -t nat -A POSTROUTING -s 10.10.10.101 -o eth0 -j SNAT --to-source 157.173.122.74

# Allow forwarding for this container
iptables -A FORWARD -d 10.10.10.101 -j ACCEPT
iptables -A FORWARD -s 10.10.10.101 -j ACCEPT

# Save rules for persistence
iptables-save > /etc/iptables/rules.v4
```

### 7. Repeat for Each Container

| Container   | Private IP    | Public IP        |
|-------------|---------------|------------------|
| container-1 | 10.10.10.101  | 157.173.122.74   |
| container-2 | 10.10.10.102  | 157.173.122.75   |
| container-3 | 10.10.10.103  | 157.173.122.76   |
| container-4 | 10.10.10.104  | 157.173.122.77   |
| container-5 | 10.10.10.105  | 157.173.122.78   |

## Helper Script

A helper script is deployed at `/root/assign-public-ip.sh`:

```bash
# Usage: ./assign-public-ip.sh <container-name> <public-ip> <private-ip>
./assign-public-ip.sh container-3 157.173.122.76 10.10.10.103
```

This script:
1. Adds the public IP to eth0
2. Creates DNAT/SNAT iptables rules
3. Adds FORWARD rules
4. Saves rules for persistence

## Current Status

### ✅ IPv6 — WORKING (POC Proven)
- Each container has its own **unique globally-routable public IPv6**
- Container-1: `2a02:c207:2310:8895::101`
- Container-2: `2a02:c207:2310:8895::102`
- Outbound verified: each container shows its own IP via `curl -6 ifconfig.me`
- Inbound: DNAT routes traffic from public IPv6 to correct container
- Uses 1:1 NAT (ip6tables DNAT/SNAT) between public IPv6 and container ULA (fd42::)
- NDP works because public IPv6 addresses are on the host's eth0
- Scalable: the /64 subnet provides ~18 quintillion addresses

### ⏳ IPv4 — Blocked by BGP Routing
- LXD + bridge + 1:1 NAT setup is fully configured and correct
- Additional IPv4s (157.173.122.74-78) are NOT routed by the data center network
- **Traceroute proof**: traffic to 157.173.122.74 dies in the Telia transit backbone (hop 11)
  before ever reaching the data center's edge routers, while 85.190.254.209 reaches fine
- IPs are assigned in the data center panel but BGP announcement for 157.173.112.0/20 is missing
- **Action**: Contact data center support with traceroute evidence
- **Once fixed**: IPv4 NAT is already configured and will work immediately

### Verification Commands
```bash
# IPv6 (works now):
lxc exec container-1 -- curl -6 -s https://ifconfig.me  # → 2a02:c207:2310:8895::101
lxc exec container-2 -- curl -6 -s https://ifconfig.me  # → 2a02:c207:2310:8895::102
# Ping from any IPv6-capable machine:
ping6 2a02:c207:2310:8895::101
ping6 2a02:c207:2310:8895::102

# IPv4 (once data center fixes routing):
ping 157.173.122.74
ping 157.173.122.75
lxc exec container-1 -- curl -s https://ifconfig.me  # → 157.173.122.74
```

## Next Steps (Automation Phase)

Once the POC is validated with working public IPs, build Python scripts to:

1. **Container Lifecycle Management**
   - Create/destroy containers with auto-assigned private IPs
   - Attach/detach public IPs dynamically

2. **IP Pool Management**
   - Track available/assigned public IPs
   - Allocate/release IPs (like AWS Elastic IPs)

3. **API Layer**
   - REST API for provisioning (Flask/FastAPI)
   - Endpoints: create container, assign IP, destroy container, list containers

4. **Monitoring**
   - Container health checks
   - Bandwidth monitoring per public IP
   - Resource usage (CPU, RAM, disk) per container

## IPv6 Setup Procedure

### 1. Enable IPv6 forwarding and NDP proxy
```bash
sysctl -w net.ipv6.conf.all.forwarding=1
sysctl -w net.ipv6.conf.eth0.proxy_ndp=1
# Persist in /etc/sysctl.d/99-ip-forward.conf
```

### 2. Enable IPv6 on LXD bridge (ULA for internal routing)
```bash
lxc network set lxdbr0 ipv6.address fd42::1/64
```

### 3. Add public IPv6 to host eth0
```bash
ip -6 addr add 2a02:c207:2310:8895::101/128 dev eth0
sleep 3  # Wait for DAD
```

### 4. Set up 1:1 NAT (ip6tables)
```bash
# Get container's ULA address
C_ULA=$(lxc exec container-1 -- ip -6 addr show eth0 scope global | grep fd42 | awk '{print $2}' | cut -d/ -f1)

# DNAT inbound
ip6tables -t nat -A PREROUTING -d 2a02:c207:2310:8895::101 -j DNAT --to-destination $C_ULA
# SNAT outbound
ip6tables -t nat -A POSTROUTING -s $C_ULA -o eth0 -j SNAT --to-source 2a02:c207:2310:8895::101
# Forward rules
ip6tables -A FORWARD -d $C_ULA -j ACCEPT
ip6tables -A FORWARD -s $C_ULA -j ACCEPT
```

### Key Lesson: NDP Proxy
The kernel's built-in NDP proxy (`ip -6 neigh add proxy`) does NOT work for addresses
within the same /64 already on the interface. Instead, add public IPv6 directly to eth0
and use 1:1 NAT. This ensures the host responds to NDP naturally.

## Key Files on Server

- `/etc/netplan/50-cloud-init.yaml` — Main network config (do not edit)
- `/etc/netplan/99-additional-ips.yaml` — Additional public IPv4s
- `/etc/sysctl.d/99-ip-forward.conf` — IP forwarding (v4 + v6)
- `/etc/iptables/rules.v4` — Persisted IPv4 NAT/forwarding rules
- `/etc/ndppd.conf` — NDP proxy config (alternative approach, not used currently)
- `/root/assign-public-ip.sh` — Helper script for assigning IPv4 IPs
