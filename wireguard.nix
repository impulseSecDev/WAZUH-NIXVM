# ============================================================
# wireguard.nix — WireGuard Module for Wazuh VM 
# ============================================================

{ config, lib, pkgs, ... }:

{
  environment.systemPackages = [ pkgs.wireguard-tools ];

  sops.secrets = {
    "headscale_hostname" = {};
    "wg0_private_key" = {};
    "wg0_headscale_allowedips" = {};
    "wg0_elk_allowedips" = {};
    "wg0_elk_endpoint" = {};
    "wg0_dailydriver_allowedips" = {};
    "wg0_vwvm_allowedips" = {};
    "wg0_laptop_allowedips" = {};
  };

  sops.templates."wg0.conf" = {
    content = ''
      [Interface]
      PrivateKey = ${config.sops.placeholder."wg0_private_key"}
      Address = 10.10.10.3/24
      ListenPort = 62091

      [Peer]
      # Headscale
      PublicKey = Owp1/h9AbTuRAGGGA9L0McoGbn54vWtYGRserVfrrxs=
      AllowedIPs = ${config.sops.placeholder."wg0_headscale_allowedips"}
      Endpoint = ${config.sops.placeholder."headscale_hostname"}
      PersistentKeepalive = 25

      [Peer]
      # Elk VM
      PublicKey = wW4FLWFhZGOyzUnnf3cFTNlcmcXgc7E7S6LobwFF3Tc=
      AllowedIPs = ${config.sops.placeholder."wg0_elk_allowedips"}
      Endpoint = ${config.sops.placeholder."wg0_elk_endpoint"}

      [Peer]
      # Daily Driver
      PublicKey = 51ZOUM8ant3W4DsQYkFhf642TSoH/Ct/kzTjW06p+X4=
      AllowedIPs = ${config.sops.placeholder."wg0_dailydriver_allowedips"}

      [Peer]
      # VW VM
      PublicKey = 8hppDFIJhfCzdjbNI7xqn98JxM0Bes/ZTbsZkekPEEw=
      AllowedIPs = ${config.sops.placeholder."wg0_vwvm_allowedips"}

      [Peer]
      # Laptop
      PublicKey = P+vWLcVRat/dq01yYksYeAvXtJgxo8j7C4GV05GV+0s=
      AllowedIPs = ${config.sops.placeholder."wg0_laptop_allowedips"}
      PersistentKeepalive = 25
    '';
    path = "/run/secrets/wg0.conf";
    mode = "0400";
  };

  networking.wg-quick.interfaces = {
    wg0.configFile = config.sops.templates."wg0.conf".path;
  };

  networking.firewall = {
    # Required for WireGuard on NixOS.
    checkReversePath = "loose";
    interfaces = {
      "wg0" = {
        allowedTCPPorts = [
          1514
	  1515
	  55000
        ];
      };
      "enp1s0" = {
        allowedUDPPorts = [
	  62091
        ];
      };	
    };  
  };
}

