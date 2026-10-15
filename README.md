# agent-hosts

NixOS for the machines that run [upstacked-agent][releases]. Every agent
machine is built from this repository, and [upagent-anywhere][anywhere] is how
one gets here:

```sh
upagent-anywhere --target-host 10.30.100.20
```

[releases]: https://github.com/upstacked/agent-releases
[anywhere]: https://github.com/upstacked/upagent-anywhere

## What is here, and what is not

Here is everything every machine shares:

| | |
|---|---|
| `pkgs/upstacked-agent.nix` | the agent, as released, pinned by hash |
| `modules/upstacked-agent.nix` | `services.upstacked-agent`: the agent as a hardened service, configured as `agent.conf` |
| `modules/host.nix` | SSH as `upstacked` with the keys the machine's `host.json` names, the firewall, Nix, and updates |
| `modules/disk.nix` | one disk, bootable by BIOS or UEFI |
| `scripts/upagent-update.sh` | how a machine moves to a newer commit of this repository |

Nothing about any one machine is committed. What is particular to it lives on
the machine, in `/etc/upagent`, beside a three-line flake that calls
`lib.mkHost` on it. See `examples/host/host.json` for its shape. That is why
this repository can be public: machines that update themselves read it with
no credentials, and it holds no secrets. That includes SSH keys: who may log
in to a machine is chosen when it is installed, and written to its
`host.json`, not granted to every machine from here.

## Changing every machine at once

A commit to `main` reaches every machine in pull mode within its interval (an
hour by default), and every machine in push mode the next time someone runs
`upagent-anywhere update` against it. CI builds the example machine on every
push; do not merge what it cannot build.

To move every machine to a new agent:

```sh
scripts/bump-agent 0.3.1
```

## Checking a change locally

```sh
nix flake check           # evaluates everything; builds on Linux
nix eval .#nixosConfigurations.example.config.system.build.toplevel.drvPath
```

Building needs Linux. On macOS, evaluation is the check, or build inside a
`nixos/nix` container.
