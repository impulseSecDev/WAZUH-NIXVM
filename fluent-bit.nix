###############################################################################
# Fluent-bit — ELK VM
###############################################################################
{ config, lib, pkgs, ... }:
{
  sops.secrets = {
    "es_host" = {};
    "elastic_password" = {};
    "elastic_user" = {};
  };

  # Lua script to parse Tailscale SSH sessions from login _CMDLINE
  environment.etc."fluent-bit/tailscale-parse.lua".text = ''
    function parse_tailscale(tag, timestamp, record)
      local cmdline = record["_CMDLINE"]
      if cmdline then
        -- Match Tailscale CGNAT IP in -h 100.x.x.x
        local ip = string.match(cmdline, "-h%s+(100%.[%d%.]+)")
        if ip then
          record["tailscale_src_ip"] = ip
          record["tailscale_ssh"]    = true
          record["event_type"]       = "tailscale_login"
        end
      end
      return 1, timestamp, record
    end
  '';

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

      [FILTER]
          name    lua
          match   *.journal
          script  /etc/fluent-bit/tailscale-parse.lua
          call    parse_tailscale

      [OUTPUT]
          name               es
          match              *
          host               ${config.sops.placeholder."es_host"}
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
