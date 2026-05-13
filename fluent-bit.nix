###############################################################################
# Fluent-bit — VW VM
###############################################################################
{ config, lib, pkgs, ... }:
{
  sops.secrets = {
    "es_host" = {};
    "elastic_password" = {};
    "elastic_user" = {};
  };

  environment.etc."fluent-bit/tailscale-parse.lua".text = ''
    function parse_tailscale(tag, timestamp, record)
      local cmdline = record["_CMDLINE"]
      if cmdline then
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
      local msg = record["log"] or record["message"] or ""
      local jail, action, ip = string.match(msg, "%[([^%]]+)%]%s+(%w+)%s+([%d%.]+)")
      if jail then
        record["jail"] = jail
        record["action"] = action
        record["src_ip"] = ip
      end
      return 1, timestamp, record
    end
  '';

  environment.etc."fluent-bit/vaultwarden-auth.lua".text = ''
    function parse_vw_auth(tag, timestamp, record)
      if not record then return 1, timestamp, record end

      local msg = record["log"] or record["MESSAGE"] or ""

      if msg:find("incorrect") or msg:find("invalid") then
        record["event_type"] = "login_failure"
        record["client_ip"]  = msg:match("IP: ([%d%.%:a%-fA%-F]+)")
        record["username"]   = msg:match("Username: ([^%s]+)%.")

      elseif msg:find("logged in successfully") then
        record["event_type"] = "login_success"
        record["username"]   = msg:match("User ([^%s]+) logged in")
        record["client_ip"]  = msg:match("IP: ([%d%.%:a%-fA%-F]+)")
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
          flush        1
          log_level    info
          daemon       off
          Parsers_File /etc/fluent-bit/parsers.conf

      [INPUT]
          name systemd
          tag  vw.journal
          db   /var/lib/fluent-bit/journal.db

      [INPUT]
          name tail
          path /var/log/syslog /var/log/messages
          tag  vw.tail

      [INPUT]
          name              tail
          tag               vw.fail2ban
          path              /var/log/fail2ban.log
          db                /var/lib/fluent-bit/fail2ban.db

      [INPUT]
          name              tail
          tag               vw.suricata.eve
          path              /var/log/suricata/eve.json
          db                /var/lib/fluent-bit/suricata-eve.db
          mem_buf_limit     10MB
          skip_long_lines   on
          refresh_interval  5
          parser            suricata-eve

      [INPUT]
          name              tail
          tag               vw.suricata.fast
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
          name   lua
          match  *.journal
          script /etc/fluent-bit/tailscale-parse.lua
          call   parse_tailscale

      [FILTER]
          name   lua
          match  vw.fail2ban
          script /etc/fluent-bit/fail2ban-parse.lua
          call   parse_fail2ban

      [FILTER]
          name   lua
          match  vw.*
          script /etc/fluent-bit/vaultwarden-auth.lua
          call   parse_vw_auth

      [FILTER]
          name     record_modifier
          match    vw.*
          Record   hostname VW
          Record   source   vm-vaultwarden

      [OUTPUT]
          name               es
          match              *
          host               ${config.sops.placeholder."es_host"}
          port               9200
          http_user          ${config.sops.placeholder."elastic_user"}
          http_passwd        ${config.sops.placeholder."elastic_password"}
          logstash_format    On
          logstash_prefix    vw
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
    serviceConfig = {
      # Critical for reading /var/lib/vaultwarden and suricata logs
      SupplementaryGroups = [ "adm" "suricata" "vaultwarden" ];
      StateDirectory = lib.mkForce "fluent-bit";
      StateDirectoryMode = "0750";
    };
  };
}
