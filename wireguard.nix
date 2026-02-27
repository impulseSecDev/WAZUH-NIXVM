# ============================================================
# wireguard.nix — WireGuard Module for Wazuh VM 
# ============================================================

{ config, lib, pkgs, ... }:

{
  environment.systemPackages = [ pkgs.wireguard-tools ];

  networking.wg-quick.interfaces = {
    wg0 = {
      address = [ "10.10.10.3/24" ];

      # Private key generated during setup.
      privateKeyFile = "/etc/secrets/wg-wazuh-private";

      peers = [
        {
          publicKey = "Owp1/h9AbTuRAGGGA9L0McoGbn54vWtYGRserVfrrxs=";

          # Wazuh agent traffic from arrives via this tunnel.
          allowedIPs = [ "10.10.10.0/24" ];

          endpoint = lib.strings.trim (builtins.readFile /etc/secrets/wg-endpoint);

          # Keepalive keeps the NAT table entry alive so the VPS
          # can send data back through the tunnel at any time.
          persistentKeepalive = 25;
        }
      ];
    };
  };
  networking.firewall = {
    # Required for WireGuard on NixOS.
    checkReversePath = "loose";
    interfaces."wg0" = {
      allowedTCPPorts = [
        1514
	1515
	55000
      ];
    };  
  };
}

