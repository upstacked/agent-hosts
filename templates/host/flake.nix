{
  inputs.fleet.url = "github:upstacked/agent-hosts";
  outputs = { fleet, ... }: {
    nixosConfigurations.host = fleet.lib.mkHost ./.;
  };
}
