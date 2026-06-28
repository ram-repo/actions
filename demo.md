# Azure WAN: Concepts and Setup Guide

A reference covering Azure's three core WAN connectivity options — **Azure Virtual WAN**, **ExpressRoute**, and **Site-to-Site VPN** — with setup steps for each. Intended as classroom/reference material.

---

## 1. Overview: What Counts as "Azure WAN"

| Option | Best For | Connection Type | Typical Latency/Reliability |
|---|---|---|---|
| **Azure Virtual WAN** | Hub-and-spoke at global scale, branch offices | Aggregates VPN + ExpressRoute under one hub | Depends on underlying links |
| **ExpressRoute** | Enterprise, high-throughput, low-latency private link | Private connection via connectivity provider (not over public internet) | Highest reliability, SLA-backed |
| **Site-to-Site (S2S) VPN** | Smaller scale, cost-sensitive, quick setup | Encrypted tunnel over public internet (IPsec/IKE) | Good, but subject to internet variability |

A common teaching point: **Virtual WAN is the orchestration layer** — it doesn't replace ExpressRoute or VPN, it sits above them and manages routing between many sites/hubs.

---

## 2. Azure Virtual WAN

### 2.1 Core Concepts
- **Virtual WAN resource** — top-level container for the network.
- **Hub** — a Microsoft-managed virtual network deployed per region; spokes (VNets, branches) connect to it.
- **Hub Gateways** — VPN Gateway, ExpressRoute Gateway, and Azure Firewall can all attach to a hub.
- **Connections** — VNet connections, Site-to-site VPN connections, Point-to-site (remote user) connections, ExpressRoute connections — all unified under one hub.

### 2.2 Setup Steps

1. **Create the Virtual WAN resource**
   - Portal: *Create a resource → Virtual WAN*
   - Choose Basic or Standard tier (Standard required for ExpressRoute/VNet-to-VNet transit and most production scenarios).

2. **Create a Virtual Hub**
   - Inside the Virtual WAN resource, add a hub.
   - Specify region and address space (e.g., `/24` minimum recommended).

3. **Connect VNets to the Hub**
   - Add a **Hub Virtual Network Connection**.
   - Select existing VNets (or create new ones) to peer into the hub — no manual VNet peering needed.

4. **Add Connectivity (choose one or more)**
   - **Site-to-Site**: Deploy a VPN Gateway inside the hub, then create a Site connection pointing to your on-prem VPN device.
   - **ExpressRoute**: Deploy an ExpressRoute Gateway inside the hub, then link an existing ExpressRoute circuit.
   - **Point-to-Site**: Deploy a P2S gateway for remote user VPN access.

5. **Configure Routing**
   - Use **Hub Route Tables** to control traffic flow between spokes, VPN, and ExpressRoute.
   - Optionally insert **Azure Firewall** in the hub (secured virtual hub) for centralized inspection.

6. **Validate**
   - Check effective routes on a test VM in a connected VNet.
   - Confirm connectivity status shows "Connected" for each hub connection.

---

## 3. Azure ExpressRoute

### 3.1 Core Concepts
- **Circuit** — the logical connection between your on-prem network and Microsoft's edge, provisioned via a connectivity provider.
- **Peering types**: Private Peering (VNet access), Microsoft Peering (Microsoft 365/Azure PaaS public endpoints).
- **SKUs**: Standard, Premium (global reach, higher route limits), and ExpressRoute Local (data-transfer pricing tied to circuit region).
- Bypasses the public internet entirely — traffic travels over the provider's private backbone.

### 3.2 Setup Steps

1. **Choose a connectivity provider** (or use ExpressRoute Direct for direct Microsoft connection at 10/100 Gbps).

2. **Create the ExpressRoute circuit**
   - Portal: *Create a resource → ExpressRoute*
   - Select provider, peering location, bandwidth, and SKU.
   - Note the **Service Key** generated — you'll give this to your provider.

3. **Provider provisions the circuit**
   - Provider configures their side using the Service Key.
   - Circuit status moves from "Not Provisioned" → "Provisioned."

4. **Configure Peering**
   - Set up Private Peering (and/or Microsoft Peering) with BGP details: primary/secondary subnets, VLAN ID, peer ASN.

5. **Link to a Virtual Network**
   - Create a **Gateway subnet** in the target VNet.
   - Deploy an **ExpressRoute Virtual Network Gateway**.
   - Create a **Connection** linking the gateway to the ExpressRoute circuit.

6. **Verify**
   - Check circuit and peering status in the portal.
   - Confirm BGP session is "Up" and routes are being exchanged.
   - (Optional) Configure ExpressRoute Global Reach to connect on-prem sites to each other through Microsoft's backbone.

---

## 4. Site-to-Site (S2S) VPN

### 4.1 Core Concepts
- Encrypted IPsec/IKE tunnel between an on-prem VPN device and an Azure VPN Gateway.
- Requires a **public-facing VPN device** on-premises with a static public IP (in most configs).
- Good fit for smaller sites, dev/test, or as a backup path alongside ExpressRoute.

### 4.2 Setup Steps

1. **Create a Virtual Network and Gateway Subnet**
   - Subnet name must be exactly `GatewaySubnet`.
   - Recommended size: `/27` or larger.

2. **Create a Virtual Network Gateway**
   - Gateway type: **VPN**.
   - VPN type: **Route-based** (recommended over policy-based for flexibility).
   - SKU: choose based on throughput needs (VpnGw1–VpnGw5, or Basic for dev/test).
   - This step takes ~30–45 minutes to provision.

3. **Create a Local Network Gateway**
   - Represents your on-prem network: public IP of your VPN device + on-prem address space(s).

4. **Create the Connection**
   - Connection type: **Site-to-site (IPsec)**.
   - Link the Virtual Network Gateway to the Local Network Gateway.
   - Set a shared key (PSK) matching what's configured on the on-prem device.

5. **Configure the on-prem VPN device**
   - Use Azure's downloadable device configuration script (Portal → Gateway → *Download configuration*) matched to your device vendor/model.

6. **Verify the Tunnel**
   - Portal: Connection → check status shows "Connected."
   - Test connectivity from a VM in the VNet to an on-prem resource (and vice versa).

---

## 5. Choosing the Right Option (Teaching Summary)

```
Need global, multi-site orchestration with mixed VPN/ExpressRoute?
        → Azure Virtual WAN

Need guaranteed low latency, high throughput, private connectivity?
        → ExpressRoute

Need quick, cost-effective, internet-based connectivity?
        → Site-to-Site VPN

Need all of the above unified under one management plane?
        → Virtual WAN hub with both VPN and ExpressRoute gateways attached
```

---

## 6. Quick Reference: Key Azure CLI Commands

```bash
# Create a Virtual WAN
az network vwan create --resource-group MyRG --name MyVWAN --location eastus

# Create a Virtual Hub
az network vhub create --resource-group MyRG --name MyHub --vwan MyVWAN \
  --address-prefix 10.0.0.0/24 --location eastus

# Create an ExpressRoute circuit
az network express-route create --resource-group MyRG --name MyCircuit \
  --bandwidth 200 --provider "Provider Name" --peering-location "Location" --sku-family MeteredData --sku-tier Standard

# Create a VPN Gateway (Virtual Network Gateway)
az network vnet-gateway create --resource-group MyRG --name MyVPNGateway \
  --public-ip-address MyGatewayIP --vnet MyVNet --gateway-type Vpn \
  --vpn-type RouteBased --sku VpnGw1
```

---

## 7. Notes for Class Discussion
- Emphasize that **Virtual WAN is a management/orchestration layer**, not a replacement for the underlying connectivity types.
- ExpressRoute does **not** encrypt traffic by default (it's private, not encrypted) — IPsec can be layered on top if encryption-in-transit is required.
- VPN Gateway SKU choice directly affects throughput and the number of supported tunnels/connections — worth a side-by-side SKU comparison exercise.
- Good follow-on lab: deploy a Virtual WAN hub, attach a VPN site, and trace effective routes on a spoke VNet.
