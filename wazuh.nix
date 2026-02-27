# ============================================================
# wazuh.nix — Wazuh Manager Module for Wazuh VM (NixOS)
# ============================================================
# Import this file in your configuration.nix:
#
#   imports = [
#     ./wazuh.nix
#   ];
#
# ============================================================
# Architecture:
#   Wazuh manager runs as a Docker container declared via
#   virtualisation.oci-containers. Data directories are
#   mounted from the host so they persist across container
#   restarts and rebuilds.
#
#   Alerts are written to:
#   /var/lib/wazuh/ossec/logs/alerts/alerts.json
#
#   Fluent Bit on this VM reads that file and ships alerts
#   to Elasticsearch on the ELK VM over Tailscale.
# ============================================================
#
# SETUP — run these commands before rebuilding:
#
#   sudo mkdir -p /var/lib/wazuh/ossec/{api/configuration,etc,logs,queue,var/multigroups,integrations,active-response/bin,agentless,wodles}
#   sudo mkdir -p /var/lib/wazuh/filebeat/{etc,var}
#   sudo touch /etc/secrets/wazuh.env
#   sudo chmod 600 /etc/secrets/wazuh.env
#
# /etc/secrets/wazuh.env should contain:
#   INDEXER_URL=http://ELK_VM_TAILSCALE_IP:9200
#   INDEXER_USERNAME=elastic
#   INDEXER_PASSWORD=yourpassword
#
# Agents connect to this manager on:
#   - Port 1514 — agent communication (over Tailscale for local hosts)
#   - Port 1515 — agent enrollment (over Tailscale for local hosts)
#   - Port 55000 — Wazuh API
#   VPS agent connects over WireGuard tunnel at 10.10.10.3
# ============================================================

{ config, lib, pkgs, ... }:

{
  virtualisation.docker.enable = true;

  virtualisation.oci-containers = {
    backend = "docker";
    containers = {
      wazuh-manager = {
        image = "wazuh/wazuh-manager:4.14.3";

        environmentFiles = [ /etc/secrets/wazuh.env ];

        # Persistent volumes — data survives container restarts.
        # All Wazuh state, config, logs, and alerts live on the host.
        volumes = [
          "/var/lib/wazuh/ossec/api/configuration:/var/ossec/api/configuration"
          "/var/lib/wazuh/ossec/etc:/var/ossec/etc"
          "/var/lib/wazuh/ossec/logs:/var/ossec/logs"
          "/var/lib/wazuh/ossec/queue:/var/ossec/queue"
          "/var/lib/wazuh/ossec/var/multigroups:/var/ossec/var/multigroups"
          "/var/lib/wazuh/ossec/integrations:/var/ossec/integrations"
          "/var/lib/wazuh/ossec/active-response/bin:/var/ossec/active-response/bin"
          "/var/lib/wazuh/ossec/agentless:/var/ossec/agentless"
          "/var/lib/wazuh/ossec/wodles:/var/ossec/wodles"
        ];

        extraOptions = [ "--network=host" ];
      };
    };
  };

  # Ensure the base wazuh directory exists with correct permissions.
  systemd.tmpfiles.rules = [
    "d /var/lib/wazuh 0750 root root -"
  ];
}

