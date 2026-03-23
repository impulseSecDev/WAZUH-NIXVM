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

  environment.etc."fluent-bit/fail2ban-parse.lua".text = ''
    function parse_fail2ban(tag, timestamp, record)
      local msg = record["message"] or ""
      local jail, action, ip = string.match(msg, "%[([^%]]+)%]%s+(%w+)%s+([%d%.]+)")
      if jail then
        record["jail"] = jail
        record["action"] = action
        record["src_ip"] = ip
      end
      local jail_only = string.match(msg, "%[([^%]]+)%]")
      if jail_only and not jail then
        record["jail"] = jail_only
      end
      return 1, timestamp, record
    end
  '';

  environment.etc."fluent-bit/parsers.conf".text = ''
    [PARSER]
        Name        suricata-eve
        Format      json
        Time_Key    timestamp
        Time_Format %Y-%m-%dT%H:%M:%S.%L%z
        Time_Keep   On
  '';

  sops.templates."fluent-bit.conf" = {
    content = ''
      [SERVICE]
          flush     1
          log_level info
          daemon    off
	  Parsers_File /etc/fluent-bit/parsers.conf

      [INPUT]
          name systemd
          tag  wazuh.journal

      [INPUT]
          name tail
          path /var/log/*.log
          tag  nixos.tail

      [INPUT]
          name              tail
          tag               wazuhvm.suricata.eve
          path              /var/log/suricata/eve.json
          db                /var/lib/fluent-bit/suricata-eve.db
          mem_buf_limit     10MB
          skip_long_lines   on
          refresh_interval  5
          parser            suricata-eve

      [INPUT]
          name              tail
          tag               wazuhvm.suricata.fast
          path              /var/log/suricata/fast.log
          db                /var/lib/fluent-bit/suricata-fast.db
          mem_buf_limit     5MB
          skip_long_lines   on
          refresh_interval  5

      [FILTER]
          name   modify
          match  *
          remove SYSLOG_TIMESTAMP

      [FILTER]
          name    lua
          match   *.journal
          script  /etc/fluent-bit/tailscale-parse.lua
          call    parse_tailscale

      [FILTER]
          name   lua
          match  wazuhvm.fail2ban
          script /etc/fluent-bit/fail2ban-parse.lua
          call   parse_fail2ban

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
