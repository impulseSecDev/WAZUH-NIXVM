# ============================================================
# wazuh.nix — Wazuh Manager Module for Wazuh VM (NixOS)
# ============================================================

{ config, lib, pkgs, ... }:

{

  sops.secrets = {
    "wazuh_indexer_url" = {};
    "wazuh_indexer_username" = {};
    "wazuh_indexer_password" = {};
  };  

  sops.templates."wazuh.env" = {
    content = ''
      INDEXER_URL=${config.sops.placeholder."wazuh_indexer_url"}
      INDEXER_USERNAME=${config.sops.placeholder."wazuh_indexer_username"}
      INDEXER_PASSWORD=${config.sops.placeholder."wazuh_indexer_password"}
      FILEBEAT_SSL_VERIFICATION_MODE=none
    '';
    path = "/run/secrets/wazuh.env";
    mode = "0444";
  };

  virtualisation.docker.enable = true;

  virtualisation.oci-containers = {
    backend = "docker";
    containers = {
      wazuh-manager = {
        image = "wazuh/wazuh-manager:4.14.3";
        environmentFiles = [ config.sops.templates."wazuh.env".path ];

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

