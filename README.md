# Wazuh VM

> Host-based intrusion detection and security monitoring manager for the homelab security stack. Runs Wazuh Manager 4.14.3 on NixOS via Docker — fully declarative and version-controlled.

Part of the [Homelab Security Stack](https://github.com/impulseSecDev/NIX-HOMELAB-SECURITY-STACK).

---

## Overview

The Wazuh VM is the HIDS core for the homelab. It receives security events from agents on all hosts, performs log analysis, file integrity monitoring, rootkit detection, and vulnerability assessment, and forwards alerts to Elasticsearch on the ELK VM via internal Filebeat.

Wazuh Manager runs as a Docker container declared via `virtualisation.oci-containers` — managed by systemd, fully reproducible. All Wazuh state, configuration, logs, and alerts are persisted via volume mounts and survive container restarts.

---

## Stack

| Component | Version | Method |
|---|---|---|
| Wazuh Manager | 4.14.3 | Docker via `virtualisation.oci-containers` |
| Fluent Bit | 4.x | Native NixOS module |
| Wazuh Agent | 4.14.3 | Monitors the VM itself |
| WireGuard | — | Native NixOS module |
| Suricata | — | IDS/IPS in NFQ mode, EVE JSON alert logging |
| fail2ban | — | Automated banning for SSH and Suricata alerts |
| sops-nix | — | Encrypted secrets management |

---

## Agent Connections

| Agent | Host | Connection |
|---|---|---|
| Daily Driver | NixOS workstation | WireGuard wg0 |
| ELK VM | NixOS ELK VM | WireGuard wg0 |
| Vaultwarden VM | NixOS Vaultwarden VM | WireGuard wg0 |
| VPS | Ubuntu VPS | WireGuard wg0 |
| Laptop | NixOS laptop | WireGuard wg0 |

---

## Network

### Agent Ports

| Port | Protocol | Purpose |
|---|---|---|
| 1514 | TCP | Agent communication |
| 1515 | TCP | Agent enrollment |
| 55000 | TCP | Wazuh API |

Ports 1514, 1515, and 55000 are open on the WireGuard interface. All agents connect over WireGuard wg0 — Tailscale is used exclusively for admin and SSH access.

### WireGuard Tunnel

The Wazuh VM connects outbound to the VPS WireGuard hub — no inbound ports required on the home router.

```
Wazuh VM (wg0) ──── WireGuard ──── VPS hub
                outbound only, no home port forwarding
```

Log shipping to the ELK VM also routes over WireGuard (`wg0`) — deliberately separated from Tailscale admin traffic.

---

## NixOS Module Structure

```
nixos/
├── configuration.nix      # Entry point, imports all modules
├── hardware-configuration.nix
├── flake.nix
├── wazuh.nix              # Wazuh manager oci-container, volumes, tmpfiles
├── fluent-bit.nix         # Fluent Bit with sops template
├── wireguard.nix          # wg0 log shipping + VPS connectivity
├── suricata.nix           # IDS/IPS with NFQ nftables hooks, daily rule updates
├── fail2ban.nix           # Banning for SSH brute force and Suricata alerts
├── sops.nix               # sops-nix configuration
└── secrets/
    └── secrets.yaml       # sops-encrypted secrets (safe to commit)
```

---

## Persistent Data

All Wazuh state is stored on the host and mounted into the container — data survives container restarts and image updates:

```
/var/lib/wazuh/ossec/
├── etc/                     # ossec.conf, client.keys, authd.pass
├── logs/                    # ossec.log, alerts/alerts.json
├── api/configuration/       # Wazuh API config
├── queue/                   # Agent message queues
├── var/multigroups/         # Agent group assignments
├── active-response/bin/     # Active response scripts
├── integrations/            # Integration scripts
├── agentless/               # Agentless monitoring
└── wodles/                  # Wazuh modules
```

---

## Architecture

### Alert Flow

```
All hosts (Wazuh agents)
        │
        ▼
Wazuh Manager (this VM)
        │  internal Filebeat (Wazuh alerts only)
        ▼
Elasticsearch (ELK VM) ──── WireGuard wg0
```

### Log Shipping

Fluent Bit runs natively on the Wazuh VM and ships system/journal logs to Elasticsearch over WireGuard — separate from Wazuh alert data which is handled by the internal Filebeat inside the Wazuh container.

---

## Defense in Depth

- Wazuh agent monitors the VM itself — FIM on config files, rootkit detection
- Manager ports only open on WireGuard and Tailscale interfaces — not publicly exposed
- All agent communication encrypted in transit via Tailscale or WireGuard
- Alert forwarding to Elasticsearch over dedicated WireGuard log shipping channel
- Suricata running in NFQ IPS mode — inspects all non-WireGuard/Tailscale traffic, rules updated daily
- fail2ban bans on SSH brute force and Suricata alerts; Tailscale IPs whitelisted
- sops-nix encrypted secrets — no plaintext credentials in version control
- Agent enrollment password enforced via `ossec.conf` `<use_password>yes</use_password>`

---

## Tech Stack

`NixOS` `Wazuh` `Docker` `Fluent Bit` `WireGuard` `Tailscale` `Suricata` `fail2ban` `sops-nix` `HIDS` `File integrity monitoring` `Rootkit detection` `Log aggregation` `Declarative infrastructure`

---

## Problems Encountered

### Wazuh authd rejecting enrollment requests

**Problem:** `wazuh-authd` rejected all enrollment requests with `Invalid request for new agent` even after creating the `authd.pass` file.

**Solution:** The `<auth>` section of `ossec.conf` must explicitly contain `<use_password>yes</use_password>`. Without this the manager ignores the password file entirely. The config was copied from the running container, modified, and persisted via the existing volume mount on `/var/ossec/etc`.

### VPS agent firewall blocking enrollment

**Problem:** VPS Wazuh agent could not reach the enrollment service at port 1515 despite the WireGuard tunnel being up.

**Solution:** Added explicit firewall rules for the WireGuard interface in NixOS configuration. Unlike Tailscale which is trusted by default, WireGuard requires explicit rules:

```nix
networking.firewall.interfaces."wg0".allowedTCPPorts = [ 1514 1515 55000 ];
```

### Agent re-enrollment delay after manager restart

**Problem:** Disconnected agents waited up to an hour before being allowed to re-enroll due to the default `disconnected_time` threshold in `ossec.conf`.

**Solution:** Added a `<force>` block to the `<auth>` section of `ossec.conf` to reduce the disconnected time threshold to 1 minute:

```xml
<auth>
  <disabled>no</disabled>
  <force>
    <enabled>yes</enabled>
    <key_mismatch>yes</key_mismatch>
    <disconnected_time enabled="yes">1m</disconnected_time>
    <after_registration_time>0</after_registration_time>
  </force>
</auth>
```
