# WAZUH-NIXVM

**Wazuh security monitoring manager running on NixOS via Docker.**

Wazuh 4.14.3 manager declared as an OCI container in NixOS configuration. Receives security events from agents on all hosts, performs log analysis, file integrity monitoring, and rootkit detection, and forwards alerts to Elasticsearch on the ELK VM. Part of a broader security monitoring infrastructure — see [homelab-security-stack](https://github.com/impulseSecDev/homelab-security-stack) for full architecture.

---

## What This VM Does

- Runs Wazuh manager 4.14.3 for host-based intrusion detection across all hosts
- Receives security events from agents on the daily driver, ELK VM, and VPS
- Performs log analysis, FIM, rootkit detection, and vulnerability assessment
- Forwards alerts to Elasticsearch on the ELK VM via internal Filebeat
- Runs Fluent Bit to ship its own system logs to Elasticsearch over Tailscale
- Connects to the VPS agent over a WireGuard tunnel

---

## Stack

| Component | Version | Method |
|---|---|---|
| Wazuh Manager | 4.14.3 | Docker via `virtualisation.oci-containers` |
| Fluent Bit | 4.x | Native NixOS module |
| WireGuard | - | Native NixOS module |

---

## Agent Connections

| Agent | Host | Connection Method |
|---|---|---|
| dailyDriver | NixOS daily driver | Tailscale |
| elkVM | ELK VM | Tailscale |
| headscalevps | Ubuntu VPS | WireGuard tunnel (10.10.10.3:1514) |

---

## Wazuh Ports

| Port | Protocol | Purpose |
|---|---|---|
| 1514 | TCP | Agent communication |
| 1515 | TCP | Agent enrollment |
| 55000 | TCP | Wazuh API |

Ports 1514, 1515, and 55000 are open on the WireGuard interface only for the VPS agent. Local agents connect over Tailscale which is trusted by the NixOS firewall without explicit rules.

---

## Modules

| File | Purpose |
|---|---|
| `configuration.nix` | Wazuh manager container, Docker, base system config |
| `wireguard.nix` | WireGuard client — outbound tunnel to VPS on port 62091 |
| `fluent-bit.nix` | Fluent Bit — ships local systemd journal to ELK VM over Tailscale |
| `wazuh-agent.nix` | Wazuh agent container template — used on NixOS agent hosts |

---

## Secrets

Secrets stored in `/etc/secrets/` — not committed to this repository.

| File | Contents |
|---|---|
| `/etc/secrets/wazuh.env` | Elasticsearch indexer URL, credentials, API credentials |
| `/etc/secrets/wazuh-authd.pass` | Agent enrollment password |
| `/etc/secrets/elastic.env` | Fluent Bit Elasticsearch credentials |
| `/etc/secrets/wg-wazuh-private` | WireGuard private key |
| `/etc/secrets/wg-endpoint` | VPS public IP and WireGuard port |

---

## WireGuard Tunnel

This VM shares the same WireGuard interface on the VPS as the ELK VM, using a different peer IP on the same subnet.

```
Wazuh VM (10.10.10.3) ──── WireGuard ──── VPS (10.10.10.1)
          outbound connection, no inbound ports required
```

The VPS Wazuh agent connects back to this VM at `10.10.10.3:1514` for event shipping and `10.10.10.3:1515` for enrollment.

---

## Persistent Data

Wazuh state, configuration, logs, and alerts are stored on the host and mounted into the container:

```
/var/lib/wazuh/ossec/
├── api/configuration/   # Wazuh API config
├── etc/                 # ossec.conf, client.keys, authd.pass
├── logs/                # ossec.log, alerts/alerts.json
├── queue/               # Agent message queues
├── var/multigroups/     # Agent group assignments
├── integrations/        # Integration scripts
├── active-response/bin/ # Active response scripts
├── agentless/           # Agentless monitoring
└── wodles/              # Wazuh modules
```

---

## Problems Encountered

### Wazuh authd rejecting enrollment requests

**Problem:** `wazuh-authd` rejected all enrollment requests with `Invalid request for new agent` even after creating the `authd.pass` file.

**Solution:** The `<auth>` section of `ossec.conf` must explicitly contain `<use_password>yes</use_password>`. Without this the manager ignores the password file entirely. The config was copied from the running container, modified, and persisted via the existing volume mount.

### VPS agent firewall blocking

**Problem:** VPS Wazuh agent could not reach the enrollment service at `10.10.10.3:1515` despite the WireGuard tunnel being up.

**Solution:** Added explicit firewall rules for the WireGuard interface in NixOS configuration:
```nix
networking.firewall.interfaces."wg0".allowedTCPPorts = [ 1514 1515 55000 ];
```
Unlike Tailscale which is trusted by default, the WireGuard interface requires explicit firewall rules since NixOS treats it as an untrusted interface.

