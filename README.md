# 🌐 VPC From Scratch - Linux Networking Project

> Building AWS VPC functionality from scratch using only native Linux networking primitives

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Bash](https://img.shields.io/badge/Bash-4.0%2B-green.svg)](https://www.gnu.org/software/bash/)
[![Linux](https://img.shields.io/badge/Linux-Kernel%204.0%2B-blue.svg)](https://www.kernel.org/)

## 🎯 Project Overview

This project recreates core AWS Virtual Private Cloud (VPC) features using only Linux kernel primitives:
- **VPCs** → Linux bridges
- **Subnets** → Network namespaces
- **Inter-subnet routing** → Bridge forwarding + IP forwarding
- **NAT Gateway** → iptables MASQUERADE
- **VPC Peering** → veth pairs between bridges
- **Security** → Complete namespace isolation

**Why This Matters:** Understanding how cloud networking actually works at the kernel level - the same primitives AWS, Docker, and Kubernetes use under the hood.

---

## 🏗️ Architecture
```
┌─────────────────────────────────────────────────────────────┐
│                        HOST MACHINE                          │
│  ┌────────────────────────────────────────────────────────┐ │
│  │              VPC: 10.0.0.0/16 (br-vpc1)                │ │
│  │                                                          │ │
│  │  ┌──────────────────┐         ┌──────────────────┐    │ │
│  │  │ Public Subnet    │         │ Private Subnet   │    │ │
│  │  │ 10.0.1.0/24      │◄───────►│ 10.0.2.0/24      │    │ │
│  │  │ (ns-public)      │         │ (ns-private)     │    │ │
│  │  │                  │         │                  │    │ │
│  │  │ ✅ NAT Enabled   │         │ ❌ Isolated      │    │ │
│  │  │ Internet: YES    │         │ Internet: NO     │    │ │
│  │  └────────┬─────────┘         └──────────────────┘    │ │
│  │           │                                             │ │
│  │           └──────────┬────────────────────────────────►│ │
│  │                      │                                  │ │
│  │              Bridge Routes Traffic                      │ │
│  └────────────────────────────────────────────────────────┘ │
│                           │                                  │
│                   iptables MASQUERADE                        │
│                           │                                  │
│                    ┌──────▼──────┐                          │
│                    │ eth0 (WAN)  │                          │
│                    └─────────────┘                          │
└─────────────────────────────────────────────────────────────┘
                              │
                          INTERNET
```

---

## 🚀 Quick Start

### Prerequisites
```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install -y iproute2 iptables bridge-utils

# RHEL/CentOS
sudo yum install -y iproute iptables bridge-utils
```

### Installation
```bash
# Clone the repository
git clone <https://github.com/Teeemy/linux-vpc-project.git>
cd vpc-from-scratch

# Make vpcctl executable
chmod +x vpcctl
chmod +x tests/*.sh
chmod +x lib/*.sh

# Verify installation
sudo ./vpcctl help
```

### Basic Usage
```bash
# Create a VPC
sudo ./vpcctl create-vpc my-vpc 10.0.0.0/16

# Create subnets
sudo ./vpcctl create-subnet my-vpc public-subnet 10.0.1.0/24
sudo ./vpcctl create-subnet my-vpc private-subnet 10.0.2.0/24

# Enable NAT for public subnet (internet access)
sudo ./vpcctl enable-nat public-subnet 10.0.1.0/24

# Test internet connectivity
sudo ./vpcctl test-internet public-subnet

# View configuration
sudo ./vpcctl list-vpcs
sudo ./vpcctl list-subnets
sudo ./vpcctl list-nat

# Cleanup
sudo ./vpcctl disable-nat public-subnet
sudo ./vpcctl delete-subnet public-subnet
sudo ./vpcctl delete-subnet private-subnet
sudo ./vpcctl delete-vpc my-vpc
```

---

## 📚 Features by Stage

### ✅ Stage 1: Basic VPC & Subnet
- Create VPC (Linux bridge)
- Create subnet (network namespace)
- Connect via veth pairs
- Gateway connectivity

**Commands:**
```bash
sudo ./vpcctl create-vpc test-vpc 10.0.0.0/16
sudo ./vpcctl create-subnet test-vpc web-subnet 10.0.1.0/24
sudo ./vpcctl exec web-subnet ping -c 2 10.0.0.1  # Ping gateway
```

### ✅ Stage 2: Multi-Subnet Routing
- Multiple subnets in one VPC
- Automatic inter-subnet routing
- Bridge MAC learning
- Bidirectional connectivity

**Commands:**
```bash
sudo ./vpcctl create-subnet test-vpc app-subnet 10.0.2.0/24
sudo ./vpcctl test-ping web-subnet 10.0.2.2  # Reach app subnet
sudo ./vpcctl show-routes web-subnet
```

### ✅ Stage 3: NAT Gateway
- Selective internet access
- iptables MASQUERADE
- Public subnet connectivity
- Private subnet isolation
- Connection tracking

**Commands:**
```bash
sudo ./vpcctl enable-nat web-subnet 10.0.1.0/24
sudo ./vpcctl test-internet web-subnet
sudo ./vpcctl verify-nat web-subnet
sudo ./vpcctl list-nat
```

### ✅ Stage 4: VPC Isolation & Peering
- Multiple isolated VPCs
- VPC-to-VPC peering
- Controlled cross-VPC routing
- Peering management

**Commands:**
```bash
sudo ./vpcctl create-vpc vpc-a 10.1.0.0/16
sudo ./vpcctl create-vpc vpc-b 10.2.0.0/16
sudo ./vpcctl peer-vpcs vpc-a vpc-b
sudo ./vpcctl test-peering vpc-a vpc-b
sudo ./vpcctl list-peerings
```

### 🚧 Stage 5: Security Groups (Future)
- Port-based filtering
- Source/destination rules
- Stateful connections
- JSON policy files

---

## 🧪 Testing

### Run All Tests
```bash
cd tests
sudo ./run-all-tests.sh
```

### Run Individual Tests
```bash
sudo ./test-basic.sh      # Stage 1 tests
sudo ./test-routing.sh    # Stage 2 tests
sudo ./test-nat.sh        # Stage 3 tests
sudo ./test-peering.sh    # Stage 4 tests
```

### Expected Results
```
╔═══════════════════════════════════════════════════════╗
║              TEST SUITE SUMMARY                       ║
╚═══════════════════════════════════════════════════════╝

  Total Tests:    6
  ✓ Passed:       4
  ✗ Failed:       0
  ⊘ Skipped:      2

[SUCCESS] All implemented tests passed!
```

---

## 📖 Command Reference

### VPC Management
| Command | Description | Example |
|---------|-------------|---------|
| `create-vpc` | Create new VPC | `sudo ./vpcctl create-vpc my-vpc 10.0.0.0/16` |
| `delete-vpc` | Delete VPC | `sudo ./vpcctl delete-vpc my-vpc` |
| `list-vpcs` | List all VPCs | `sudo ./vpcctl list-vpcs` |
| `show-vpc` | Show VPC details | `sudo ./vpcctl show-vpc my-vpc` |

### Subnet Management
| Command | Description | Example |
|---------|-------------|---------|
| `create-subnet` | Create subnet | `sudo ./vpcctl create-subnet my-vpc web 10.0.1.0/24` |
| `delete-subnet` | Delete subnet | `sudo ./vpcctl delete-subnet web` |
| `list-subnets` | List all subnets | `sudo ./vpcctl list-subnets` |
| `exec` | Execute in subnet | `sudo ./vpcctl exec web ping 8.8.8.8` |

### NAT Gateway
| Command | Description | Example |
|---------|-------------|---------|
| `enable-nat` | Enable NAT | `sudo ./vpcctl enable-nat web 10.0.1.0/24` |
| `disable-nat` | Disable NAT | `sudo ./vpcctl disable-nat web` |
| `test-internet` | Test internet | `sudo ./vpcctl test-internet web` |
| `verify-nat` | Verify NAT config | `sudo ./vpcctl verify-nat web` |
| `list-nat` | List NAT rules | `sudo ./vpcctl list-nat` |

### VPC Peering
| Command | Description | Example |
|---------|-------------|---------|
| `peer-vpcs` | Create peering | `sudo ./vpcctl peer-vpcs vpc-a vpc-b` |
| `unpeer-vpcs` | Remove peering | `sudo ./vpcctl unpeer-vpcs vpc-a vpc-b` |
| `list-peerings` | List peerings | `sudo ./vpcctl list-peerings` |
| `test-peering` | Test peering | `sudo ./vpcctl test-peering vpc-a vpc-b` |

---

## 🎓 Technical Deep Dive

### How It Works

#### Network Namespaces
- Isolated network stacks (like lightweight VMs)
- Own routing tables, interfaces, iptables
- Docker/Kubernetes use these under the hood
```bash
# Create namespace
ip netns add my-subnet

# Execute inside namespace
ip netns exec my-subnet ip addr show
```

#### veth Pairs
- Virtual ethernet cables with two ends
- Connect namespace to bridge
```bash
# Create veth pair
ip link add veth0 type veth peer name veth1

# Move one end into namespace
ip link set veth0 netns my-subnet

# Connect other end to bridge
ip link set veth1 master br-vpc
```

#### Linux Bridges
- Layer 2 switches with MAC learning
- Can route at Layer 3 when ip_forward=1
- Automatically forwards between ports
```bash
# Create bridge
ip link add br-vpc type bridge
ip link set br-vpc up

# Assign IP (becomes gateway)
ip addr add 10.0.0.1/16 dev br-vpc
```

#### iptables NAT
- MASQUERADE: Rewrites source IP
- Connection tracking: Maintains state
- Allows private IPs to reach internet
```bash
# Enable NAT
iptables -t nat -A POSTROUTING -s 10.0.1.0/24 -o eth0 -j MASQUERADE

# View NAT table
iptables -t nat -L POSTROUTING -n -v
```

---

## 🐛 Troubleshooting

### Issue: Cannot ping between subnets

**Check IP forwarding:**
```bash
sysctl net.ipv4.ip_forward  # Should be 1
sudo sysctl -w net.ipv4.ip_forward=1
```

**Check routes:**
```bash
sudo ./vpcctl show-routes subnet-name
```

### Issue: NAT not working

**Verify MASQUERADE rule:**
```bash
sudo iptables -t nat -L POSTROUTING -n -v | grep MASQUERADE
```

**Check WAN interface:**
```bash
ip route show default
```

### Issue: VPC peering fails

**Check if peering exists:**
```bash
sudo ./vpcctl list-peerings
sudo ip link show | grep peer
```

**Verify routes:**
```bash
sudo ip route show | grep peer
```

See [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) for more details.

---

## 🎤 Interview Talking Points

### Key Concepts to Explain

1. **Network Namespaces vs Containers**
   > "Namespaces are the kernel primitive Docker uses. Working at this level shows I understand the foundation, not just the abstraction."

2. **Why Bridges Work Better Than Routes**
   > "Bridges automatically learn MAC addresses, so I don't need to manually configure routes as subnets are added. It scales naturally, just like AWS VPCs."

3. **MASQUERADE vs SNAT**
   > "MASQUERADE dynamically uses the outgoing interface's IP, making it portable. SNAT requires a static IP. I chose MASQUERADE for flexibility."

4. **VPC Isolation**
   > "Different bridges have no Layer 2 connectivity. They're completely isolated domains. Peering connects them with veth pairs and explicit routes."

5. **Why This Matches AWS**
   > "AWS VPCs use similar concepts - software-defined networking with virtual routers and controlled connectivity. The principles are identical."

---

## 📊 Project Stats

- **Lines of Code:** ~2,000+ (Bash)
- **Commands Implemented:** 25+
- **Test Coverage:** 4 test suites, 40+ test cases
- **Features:** VPC, Subnets, Routing, NAT, Peering
- **Documentation:** Comprehensive guides + inline comments

---

## 🤝 Contributing

This is an educational project for DevOps internship. Feedback welcome!

---

## 📄 License

MIT License - Feel free to use for learning purposes.

---

## 🙏 Acknowledgments

Built as part of DevOps Internship Stage 4 project to demonstrate deep understanding of cloud networking fundamentals.

**Technologies Used:**
- Linux Network Namespaces
- Linux Bridges
- veth Pairs
- iptables/netfilter
- iproute2 utilities

---

## 📞 Contact

For questions about this implementation, see [INTERVIEW_GUIDE.md](docs/INTERVIEW_GUIDE.md)

---

## Author
   Onibon-oje Mariam T

---


**⭐ Star this repo if you found it helpful for learning cloud networking!**
