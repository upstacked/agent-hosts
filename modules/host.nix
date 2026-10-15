# What every agent VM is: reachable over SSH by the keys its host.json names,
# running the
# agent as host.json says, and updated from this repository either on a
# timer or when upagent-anywhere asks.
#
# Nothing here is per host. A VM's own facts live on the VM, in /etc/upagent,
# and reach this module as `host`.
{
  config,
  lib,
  pkgs,
  modulesPath,
  host,
  ...
}:

let
  updates = host.updates or { };
  pull = (updates.mode or "push") == "pull";

  upagent-update = pkgs.writeShellApplication {
    name = "upagent-update";
    runtimeInputs = [
      config.nix.package
      config.system.build.nixos-rebuild
      pkgs.git
      pkgs.jq
      pkgs.coreutils
    ];
    text = builtins.readFile ../scripts/upagent-update.sh;
  };
in
{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    ./upstacked-agent.nix
    ./disk.nix
  ];

  networking.hostName = host.hostname;
  system.stateVersion = host.stateVersion or "26.05";

  hardware.facter.reportPath = lib.mkIf (builtins.pathExists (host.dir + "/facter.json")) (
    host.dir + "/facter.json"
  );

  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  services.qemuGuest.enable = true;

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  users.mutableUsers = false;
  users.users.upstacked = {
    isNormalUser = true;
    description = "Operators, through upagent-anywhere";
    extraGroups = [ "wheel" ];
    # Exactly the keys chosen for this machine when it was installed, which
    # may include the Upstacked management key. null, as well as absent, is
    # none, and then only the console gets in.
    openssh.authorizedKeys.keys = if host.sshKeys or null == null then [ ] else host.sshKeys;
  };
  security.sudo.wheelNeedsPassword = false;

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    trusted-users = [ "@wheel" ];
  };
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  services.upstacked-agent = {
    enable = true;
    settings = host.agent.settings or { };
  };

  systemd.tmpfiles.settings."10-upagent" = {
    "/var/lib/upagent".d.mode = "0755";
    "/var/lib/upagent/secrets".d.mode = "0700";
  };

  environment.systemPackages = [ upagent-update ];

  # Pull mode: the VM follows this repository by itself. Push mode runs the
  # same command, when upagent-anywhere asks over SSH.
  systemd.services.upagent-update = lib.mkIf pull {
    description = "Update this machine from agent-hosts";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig.Type = "oneshot";
    path = [ upagent-update ];
    script = "upagent-update";
    restartIfChanged = false;
  };
  systemd.timers.upagent-update = lib.mkIf pull {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5m";
      OnUnitActiveSec = updates.interval or "1h";
      RandomizedDelaySec = "10m";
      Persistent = true;
    };
  };

  # What upagent-anywhere reads to tell whether a machine is ours, and which
  # revision of this repository built it.
  environment.etc."upagent-release.json".text = builtins.toJSON {
    fleet = host.fleetRevision or "unknown";
    agent = config.services.upstacked-agent.package.version;
  };
}
