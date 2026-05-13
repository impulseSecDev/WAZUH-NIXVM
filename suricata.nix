{ config, pkgs, lib, ... }:

let
  suricataUpdatePython = pkgs.python313.withPackages (ps: [
    ps.pyyaml
    ps.requests
    ps.pygments
  ]);
in
{
  users.users.suricata = {
    isSystemUser = true;
    group = "suricata";
    description = "Suricata IDS/IPS";
  };
  users.groups.suricata = { };

  systemd.tmpfiles.rules = [
    "d /var/log/suricata 0750 suricata suricata -"
    "d /var/lib/suricata 0750 suricata suricata -"
    "d /var/lib/suricata/rules 0750 suricata suricata -"
  ];

  environment.etc."suricata/suricata.yaml" = {
    user = "suricata";
    group = "suricata";
    mode = "0640";
    text = ''
%YAML 1.1
---
vars:
  address-groups:
    HOME_NET: "[192.168.0.0/16,10.0.0.0/24,172.16.0.0/24,100.64.0.0/24]"
    EXTERNAL_NET: "!$HOME_NET"
    HTTP_SERVERS: "$HOME_NET"
    SQL_SERVERS: "$HOME_NET"
    DNS_SERVERS: "$HOME_NET"
    TELNET_SERVERS: "$HOME_NET"
    AIM_SERVERS: "$EXTERNAL_NET"
    DC_SERVERS: "$HOME_NET"
    DNP3_SERVER: "$HOME_NET"
    DNP3_CLIENT: "$HOME_NET"
    MODBUS_CLIENT: "$HOME_NET"
    MODBUS_SERVER: "$HOME_NET"
    ENIP_CLIENT: "$HOME_NET"
    ENIP_SERVER: "$HOME_NET"
  port-groups:
    HTTP_PORTS: "80"
    SHELLCODE_PORTS: "!80"
    SSH_PORTS: "22"
    ORACLE_PORTS: "1521"
    FTP_PORTS: "21"
    DNP3_PORTS: "20000"
    MODBUS_PORTS: "502"
    FILE_DATA_PORTS: "[80,110,143]"
    GENEVE_PORTS: "6081"
    VXLAN_PORTS: "4789"
    TEREDO_PORTS: "3544"
    VAULTWARDEN_PORTS: "8222"

default-log-dir: /var/log/suricata

stats:
  enabled: yes
  interval: 8

outputs:
  - eve-log:
      enabled: yes
      filetype: regular
      filename: /var/log/suricata/eve.json
      community-id: yes
      community-id-seed: 0
      types:
        - alert:
            payload: yes
            payload-buffer-size: 4kb
            payload-printable: yes
            packet: yes
            metadata: yes
            tagged-packets: yes
        - anomaly:
            enabled: yes
            types:
              decode: yes
              stream: yes
              applayer: yes
        - http:
            extended: yes
        - dns:
            version: 2
        - tls:
            extended: yes
        - files:
            force-magic: no
        - smtp: {}
        - ftp: {}
        - rdp: {}
        - nfs: {}
        - smb: {}
        - ssh: {}
        - flow: {}
        - netflow: {}
        - drop: {}
  - fast:
      enabled: yes
      filename: /var/log/suricata/fast.log
      append: yes
  - stats:
      enabled: yes
      filename: /var/log/suricata/stats.log
      append: yes
      totals: yes
      threads: no

logging:
  default-log-level: notice
  outputs:
    - console:
        enabled: no
    - file:
        enabled: yes
        filename: /var/log/suricata/suricata.log
        level: info
    - syslog:
        enabled: no

nfq:
  - id: 0
  - id: 1
  - id: 2
  - id: 3

stream:
  memcap: 256mb
  checksum-validation: yes
  inline: yes
  reassembly:
    memcap: 256mb
    depth: 1mb
    toserver-chunk-size: 2560
    toclient-chunk-size: 2560
    randomize-chunk-size: yes

app-layer:
  protocols:
    tls:
      enabled: yes
    http:
      enabled: yes
    http2:
      enabled: yes
    ftp:
      enabled: yes
    smtp:
      enabled: yes
    ssh:
      enabled: yes
    dns:
      enabled: yes
    rdp:
      enabled: yes
    nfs:
      enabled: yes
    smb:
      enabled: yes
    krb5:
      enabled: yes
    dhcp:
      enabled: yes
    ike:
      enabled: yes
    modbus:
      enabled: no
    dnp3:
      enabled: no

detect:
  profile: medium
  custom-values:
    toclient-groups: 3
    toserver-groups: 25
  sgh-mpm-context: auto
  inspection-recursion-limit: 3000

threading:
  set-cpu-affinity: no
  detect-thread-ratio: 1.0

default-rule-path: /var/lib/suricata/rules
rule-files:
  - suricata.rules

classification-file: ${pkgs.suricata}/etc/suricata/classification.config
reference-config-file: ${pkgs.suricata}/etc/suricata/reference.config

unix-command:
  enabled: yes
  filename: /run/suricata/suricata-command.socket
    '';
  };

  environment.etc."suricata/disable.conf" = {
    user = "suricata";
    group = "suricata";
    mode = "0640";
    text = ''
re:modbus
re:dnp3
    '';
  };

  systemd.services.suricata = {
    description = "Suricata IDS/IPS (NFQ mode)";
    after = [ "network-online.target" "nftables.service" "suricata-update.service" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      PIDFile = "/run/suricata/suricata.pid";
      RuntimeDirectory = "suricata";
      RuntimeDirectoryMode = "0750";
      User = "suricata";
      Group = "suricata";
      AmbientCapabilities = [ "CAP_NET_ADMIN" "CAP_NET_RAW" "CAP_SYS_NICE" ];
      CapabilityBoundingSet = [ "CAP_NET_ADMIN" "CAP_NET_RAW" "CAP_SYS_NICE" ];
      ExecStartPre = "${pkgs.suricata}/bin/suricata -c /etc/suricata/suricata.yaml -T";
      ExecStart = "${pkgs.suricata}/bin/suricata -c /etc/suricata/suricata.yaml --pidfile /run/suricata/suricata.pid -q 0 -q 1 -q 2 -q 3";
      ExecReload = "${pkgs.suricata}/bin/suricatasc -c reload-rules";
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };

  systemd.services.suricata-update = {
    description = "Update Suricata Rules";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    before = [ "suricata.service" ];
    wantedBy = [ "suricata.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = "suricata";
      ExecStart = "${suricataUpdatePython}/bin/python3 ${pkgs.suricata}/bin/suricata-update --suricata-conf /etc/suricata/suricata.yaml --disable-conf /etc/suricata/disable.conf --no-reload";
      StateDirectory = "suricata";
    };
  };

  systemd.timers.suricata-update = {
    description = "Daily Suricata rule update";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "03:00:00";
      RandomizedDelaySec = "30m";
      Persistent = true;
    };
  };

  # NFQ nftables hooks — intercept all traffic except trusted interfaces
  networking.nftables.tables.suricata-ips = {
    family = "inet";
    content = ''
      chain suricata-forward {
        type filter hook forward priority -1; policy accept;
        iifname "wg0" accept
        oifname "wg0" accept
        iifname "tailscale0" accept
        oifname "tailscale0" accept
        counter queue num 0-3 bypass
      }

      chain suricata-input {
        type filter hook input priority -1; policy accept;
        iifname "wg0" accept
        iifname "tailscale0" accept
        counter queue num 0-3 bypass
      }

      chain suricata-output {
        type filter hook output priority -1; policy accept;
        oifname "wg0" accept
        oifname "tailscale0" accept
        counter queue num 0-3 bypass
      }
    '';
  };

  # fail2ban jail for Suricata alerts
  services.fail2ban.jails.suricata = {
    settings = {
      enabled  = true;
      filter   = "suricata";
      logpath  = "/var/log/suricata/fast.log";
      action   = "nftables-multiport[name=suricata, port=\"1:65535\", protocol=tcp]";
      maxretry = 3;
      findtime = 300;
      bantime  = 3600;
    };
  };

  environment.etc."fail2ban/filter.d/suricata.conf".text = ''
    [Definition]
    failregex = ^\d+/\d+/\d+-\d+:\d+:\d+\.\d+ \[\*\*\] .+ \[\*\*\] .+ \{TCP\} <HOST>:\d+ -> .+$
                ^\d+/\d+/\d+-\d+:\d+:\d+\.\d+ \[\*\*\] .+ \[\*\*\] .+ \{UDP\} <HOST>:\d+ -> .+$
    ignoreregex =
    datepattern = %%m/%%d/%%Y-%%H:%%M:%%S.%%f
  '';
}
