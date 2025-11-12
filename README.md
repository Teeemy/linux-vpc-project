# VPC From Scratch - Linux Networking Project

Building AWS VPC functionality using only Linux primitives (network namespaces, bridges, iptables).

## 🎯 Project Overview

This project recreates core AWS VPC features using native Linux networking:
- VPCs (Linux bridges)
- Subnets (network namespaces)
- Inter-subnet routing (bridge forwarding)
- NAT Gateway (iptables MASQUERADE)
- Security isolation

## 🏗️ Architecture
```
┌─────────────────────────────────────────────────┐
│           VPC: 10.0.0.0/16 (Bridge)             │
│                                                  │
│  ┌──────────────┐       ┌──────────────┐       │
│  │ Public       │◄─────►│ Private      │       │
│  │ 10.0.1.0/24  │       │ 10.0.2.0/24  │       │
│  │ (Namespace)  │       │ (Namespace)  │       │
│  │              │       │              │       │
│  │ NAT: Yes ✓   │       │ NAT: No ✗    │       │
│  └──────────────┘       └──────────────┘       │
└─────────────────────────────────────────────────┘
           │
    iptables NAT
           │
       Internet
```

## 🚀 Quick Start
```bash
# Create VPC
sudo ./vpcctl create-vpc my-vpc 10.0.0.0/16

# Create subnets
sudo ./vpcctl create-subnet my-vpc public 10.0.1.0/24
sudo ./vpcctl create-subnet my-vpc private 10.0.2.0/24

# Enable NAT for public subnet
sudo ./vpcctl enable-nat public 10.0.1.0/24

# Test internet
sudo ./vpcctl test-internet public
```

## 📚 Features

### Stage 1: Basic VPC ✅
- VPC creation (Linux bridge)
- Single subnet (network namespace)
- Gateway connectivity

### Stage 2: Multi-Subnet Routing ✅
- Multiple subnets in one VPC
- Automatic inter-subnet routing
- Bridge MAC learning

### Stage 3: NAT Gateway ✅
- Selective internet access
- Public subnet connectivity
- Private subnet isolation
- iptables MASQUERADE

### Stage 4: VPC Isolation & Peering 🚧
Coming next...

## 🧪 Testing
```bash
# Run specific test
cd tests
sudo ./test-nat.sh

# Run all tests
sudo ./run-all-tests.sh
```

## 📖 Commands Reference

### VPC Management
- `create-vpc <name> <cidr>` - Create new VPC
- `delete-vpc <name>` - Delete VPC
- `list-vpcs` - List all VPCs

### Subnet Management
- `create-subnet <vpc> <name> <cidr>` - Create subnet
- `delete-subnet <name>` - Delete subnet
- `list-subnets` - List all subnets

### NAT Gateway
- `enable-nat <subnet> <cidr>` - Enable internet access
- `disable-nat <subnet>` - Disable NAT
- `test-internet <subnet>` - Test connectivity

## 🎓 Learning Resources

### Key Concepts
1. **Network Namespaces** - Linux kernel feature for network isolation
2. **veth Pairs** - Virtual ethernet cables connecting namespaces
3. **Bridges** - L2/L3 devices for packet forwarding
4. **iptables NAT** - Source IP translation for internet access
5. **Connection Tracking** - Stateful NAT implementation

### Interview Questions I Can Answer
- How does NAT work at the packet level?
- Why use MASQUERADE vs SNAT?
- How does bridge MAC learning work?
- What's the difference between namespaces and containers?
- How does AWS VPC implement public/private subnets?

## 🛠️ Technical Details

### Why This Design?

**Network Namespaces vs Containers:**
Namespaces are the primitive Docker uses. Working at this level shows deep understanding.

**Bridges vs Routing:**
Bridges provide automatic MAC learning, scaling to hundreds of subnets without manual configuration.

**MASQUERADE vs SNAT:**
MASQUERADE works with dynamic IPs (DHCP), making it portable across environments.

## 🐛 Troubleshooting

See [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)

## 📄 License

MIT License - Feel free to use for learning!

## 🙏 Acknowledgments

Built as part of DevOps internship Stage 4 project.