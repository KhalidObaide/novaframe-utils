#!/usr/bin/env python3
"""
create_container.py — Create an LXD container with a static private IP.

Usage:
    python3 create_container.py -n web1
    python3 create_container.py -n web1 --ip 10.10.10.150
    python3 create_container.py -n web1 --image ubuntu:22.04
    python3 create_container.py --list
"""

import argparse
import json
import subprocess
import sys

BRIDGE_PREFIX = "10.10.10"
IP_RANGE_START = 101
IP_RANGE_END = 254
DEFAULT_IMAGE = "ubuntu:24.04"


def run(cmd, check=True):
    """Run a shell command and return the result."""
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if check and result.returncode != 0:
        print(f"Error: {cmd}", file=sys.stderr)
        if result.stderr.strip():
            print(result.stderr.strip(), file=sys.stderr)
        sys.exit(1)
    return result


def get_containers():
    """Get all containers as JSON."""
    result = run("lxc list --format json")
    return json.loads(result.stdout)


def get_used_private_ips():
    """Get the set of private IPs already assigned to containers."""
    used = set()
    for c in get_containers():
        # Check static IP from device config
        for source in ("devices", "expanded_devices"):
            eth0 = c.get(source, {}).get("eth0", {})
            ip = eth0.get("ipv4.address")
            if ip:
                used.add(ip)
        # Check live network state
        state = c.get("state")
        if state and state.get("network"):
            for addr in state["network"].get("eth0", {}).get("addresses", []):
                if addr["family"] == "inet" and addr["address"].startswith(BRIDGE_PREFIX):
                    used.add(addr["address"])
    return used


def next_available_ip():
    """Find the next available private IP."""
    used = get_used_private_ips()
    for i in range(IP_RANGE_START, IP_RANGE_END + 1):
        ip = f"{BRIDGE_PREFIX}.{i}"
        if ip not in used:
            return ip
    print("Error: No available private IPs in range", file=sys.stderr)
    sys.exit(1)


def container_exists(name):
    """Check if a container already exists."""
    return run(f"lxc info {name}", check=False).returncode == 0


def list_containers():
    """Print a summary of all containers."""
    containers = get_containers()
    if not containers:
        print("No containers found.")
        return

    print(f"{'NAME':<20} {'STATE':<10} {'PRIVATE IP':<18} {'IMAGE':<20}")
    print("-" * 68)
    for c in containers:
        name = c["name"]
        state = c["status"]
        # Get private IP
        ip = "-"
        eth0 = c.get("expanded_devices", {}).get("eth0", {})
        if "ipv4.address" in eth0:
            ip = eth0["ipv4.address"]
        elif c.get("state") and c["state"].get("network"):
            for addr in c["state"]["network"].get("eth0", {}).get("addresses", []):
                if addr["family"] == "inet" and addr["address"].startswith(BRIDGE_PREFIX):
                    ip = addr["address"]
                    break
        image = c.get("config", {}).get("image.description", "-")
        print(f"{name:<20} {state:<10} {ip:<18} {image:<20}")


def setup_ssh(name, password):
    """Install SSH, set root password, and enable root login."""
    print("Setting up SSH access...")

    # Wait for cloud-init / apt to be ready
    run(f"lxc exec {name} -- bash -c 'for i in $(seq 1 30); do fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || break; sleep 1; done'", check=False)

    # Install openssh-server
    print("  Installing openssh-server...")
    run(f"lxc exec {name} -- apt-get update -qq")
    run(f"lxc exec {name} -- apt-get install -y -qq openssh-server")

    # Set root password
    print("  Setting root password...")
    run(f"lxc exec {name} -- bash -c 'echo root:{password} | chpasswd'")

    # Enable root SSH login with password
    run(f"lxc exec {name} -- bash -c 'sed -i \"s/^#\\?PermitRootLogin.*/PermitRootLogin yes/\" /etc/ssh/sshd_config'")
    run(f"lxc exec {name} -- bash -c 'sed -i \"s/^#\\?PasswordAuthentication.*/PasswordAuthentication yes/\" /etc/ssh/sshd_config'")

    # Remove Ubuntu 24.04 default drop-ins that disable password auth, then write ours
    run(f"lxc exec {name} -- bash -c 'rm -f /etc/ssh/sshd_config.d/50-cloud-init.conf /etc/ssh/sshd_config.d/60-cloudimg-settings.conf'", check=False)
    run(f"lxc exec {name} -- bash -c 'mkdir -p /etc/ssh/sshd_config.d && echo -e \"PermitRootLogin yes\\nPasswordAuthentication yes\" > /etc/ssh/sshd_config.d/99-root-login.conf'")

    # Enable and start sshd
    run(f"lxc exec {name} -- systemctl enable ssh")
    run(f"lxc exec {name} -- systemctl restart ssh")

    # Verify sshd is running
    result = run(f"lxc exec {name} -- systemctl is-active ssh", check=False)
    if result.stdout.strip() == "active":
        print("  SSH is running on port 22")
    else:
        print("  Warning: SSH may not be running", file=sys.stderr)


def create_container(name, private_ip, image, password):
    """Create and configure an LXD container."""
    if container_exists(name):
        print(f"Error: Container '{name}' already exists.", file=sys.stderr)
        sys.exit(1)

    print(f"Creating container '{name}'...")
    print(f"  Image:      {image}")
    print(f"  Private IP: {private_ip}")
    print()

    # Launch
    run(f"lxc launch {image} {name}")

    # Assign static IP
    run(f"lxc config device override {name} eth0 ipv4.address={private_ip}")

    # Restart to apply
    print("Restarting to apply static IP...")
    run(f"lxc restart {name}")

    # Wait briefly for network
    run("sleep 3")

    # Set up SSH and root password
    setup_ssh(name, password)

    # Verify
    result = run(f"lxc exec {name} -- ip -4 addr show eth0 2>/dev/null | grep inet | awk '{{print $2}}'", check=False)
    actual_ip = result.stdout.strip() if result.returncode == 0 else "pending"

    print()
    print(f"Container '{name}' created successfully!")
    print(f"  Private IP: {actual_ip}")
    print(f"  Root password: {password}")
    print(f"  SSH: port 22 (active)")
    print()
    print("To assign a public IP:")
    print(f"  python3 assign_public_ip.py -c {name} -i <PUBLIC_IP>")
    print()
    print("After assigning a public IP, SSH in with:")
    print(f"  ssh root@<PUBLIC_IP>")


def main():
    parser = argparse.ArgumentParser(
        description="Create an LXD container with a static private IP"
    )
    parser.add_argument("--name", "-n", help="Container name")
    parser.add_argument("--ip", "-i", help="Static private IP (auto-assigned if omitted)")
    parser.add_argument("--password", "-p", required=False, help="Root password for SSH access")
    parser.add_argument("--image", default=DEFAULT_IMAGE, help=f"LXD image (default: {DEFAULT_IMAGE})")
    parser.add_argument("--list", "-l", action="store_true", help="List existing containers")

    args = parser.parse_args()

    if args.list:
        list_containers()
        return

    if not args.name:
        parser.error("--name is required (or use --list)")

    if not args.password:
        parser.error("--password is required")

    private_ip = args.ip or next_available_ip()

    # Validate IP range
    if not private_ip.startswith(f"{BRIDGE_PREFIX}."):
        print(f"Error: IP must be in {BRIDGE_PREFIX}.0/24 range", file=sys.stderr)
        sys.exit(1)

    create_container(args.name, private_ip, args.image, args.password)


if __name__ == "__main__":
    main()
