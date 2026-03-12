###############################################################################
# Fluent-bit — ELK VM
###############################################################################
{ config, lib, pkgs, ... }:
{
  sops.secrets = {
    "elastic_password" = {};
    "elastic_user" = {};
  };

  sops.templates."fluent-bit.conf" = {
    content = ''
      [SERVICE]
          flush     1
          log_level info
          daemon    off

      [INPUT]
          name systemd
          tag  wazuh.journal

      [INPUT]
          name tail
          path /var/log/*.log
          tag  nixos.tail

      [FILTER]
          name   modify
          match  *
          remove SYSLOG_TIMESTAMP

      [OUTPUT]
          name               es
          match              *
          host               127.0.0.1
          port               9200
          http_user          ${config.sops.placeholder."elastic_user"}
          http_passwd        ${config.sops.placeholder."elastic_password"}
          logstash_format    On
          logstash_prefix    wazuhvm
          suppress_type_name On
          buffer_size        10MB
    '';
    path = "/run/secrets/fluent-bit.conf";
    mode = "0444";
    owner = "root";
    group = "root";
  };

  services.fluent-bit = {
    enable = true;
    configurationFile = config.sops.templates."fluent-bit.conf".path;
  };

  systemd.services.fluent-bit = {
    serviceConfig.SupplementaryGroups = [ "adm" ];
  };

  # Prevents fluent-bit from resending logs on system restart or crash
  systemd.tmpfiles.rules = [
    "d /var/lib/fluent-bit 0750 fluent-bit fluent-bit -"
  ];
}
