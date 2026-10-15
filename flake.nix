{
  description = "NixOS for the machines that run upstacked-agent";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      disko,
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAll = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      readHost =
        dir:
        builtins.fromJSON (builtins.readFile (dir + "/host.json"))
        // {
          inherit dir;
          fleetRevision = self.rev or self.dirtyRev or "unknown";
        };

      mkSystem =
        host:
        nixpkgs.lib.nixosSystem {
          system = host.system or "x86_64-linux";
          specialArgs = { inherit host; };
          modules = [
            disko.nixosModules.disko
            self.nixosModules.host
          ];
        };
    in
    {
      # A VM's own flake, in /etc/upagent, is one call:
      #   nixosConfigurations.host = fleet.lib.mkHost ./.;
      # with host.json, and the facter.json nixos-anywhere writes, beside it.
      lib.mkHost = dir: mkSystem (readHost dir);

      nixosModules = {
        host = ./modules/host.nix;
        upstacked-agent = ./modules/upstacked-agent.nix;
      };

      packages = forAll (pkgs: rec {
        upstacked-agent = pkgs.callPackage ./pkgs/upstacked-agent.nix { };
        default = upstacked-agent;
      });

      templates.host = {
        path = ./templates/host;
        description = "The flake upagent-anywhere puts in /etc/upagent";
      };

      nixosConfigurations.example = self.lib.mkHost ./examples/host;

      # The example machine, built for each architecture the agent is released for.
      checks = forAll (pkgs: {
        example =
          (mkSystem (readHost ./examples/host // { inherit (pkgs.stdenv.hostPlatform) system; }))
          .config.system.build.toplevel;
      });
    };
}
