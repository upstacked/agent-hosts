# services.upstacked-agent: the agent as a hardened systemd service, configured
# by the same agent.conf the packaged agent reads.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.upstacked-agent;
  inherit (lib) mkOption types;

  # As the agent's own setup writes it: a value is quoted when it is empty or
  # holds anything the parser would otherwise split on.
  render =
    name: value:
    let
      v =
        if builtins.isBool value then
          lib.boolToString value
        else
          toString value;
      quoted = if v == "" || builtins.match ".*[ \t#\"].*" v != null then builtins.toJSON v else v;
    in
    "${name} = ${quoted}";

  configFile = pkgs.writeText "agent.conf" (
    lib.concatStringsSep "\n" (lib.mapAttrsToList render cfg.settings) + "\n"
  );

  modes = lib.splitString "," (cfg.settings.mode or "collector");
  collects = builtins.elem "collector" modes;
in
{
  options.services.upstacked-agent = {
    enable = lib.mkEnableOption "upstacked-agent";

    package = mkOption {
      type = types.package;
      default = pkgs.callPackage ../pkgs/upstacked-agent.nix { };
      defaultText = lib.literalExpression "the pinned release";
    };

    settings = mkOption {
      type = types.attrsOf (types.oneOf [ types.str types.int types.bool ]);
      default = { };
      example = {
        mode = "collector,monitor";
        "api.url" = "https://agent-api.upstacked-staging.sokl.dev";
        "observability.logs" = "warn";
      };
      description = ''
        Settings for agent.conf, named as `upstacked-agent run -h` lists them.
      '';
    };

    authKeyFile = mkOption {
      type = types.str;
      default = "/var/lib/upagent/secrets/authkey";
      description = ''
        The upsk- key the agent enrols with, read once. A path, not a store
        path: the key must never be copied into the world-readable store.
        Missing is fine for an agent that has already enrolled.
      '';
    };

    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Open the syslog and flow ports when the agent runs in collector mode.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.upstacked-agent.settings = {
      mode = lib.mkDefault "collector";
      "state.dir" = lib.mkDefault "/var/lib/upstacked-agent";
      admin = lib.mkDefault "127.0.0.1:9101";
    };

    environment.systemPackages = [ cfg.package ];

    # LoadCredential refuses to start the service without the file, and an
    # enrolled agent no longer needs a key. An empty one reads as none.
    systemd.tmpfiles.settings."10-upstacked-agent".${cfg.authKeyFile}.f = {
      mode = "0600";
      user = "root";
      group = "root";
    };
    environment.etc."upstacked-agent/agent.conf".source = configFile;

    # Unprivileged ICMP sockets, which monitor mode pings with.
    boot.kernel.sysctl."net.ipv4.ping_group_range" = "0 2147483647";

    networking.firewall = lib.mkIf (cfg.openFirewall && collects) {
      allowedUDPPorts = [
        514
        2055
        4739
        6343
      ];
      allowedTCPPorts = [ 601 ];
    };

    systemd.services.upstacked-agent = {
      description = "Upstacked agent";
      documentation = [ "https://github.com/upstacked/agent-releases" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      restartTriggers = [ configFile ];

      serviceConfig = {
        Type = "exec";
        ExecStart = "${lib.getExe cfg.package} run -config /etc/upstacked-agent/agent.conf";
        LoadCredential = "authkey:${cfg.authKeyFile}";
        Restart = "always";
        RestartSec = "2s";

        DynamicUser = true;
        StateDirectory = "upstacked-agent";
        StateDirectoryMode = "0750";

        # Binding 514 and 601 is the only privilege the agent needs.
        AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" ];
        CapabilityBoundingSet = [ "CAP_NET_BIND_SERVICE" ];
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
        ];
        RestrictNamespaces = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        SystemCallFilter = [ "@system-service" ];
        SystemCallArchitectures = "native";
      };
    };
  };
}
