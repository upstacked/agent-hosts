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
| `scripts/upagent-update.sh` | how a machine moves to a newer commit of this repository, and rolls back if that leaves it unhealthy |
| `scripts/upagent-reboot.sh` | how a machine boots the kernel and systemd it was switched to, in its reboot window |

Nothing about any one machine is committed. What is particular to it lives on
the machine, in `/etc/upagent`, beside a three-line flake that calls
`lib.mkHost` on it. See `examples/host/host.json` for its shape. That is why
this repository can be public: machines that update themselves read it with
no credentials, and it holds no secrets. That includes SSH keys: who may log
in to a machine is chosen when it is installed, and written to its
`host.json`, not granted to every machine from here.

## Changing every machine at once

Machines follow one of two branches, as `updates.branch` in their `host.json`
says:

- `main`: canaries, a few machines that take every commit within their
  interval (an hour by default).
- `stable`, the default: everyone else.

A workflow fast-forwards `stable` on weekday mornings to the newest commit on
`main` that is at least a day old and that CI built. To promote one sooner,
for an urgent fix, run it by hand with that commit:

```sh
gh workflow run promote.yml -f commit=<sha>
```

Machines in pull mode take the head of their branch within their interval;
machines in push mode take it the next time someone runs `upagent-anywhere
update` against them. CI builds the example machine on every push; do not
merge what it cannot build.

A machine that is healthy before an update, but whose agent or SSH is down or
cannot reach GitHub afterwards, rolls back, and skips that commit from then on.
`/var/lib/upagent/last-update.json` says what happened, and
`/var/lib/upagent/rolled-back` lists the commits it skipped.

Switching does not reboot. Each machine reboots in the window its `host.json`
names (`updates.reboot`, a systemd calendar expression, Sundays at 03:00 by
default, `null` for never), and only when its kernel or systemd changed.

To move every machine to a new agent:

```sh
scripts/bump-agent 0.3.1
```

## Keeping nixpkgs current

nixpkgs reaches the machines only through this repository's `flake.lock`. A
workflow opens a pull request updating it every Monday; merge it. Each NixOS
release is supported for about seven months, so move `flake.nix` to the next
one before the current one's end of life: `nixos-26.05` ends on 2026-12-31.

## Checking a change locally

```sh
nix flake check           # evaluates everything; builds on Linux
nix eval .#nixosConfigurations.example.config.system.build.toplevel.drvPath
```

Building needs Linux. On macOS, evaluation is the check, or build inside a
`nixos/nix` container.
