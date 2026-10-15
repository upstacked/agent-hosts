# The agent as released: the static binary from upstacked/agent-releases,
# pinned by hash. The source repositories are private, and a VM that updates
# itself should not need credentials to build its own agent.
#
# scripts/bump-agent <version> rewrites this file from the release's checksums.
{
  lib,
  stdenvNoCC,
  fetchurl,
  installShellFiles,
}:

let
  version = "0.3.0";
  sources = {
    x86_64-linux = {
      arch = "linux_amd64";
      hash = "sha256-u0yAcpwAbMIqec03AkNyewjJ+rii8NEhLsUWIc763ek=";
    };
    aarch64-linux = {
      arch = "linux_arm64";
      hash = "sha256-msgQax9nU4makDX9M8GvmXlvaTangomOxDx+/sTMFIw=";
    };
  };
  source =
    sources.${stdenvNoCC.hostPlatform.system}
      or (throw "upstacked-agent is not released for ${stdenvNoCC.hostPlatform.system}");
in
stdenvNoCC.mkDerivation {
  pname = "upstacked-agent";
  inherit version;

  src = fetchurl {
    url = "https://github.com/upstacked/agent-releases/releases/download/v${version}/upstacked-agent_${version}_${source.arch}.tar.gz";
    inherit (source) hash;
  };
  sourceRoot = ".";

  nativeBuildInputs = [ installShellFiles ];

  installPhase = ''
    runHook preInstall
    install -Dm0755 upstacked-agent $out/bin/upstacked-agent
    installShellCompletion --bash completions/upstacked-agent.bash
    installShellCompletion --fish completions/upstacked-agent.fish
    installShellCompletion --zsh completions/_upstacked-agent
    runHook postInstall
  '';

  meta = {
    description = "Ships logs, flows and monitoring from a customer network to Upstacked";
    homepage = "https://github.com/upstacked/agent-releases";
    platforms = builtins.attrNames sources;
    mainProgram = "upstacked-agent";
  };
}
