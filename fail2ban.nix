 confing, lib, pkgs, ... }:
{

  services.fail2ban = {
    enable = true;
    maxretry = 5;
    bantime = "1d";
    bantime-increment = {
      enable = true;
      formula = "ban.Time * 1.5";
      maxtime = "1w";
      overalljails = true;
    };
    ignoreIP = [ "100.64.0.6/32" "100.64.0.1/32" ];
    jails = {
      sshd = {
        enabled = true;
        settings = {
          journalmatch = "_SYSTEMD_UNIT=sshd.service";
          bantime = "2d";
          findtime = 600;
          maxretry = 3;
        };
      };
    };
  };

  environment.etc = {
    "fail2ban/filter.d/vaultwarden.conf".text = ''
      [Definition]
      failregex = ^<HOST> - - \[.*\] "POST /identity/connect/token HTTP/\d\.\d" 4\d\d
      ignoreregex =
    '';
  };
}
