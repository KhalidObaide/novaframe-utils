#!/usr/bin/env python3
"""
assign_public_ip.py — Assign a public IP to an LXD container via 1:1 NAT.

Usage:
    python3 assign_public_ip.py -c web1 -i 157.173.122.74
    python3 assign_public_ip.py -c web1 -i 157.173.122.74 --ipv6 2a02:c207:2310:8895::101
    python3 assign_public_ip.py --status
"""

import argparse
import json
import os
import subprocess
import sys

INTERFACE = "eth0"
NETPLAN_FILE = "/etc/netplan/99-additional-ips.yaml"
BRIDGE_PREFIX = "10.10.10"


def run(cmd, check=True):
    """Run a shell command and return the result."""
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if check and result.returncode != 0:
        print(f"Error: {cmd}", file=sys.stderr)
        if result.stderr.strip():
            print(result.stderr.strip(), file=sys.stderr)
        sys.exit(1)
    return result


# ---------------------------------------------------------------------------
# Container helpers
# ---------------------------------------------------------------------------

def get_container_private_ip(name):
    """Get the private IPv4 of a container."""
    result = run(f"lxc list {name} --format json")
    containers = json.loads(result.stdout)
    if not containers:
        print(f"Error: Container '{name}' not found.", file=sys.stderr)
        sys.exit(1)

    c = containers[0]

    # Static device override
    for source in ("expanded_devices", "devices"):
        ip = c.get(source, {}).get("eth0", {}).get("ipv4.address")
        if ip:
            return ip

    # Live network state
    state = c.get("state")
    if state and state.get("network"):
        for addr in state["network"].get("eth0", {}).get("addresses", []):
            if addr["family"] == "inet" and addr["address"].startswith(BRIDGE_PREFIX):
                return addr["address"]

    print(f"Error: Could not determine private IP for '{name}'.", file=sys.stderr)
    sys.exit(1)


def get_container_ula(name):
    """Get the ULA (fd42::) IPv6 address of a container."""
    result = run(
        f"lxc exec {name} -- ip -6 addr show eth0 scope global 2>/dev/null"
        " | grep fd42 | awk '{print $2}' | cut -d/ -f1",
        check=False,
    )
    if result.returncode == 0 and result.stdout.strip():
        return result.stdout.strip()
    return None


# ---------------------------------------------------------------------------
# IP / iptables helpers
# ---------------------------------------------------------------------------

def ip_on_interface(ip, iface):
    """Check if an IP is already on the interface."""
    return ip in run(f"ip addr show {iface}", check=False).stdout


def rule_exists(v6, table, chain, rule):
    """Check if an iptables/ip6tables rule exists."""
    cmd = "ip6tables" if v6 else "iptables"
    return run(f"{cmd} -t {table} -C {chain} {rule} 2>/dev/null", check=False).returncode == 0


def add_rule(v6, table, chain, rule, label=""):
    """Add an iptables/ip6tables rule if it doesn't already exist."""
    cmd = "ip6tables" if v6 else "iptables"
    if rule_exists(v6, table, chain, rule):
        print(f"  {label} rule already exists")
    else:
        run(f"{cmd} -t {table} -A {chain} {rule}")
        print(f"  Added {label} rule")


# ---------------------------------------------------------------------------
# Netplan persistence
# ---------------------------------------------------------------------------

def read_netplan_entries():
    """Read address entries from the additional-IPs netplan file."""
    if not os.path.exists(NETPLAN_FILE):
        return []
    entries = []
    with open(NETPLAN_FILE) as f:
        for line in f:
            stripped = line.strip()
            if stripped.startswith("- ") and "/" in stripped:
                entries.append(stripped[2:].strip())
    return entries


def write_netplan(entries):
    """Write the additional-IPs netplan file."""
    addr_lines = "\n".join(f"        - {e}" for e in entries)
    content = (
        f"network:\n"
        f"  version: 2\n"
        f"  ethernets:\n"
        f"    {INTERFACE}:\n"
        f"      addresses:\n"
        f"{addr_lines}\n"
    )
    with open(NETPLAN_FILE, "w") as f:
        f.write(content)
    os.chmod(NETPLAN_FILE, 0o600)


def persist_ip_in_netplan(ip, prefix):
    """Add an IP/prefix to netplan if not already present."""
    entry = f"{ip}/{prefix}"
    entries = read_netplan_entries()
    if entry not in entries:
        entries.append(entry)
        write_netplan(entries)
        print(f"  Added {entry} to {NETPLAN_FILE}")
    else:
        print(f"  {entry} already in {NETPLAN_FILE}")


# ---------------------------------------------------------------------------
# IPv4 assignment
# ---------------------------------------------------------------------------

def assign_ipv4(container, public_ip, private_ip):
    """Set up full 1:1 NAT for an IPv4 address."""
    print(f"\n--- IPv4: {public_ip} → {private_ip} ({container}) ---")

    # Check for conflicts (is this public IP already DNATed to a different container?)
    result = run(f"iptables -t nat -L PREROUTING -n", check=False)
    for line in result.stdout.splitlines():
        if public_ip in line and private_ip not in line:
            print(f"Error: {public_ip} is already assigned to a different container.", file=sys.stderr)
            sys.exit(1)

    # 1. Add IP to interface
    if not ip_on_interface(public_ip, INTERFACE):
        run(f"ip addr add {public_ip}/32 dev {INTERFACE}")
        print(f"  Added {public_ip}/32 to {INTERFACE}")
    else:
        print(f"  {public_ip} already on {INTERFACE}")

    # 2. DNAT (inbound)
    add_rule(False, "nat", "PREROUTING",
             f"-d {public_ip} -j DNAT --to-destination {private_ip}", "DNAT")

    # 3. SNAT (outbound)
    add_rule(False, "nat", "POSTROUTING",
             f"-s {private_ip} -o {INTERFACE} -j SNAT --to-source {public_ip}", "SNAT")

    # 4. FORWARD
    add_rule(False, "filter", "FORWARD", f"-d {private_ip} -j ACCEPT", "FORWARD-in")
    add_rule(False, "filter", "FORWARD", f"-s {private_ip} -j ACCEPT", "FORWARD-out")

    # 5. Persist
    persist_ip_in_netplan(public_ip, "32")
    run("iptables-save > /etc/iptables/rules.v4")
    print("  Saved iptables rules")


# ---------------------------------------------------------------------------
# IPv6 assignment
# ---------------------------------------------------------------------------

def assign_ipv6(container, public_ipv6):
    """Set up full 1:1 NAT for an IPv6 address."""
    ula = get_container_ula(container)
    if not ula:
        print(f"\n  Warning: Could not get ULA for '{container}', skipping IPv6.", file=sys.stderr)
        return

    print(f"\n--- IPv6: {public_ipv6} → {ula} ({container}) ---")

    # 1. Add IPv6 to interface
    if not ip_on_interface(public_ipv6, INTERFACE):
        run(f"ip -6 addr add {public_ipv6}/128 dev {INTERFACE}")
        print(f"  Added {public_ipv6}/128 to {INTERFACE}")
    else:
        print(f"  {public_ipv6} already on {INTERFACE}")

    # 2. DNAT
    add_rule(True, "nat", "PREROUTING",
             f"-d {public_ipv6} -j DNAT --to-destination {ula}", "DNAT")

    # 3. SNAT
    add_rule(True, "nat", "POSTROUTING",
             f"-s {ula} -o {INTERFACE} -j SNAT --to-source {public_ipv6}", "SNAT")

    # 4. FORWARD
    add_rule(True, "filter", "FORWARD", f"-d {ula} -j ACCEPT", "FORWARD-in")
    add_rule(True, "filter", "FORWARD", f"-s {ula} -j ACCEPT", "FORWARD-out")

    # 5. Persist
    persist_ip_in_netplan(public_ipv6, "128")
    run("ip6tables-save > /etc/iptables/rules.v6")
    print("  Saved ip6tables rules")


# ---------------------------------------------------------------------------
# Status
# ---------------------------------------------------------------------------

def show_status():
    """Show current public IP assignments."""
    result = run("iptables -t nat -L PREROUTING -n")
    print("Current IPv4 assignments (DNAT rules):")
    print("-" * 55)
    found = False
    for line in result.stdout.splitlines():
        if "DNAT" in line:
            parts = line.split()
            # destination is parts[4], to: is at the end
            dst = parts[4] if len(parts) > 4 else "?"
            to_part = [p for p in parts if p.startswith("to:")]
            to_ip = to_part[0].replace("to:", "") if to_part else "?"
            print(f"  {dst} → {to_ip}")
            found = True
    if not found:
        print("  (none)")

    result = run("ip6tables -t nat -L PREROUTING -n", check=False)
    print("\nCurrent IPv6 assignments (DNAT rules):")
    print("-" * 55)
    found = False
    for line in result.stdout.splitlines():
        if "DNAT" in line:
            parts = line.split()
            dst = parts[3] if len(parts) > 3 else "?"
            to_part = [p for p in parts if p.startswith("to:")]
            to_ip = to_part[0].replace("to:", "") if to_part else "?"
            print(f"  {dst} → {to_ip}")
            found = True
    if not found:
        print("  (none)")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="Assign a public IP to an LXD container via 1:1 NAT"
    )
    parser.add_argument("--container", "-c", help="Container name")
    parser.add_argument("--ip", "-i", help="Public IPv4 address")
    parser.add_argument("--ipv6", help="Public IPv6 address (optional)")
    parser.add_argument("--status", "-s", action="store_true", help="Show current assignments")

    args = parser.parse_args()

    if args.status:
        show_status()
        return

    if not args.container or not args.ip:
        parser.error("--container and --ip are required (or use --status)")

    private_ip = get_container_private_ip(args.container)

    print(f"Container:  {args.container}")
    print(f"Private IP: {private_ip}")

    assign_ipv4(args.container, args.ip, private_ip)

    if args.ipv6:
        assign_ipv6(args.container, args.ipv6)

    # Apply netplan for persistence across reboots
    print("\nApplying netplan...")
    run("netplan apply")

    print(f"\n{'='*50}")
    print("Done! Verify with:")
    print(f"  lxc exec {args.container} -- curl -s ifconfig.me")
    if args.ipv6:
        print(f"  lxc exec {args.container} -- curl -6 -s ifconfig.me")
    print(f"{'='*50}")


if __name__ == "__main__":
    main()
