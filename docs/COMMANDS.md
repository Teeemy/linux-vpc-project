# 📖 Complete Command Reference

## VPC Commands

### create-vpc
Create a new VPC (Linux bridge).

**Syntax:**
```bash
sudo ./vpcctl create-vpc <vpc-name> <cidr>
```

**Example:**
```bash
sudo ./vpcctl create-vpc my-vpc 10.0.0.0/16
```

**What it does:**
- Creates Linux bridge device
- Assigns gateway IP (first IP in CIDR)
- Enables the interface
- Stores metadata in `/var/lib/vpcctl/`

---

### delete-vpc
Delete a VPC and all associated resources.

**Syntax:**
```bash
sudo ./vpcctl delete-vpc <vpc-name>
```

**Example:**
```bash
sudo ./vpcctl delete-vpc my-vpc
```

**What it does:**
- Removes all veth pairs from bridge
- Deletes bridge device
- Cleans up metadata

---

### list-vpcs
List all VPCs with their status.

**Syntax:**
```bash
sudo ./vpcctl list-vpcs
```

**Output:**
```
NAME                 IP ADDRESS           STATE     
----                 ----------           -----     
my-vpc               10.0.0.1/16          UP        
```

---

## Subnet Commands

### create-subnet
Create a subnet in a VPC.

**Syntax:**
```bash
sudo ./vpcctl create-subnet <vpc-name> <subnet-name> <cidr>
```

**Example:**
```bash
sudo ./vpcctl create-subnet my-vpc web-subnet 10.0.1.0/24
```

**What it does:**
- Creates network namespace
- Creates veth pair
- Connects to VPC bridge
- Assigns IP address
- Sets default route to bridge

---

### delete-subnet
Delete a subnet.

**Syntax:**
```bash
sudo ./vpcctl delete-subnet <subnet-name>
```

**Example:**
```bash
sudo ./vpcctl delete-subnet web-subnet
```

---

### list-subnets
List all subnets.

**Syntax:**
```bash
sudo ./vpcctl list-subnets
```

**Output:**
```
NAME                 IP ADDRESS           GATEWAY             
----                 ----------           -------             
web-subnet           10.0.1.2/16          10.0.0.1            
```

---

### exec
Execute a command inside a subnet's namespace.

**Syntax:**
```bash
sudo ./vpcctl exec <subnet-name> <command>
```

**Examples:**
```bash
# Show IP address
sudo ./vpcctl exec web-subnet ip addr show

# Ping Google DNS
sudo ./vpcctl exec web-subnet ping -c 2 8.8.8.8

# Run curl
sudo ./vpcctl exec web-subnet curl http://example.com
```

---

## NAT Gateway Commands

### enable-nat
Enable NAT (internet access) for a subnet.

**Syntax:**
```bash
sudo ./vpcctl enable-nat <subnet-name> <subnet-cidr>
```

**Example:**
```bash
sudo ./vpcctl enable-nat web-subnet 10.0.1.0/24
```

**What it does:**
- Adds iptables MASQUERADE rule
- Enables IP forwarding
- Adds FORWARD chain rules
- Stores NAT configuration

---

### disable-nat
Disable NAT for a subnet.

**Syntax:**
```bash
sudo ./vpcctl disable-nat <subnet-name>
```

**Example:**
```bash
sudo ./vpcctl disable-nat web-subnet
```

---

### test-internet
Test internet connectivity from a subnet.

**Syntax:**
```bash
sudo ./vpcctl test-internet <subnet-name> [host]
```

**Examples:**
```bash
# Test with default (8.8.8.8)
sudo ./vpcctl test-internet web-subnet

# Test with specific host
sudo ./vpcctl test-internet web-subnet 1.1.1.1
```

**Tests performed:**
1. Ping test
2. DNS resolution (if dig available)
3. HTTP connectivity (if curl available)

---

### verify-nat
Verify NAT configuration for a subnet.

**Syntax:**
```bash
sudo ./vpcctl verify-nat <subnet-name>
```

**Example:**
```bash
sudo ./vpcctl verify-nat web-subnet
```

**Checks:**
- NAT metadata exists
- iptables MASQUERADE rule present
- IP forwarding enabled
- WAN interface up

---

### list-nat
List all NAT configurations.

**Syntax:**
```bash
sudo ./vpcctl list-nat
```

**Output:**
```
Active NAT Rules:
...iptables rules...

Subnets with NAT enabled:
  web-subnet           10.0.1.0/24          → wlp58s0
```

---

## VPC Peering Commands

### peer-vpcs
Create a peering connection between two VPCs.

**Syntax:**
```bash
sudo ./vpcctl peer-vpcs <vpc-a> <vpc-b>
```

**Example:**
```bash
sudo ./vpcctl peer-vpcs corp-vpc partner-vpc
```

**What it does:**
- Creates veth pair between bridges
- Adds routes for cross-VPC communication
- Stores peering metadata

---

### unpeer-vpcs
Remove peering between VPCs.

**Syntax:**
```bash
sudo ./vpcctl unpeer-vpcs <vpc-a> <vpc-b>
```

**Example:**
```bash
sudo ./vpcctl unpeer-vpcs corp-vpc partner-vpc
```

---

### list-peerings
List all VPC peering connections.

**Syntax:**
```bash
sudo ./vpcctl list-peerings
```

**Output:**
```
VPC-A                VPC-B                STATUS    
-----                -----                ------    
corp-vpc             partner-vpc          ACTIVE    
```

---

### test-peering
Test connectivity through a peering connection.

**Syntax:**
```bash
sudo ./vpcctl test-peering <vpc-a> <vpc-b>
```

**Example:**
```bash
sudo ./vpcctl test-peering corp-vpc partner-vpc
```

---

## Routing & Inspection Commands

### show-routes
Show routing table for a subnet.

**Syntax:**
```bash
sudo ./vpcctl show-routes <subnet-name>
```

**Example:**
```bash
sudo ./vpcctl show-routes web-subnet
```

---

### show-bridge
Show bridge forwarding table (MAC addresses).

**Syntax:**
```bash
sudo ./vpcctl show-bridge <vpc-name>
```

**Example:**
```bash
sudo ./vpcctl show-bridge my-vpc
```

---

### test-ping
Test connectivity between subnets.

**Syntax:**
```bash
sudo ./vpcctl test-ping <source-subnet> <destination-ip> [count]
```

**Example:**
```bash
sudo ./vpcctl test-ping web-subnet 10.0.2.2 3
```

---

### show-interfaces
Show network interfaces in a subnet.

**Syntax:**
```bash
sudo ./vpcctl show-interfaces <subnet-name>
```

**Example:**
```bash
sudo ./vpcctl show-interfaces web-subnet
```

---

### verify-learning
Verify bridge MAC learning.

**Syntax:**
```bash
sudo ./vpcctl verify-learning <vpc-name>
```

**Example:**
```bash
sudo ./vpcctl verify-learning my-vpc
```

---

## Utility Commands

### help
Show help information.

**Syntax:**
```bash
sudo ./vpcctl help
```

---

### version
Show version information.

**Syntax:**
```bash
sudo ./vpcctl version
```

---

## Common Workflows

### Create Complete VPC Environment
```bash
# 1. Create VPC
sudo ./vpcctl create-vpc prod-vpc 10.0.0.0/16

# 2. Create public subnet
sudo ./vpcctl create-subnet prod-vpc public 10.0.1.0/24

# 3. Create private subnet
sudo ./vpcctl create-subnet prod-vpc private 10.0.2.0/24

# 4. Enable NAT for public subnet
sudo ./vpcctl enable-nat public 10.0.1.0/24

# 5. Verify
sudo ./vpcctl list-vpcs
sudo ./vpcctl list-subnets
sudo ./vpcctl list-nat

# 6. Test
sudo ./vpcctl test-internet public
sudo ./vpcctl test-ping public 10.0.2.2
```

### Create VPC Peering
```bash
# 1. Create two VPCs
sudo ./vpcctl create-vpc vpc-a 10.1.0.0/16
sudo ./vpcctl create-vpc vpc-b 10.2.0.0/16

# 2. Create subnets
sudo ./vpcctl create-subnet vpc-a subnet-a 10.1.1.0/24
sudo ./vpcctl create-subnet vpc-b subnet-b 10.2.1.0/24

# 3. Create peering
sudo ./vpcctl peer-vpcs vpc-a vpc-b

# 4. Test
sudo ./vpcctl test-peering vpc-a vpc-b
```

### Complete Cleanup
```bash
# 1. Disable NAT
sudo ./vpcctl disable-nat public

# 2. Remove peerings
sudo ./vpcctl unpeer-vpcs vpc-a vpc-b

# 3. Delete subnets
sudo ./vpcctl delete-subnet public
sudo ./vpcctl delete-subnet private

# 4. Delete VPCs
sudo ./vpcctl delete-vpc prod-vpc
```

---

## Exit Codes

- `0` - Success
- `1` - Error (check log output)

---

## Environment

### Required Permissions
- Must run as root (sudo)

### Required Tools
- `ip` (iproute2)
- `iptables`
- `bridge` (bridge-utils)
- `sysctl`

### State Storage
- `/var/lib/vpcctl/` - VPC and subnet metadata
- `/var/lib/vpcctl/nat/` - NAT configuration
- `/var/lib/vpcctl/peerings/` - Peering connections

---

**For troubleshooting, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md)**

