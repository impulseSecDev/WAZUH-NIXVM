{ config, lib, pkgs, ... }:
{
  services.fluent-bit = {
    enable = true;
    settings = {
      service = {
        flush = 1;
        log_level = "info";
        daemon = "off";
      };
      pipeline = {
        inputs = [
          {
            name = "systemd";
            tag = "wazuh.journal";
          }
        ];
        outputs = [
          {
            name = "es";
            match = "*";
            host = "100.64.0.3";
            port = 9200;
            http_user = "$\{ELASTIC_USERNAME}";
            http_passwd = "$\{ELASTIC_PASSWORD}";
            logstash_format = true;
            logstash_prefix = "wazuhvm";
            suppress_type_name = true;
          }
        ];
      };
    };
  };
  systemd.services.fluent-bit.serviceConfig = {
    EnvironmentFile = "/etc/secrets/elastic.env";
    SupplementaryGroups = [ "adm" ];
  };
  systemd.tmpfiles.rules = [
    "d /var/lib/fluent-bit 0750 fluent-bit fluent-bit -"
  ];
}

