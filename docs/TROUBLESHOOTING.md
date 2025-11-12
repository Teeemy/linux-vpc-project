# 🔧 Troubleshooting Guide

Common issues and their solutions.

---

## Issue: Cannot ping between subnets

**Symptoms:**
```bash
sudo ./vpcctl test-ping subnet-a 10.0.2.2
# Request timeout
```

**Diagnosis:**
```bash
# Check IP forwarding
sysctl net.ipv4.ip_forward
# Should return: net.ipv4.ip_forward = 1

# Check routing table
sudo ./vpcctl show-routes subnet-a

# Check if bridge is UP
ip link show br-vpc
```

**Solution:**
```bash
# Enable IP forwarding
sudo sysctl -w net.ipv4.ip_forward=1

# Make permanent
echo "net.ipv4.ip_forward = 1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# Bring bridge UP if needed
sudo ip link set br-vpc up
```

---

## Issue: NAT not working (public subnet can't reach internet)

**Symptoms:**
```bash
sudo ./vpcctl test-internet public-subnet
# Ping fails
```

**Diagnosis:**
```bash
# Check if NAT rule exists
sudo iptables -t nat -L POSTROUTING -n -v | grep MASQUERADE

# Check WAN interface
ip route show default

# Check if host has internet
ping -c 2 8.8.8.8

# Verify subnet CIDR in NAT rule
sudo ./vpcctl verify-nat public-subnet
```

**Solution:**
```bash
# Re-enable NAT
sudo ./vpcctl disable-nat public-subnet
sudo ./vpcctl enable-nat public-subnet 10.0.1.0/24

# Check iptables rules again
sudo iptables -t nat -L POSTROUTING -n -v
```

---

## Issue: Private subnet CAN reach internet (shouldn't!)

**Symptoms:**
```bash
sudo ./vpcctl exec private-subnet ping -c 2 8.8.8.8
# Success (this is bad!)
```

**Diagnosis:**
```bash
# Check for overly broad NAT rules
sudo iptables -t nat -L POSTROUTING -n -v

# Look for rules without source restriction
sudo iptables -t nat -L POSTROUTING -n | grep -v "10.0.1.0/24"
```

**Solution:**
```bash
# Remove overly broad MASQUERADE rules
sudo iptables -t nat -D POSTROUTING -j MASQUERADE

# Re-add specific rule
sudo ./vpcctl enable-nat public-subnet 10.0.1.0/24
```

---

## Issue: "Nexthop has invalid gateway"

**Symptoms:**
```bash
Error: Nexthop has invalid gateway.
```

**Cause:**
Subnet interface has /24 mask, can't reach gateway at 10.0.0.1

**Solution:**
```bash
# Change subnet interface to use VPC prefix
sudo ip netns exec subnet-name ip addr del 10.0.1.2/24 dev veth
sudo ip netns exec subnet-name ip addr add 10.0.1.2/16 dev veth
sudo ip netns exec subnet-name ip route add default via 10.0.0.1
```

---

## Issue: "name not a valid ifname" (interface name too long)

**Symptoms:**
```bash
Error: argument "veth-long-subnet-name-br" is wrong: "name" not a valid ifname
```

**Cause:**
Linux interface names limited to 15 characters.

**Solution:**
Already fixed in lib/subnet.sh with short names (vb-*, vs-*)

If you encounter this, update subnet.sh to use shorter names.

---

## Issue: VPC peering not working

**Symptoms:**
```bash
sudo ./vpcctl test-peering vpc-a vpc-b
# Ping fails
```

**Diagnosis:**
```bash
# Check if peering exists
sudo ./vpcctl list-peerings

# Check peering interfaces
sudo ip link show | grep peer

# Check routes
sudo ip route show | grep peer

# Verify both VPCs exist
sudo ./vpcctl list-vpcs
```

**Solution:**
```bash
# Remove and recreate peering
sudo ./vpcctl unpeer-vpcs vpc-a vpc-b
sudo ./vpcctl peer-vpcs vpc-a vpc-b

# Verify peering interfaces are UP
sudo ip link set peer-vpc-a-vpc-b up
sudo ip link set peer-vpc-b-vpc-a up
```

---

## Issue: "Subnet does not exist" but it shows in list-subnets

**Symptoms:**
```bash
sudo ./vpcctl list-subnets
# Shows: my-subnet

sudo ./vpcctl test-internet my-subnet
# ERROR: Subnet 'my-subnet' does not exist
```

**Cause:**
Bug in netns_exists() function

**Solution:**
Update lib/utils.sh with fixed netns_exists():
```bash
netns_exists() {
    local ns=$1
    if ip netns list 2>/dev/null | grep -qw "^${ns}"; then
        return 0
    fi
    if ip netns exec "$ns" true 2>/dev/null; then
        return 0
    fi
    return 1
}
```

---

## Issue: Tests hang indefinitely

**Symptoms:**
```bash
sudo ./test-nat.sh
# Hangs at "Creating test environment..."
```

**Diagnosis:**
```bash
# In another terminal, check processes
ps aux | grep -E 'vpcctl|test|ping'

# Check for hung namespaces
sudo ip netns list
```

**Solution:**
```bash
# Kill hung processes
sudo pkill -9 -f test-nat
sudo pkill -9 ping

# Clean up namespaces
sudo ip netns list | while read ns; do
    sudo ip netns delete "$ns" 2>/dev/null || true
done

# Add timeouts to test commands
# Use: timeout 10 command
```

---

## Issue: Bridge has multiple IPs

**Symptoms:**
```bash
sudo ip addr show br-vpc
# Shows: 10.0.0.1/16 AND 10.0.1.1/24
```

**Cause:**
Extra IP added accidentally

**Solution:**
```bash
# Remove extra IPs
sudo ip addr del 10.0.1.1/24 dev br-vpc

# Verify only gateway IP remains
sudo ip addr show br-vpc | grep inet
# Should show only: 10.0.0.1/16
```

---

## Issue: Permission denied

**Symptoms:**
```bash
./vpcctl help
bash: ./vpcctl: Permission denied
```

**Solution:**
```bash
# Make executable
chmod +x vpcctl
chmod +x tests/*.sh
chmod +x lib/*.sh

# Run with sudo
sudo ./vpcctl help
```

---

## Issue: Command not found

**Symptoms:**
```bash
sudo ./vpcctl help
sudo: ./vpcctl: command not found
```

**Solution:**
```bash
# Check shebang line
head -1 vpcctl
# Should be: #!/bin/bash

# Make executable
chmod +x vpcctl

# Run with bash explicitly if needed
sudo bash vpcctl help
```

---

## Issue: iptables rules persist after cleanup

**Symptoms:**
NAT rules remain after deleting VPC

**Solution:**
```bash
# List all NAT rules
sudo iptables -t nat -L POSTROUTING -n -v --line-numbers

# Delete specific rule by line number
sudo iptables -t nat -D POSTROUTING <line-number>

# Or flush all NAT rules (careful!)
sudo iptables -t nat -F POSTROUTING
```

---

## Issue: Cannot delete namespace

**Symptoms:**
```bash
sudo ip netns delete my-subnet
# Device or resource busy
```

**Solution:**
```bash
# Find processes using namespace
sudo ip netns pids my-subnet

# Kill them
sudo ip netns pids my-subnet | xargs sudo kill -9

# Delete veth interfaces first
sudo ip link delete vb-mysubnet 2>/dev/null || true

# Try deleting namespace again
sudo ip netns delete my-subnet
```

---

## Debug Mode

**Enable verbose output:**
```bash
# Run vpcctl commands with -x for debugging
sudo bash -x ./vpcctl create-vpc test 10.0.0.0/16
```

**Check logs:**
```bash
# System logs
sudo journalctl -xe | grep -i network

# Kernel messages
sudo dmesg | tail -50
```

---

## Clean Slate (Nuclear Option)

If everything is broken, start fresh:
```bash
#!/bin/bash
# cleanup-all.sh

echo "WARNING: This will delete ALL VPCs, subnets, and NAT rules!"
read -p "Continue? (yes/no): " confirm

if [[ "$confirm" != "yes" ]]; then
    echo "Aborted"
    exit 0
fi

# Delete all namespaces
sudo ip netns list | while read ns _; do
    echo "Deleting namespace: $ns"
    sudo ip netns delete "$ns" 2>/dev/null || true
done

# Delete all veth interfaces
sudo ip link show | grep -oP '^\d+: \K(vb-|vs-|peer-)[^:@]+' | while read iface; do
    echo "Deleting interface: $iface"
    sudo ip link delete "$iface" 2>/dev/null || true
done

# Delete all test bridges
sudo ip link show type bridge | grep -oP '^\d+: \K[^:]+' | while read br; do
    if [[ "$br" =~ ^(test-|vpc-|br-) ]]; then
        echo "Deleting bridge: $br"
        sudo ip link delete "$br" 2>/dev/null || true
    fi
done

# Flush NAT rules
echo "Flushing NAT rules..."
sudo iptables -t nat -F POSTROUTING 2>/dev/null || true

# Clean state directory
echo "Cleaning state directory..."
sudo rm -rf /var/lib/vpcctl/* 2>/dev/null || true

echo "Cleanup complete!"
```

---

## Getting Help

1. **Check logs:** Enable verbose mode with `bash -x`
2. **Verify basics:** IP forwarding, interfaces UP, routes exist
3. **Test incrementally:** Create VPC → add subnet → test gateway → add NAT
4. **Use provided tests:** `tests/test-basic.sh` validates core functionality

**Still stuck?** Review the code comments in lib/*.sh files - they explain what each command does and why.

