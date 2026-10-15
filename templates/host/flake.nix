{
  inputs.fleet.url = "git+https://sokkel.dev/upstacked/agent-hosts.git";
  outputs = { fleet, ... }: {
    nixosConfigurations.host = fleet.lib.mkHost ./.;
  };
}
