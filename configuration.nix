###############################################################################
# Configuration.nix
###############################################################################

{ config, lib, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./disko-config.nix
      #./wireguard.nix
      #./fluent-bit.nix
      #./wazuh.nix
      #./fail2ban.nix
      #./suricata.nix
    ];

  # sops.secrets."user_password" = {
  #   neededForUsers = true;
  # };
  #
  # sops = {
  #   defaultSopsFile = ./secrets/secrets.yaml;
  #   age.keyFile = "/home/tim/.config/sops/age/keys.txt";
  # };

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
  };

  boot.supportedFilesystems = lib.mkForce [ "vfat" "fat32" "exfat" "ext4" "btrfs" ];

  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/var/lib/sbctl";
    autoGenerateKeys.enable = true;
    autoEnrollKeys = {
      enable = true;
      # Automatically reboot to enroll the keys in the firmware
      autoReboot = true;
    };
  };

  networking.hostName = "wazuh"; # Define your hostname.

  # Configure network connections interactively with nmcli or nmtui.
  networking.networkmanager.enable = true;

  swapDevices = [{
    device = "/var/lib/swapfile";
    size = 4*1024;
  }];

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.tim = {
    isNormalUser = true;
    hashedPasswordFile = config.sops.secrets."user_password".path;
    extraGroups = [ "wheel" ]; # Enable ‘sudo’ for the user.
    packages = with pkgs; [
      btop
      sops
      tmux
      vim
    ];
  };

  nix.settings.trusted-users = [ "root" "tim" ];

  users.users.root.hashedPassword = "!";

  programs.neovim.enable = true;
  programs.nano.enable = false;
  services.tailscale.enable = true;

  environment.systemPackages = with pkgs; [
    wget
    suricata
  ];

  environment = {
    shellAliases = {
      #sops-edit = "sudo SOPS_AGE_KEY_FILE=/home/tim/.config/sops/age/keys.txt sops";
      vi = "nvim";
      vim = "nvim";
    };
    variables = {
      EDITOR = "nvim";
      SUDO_EDITOR = "nvim";
      VISUAL = "nvim";
      SOPS_EDITOR = "vim";
    };
  };

  system.stateVersion = "26.05"; # Did you read the comment?

}
