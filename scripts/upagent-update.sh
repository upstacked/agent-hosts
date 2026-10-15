# upagent-update [--rev <commit>]
#
# Moves this machine to the latest agent-hosts, or to <commit>, and switches to
# it. The pull timer runs it, and so does upagent-anywhere over SSH, so both
# paths leave the same record in /var/lib/upagent/last-update.json.

flake=/etc/upagent
status=/var/lib/upagent/last-update.json
rev=""

while [ $# -gt 0 ]; do
  case "$1" in
    --rev) rev="$2"; shift 2 ;;
    *) echo "upagent-update: unknown argument $1" >&2; exit 2 ;;
  esac
done

if [ "$(id -u)" -ne 0 ]; then
  echo "upagent-update: run as root" >&2
  exit 1
fi

record() {
  local ok="$1" message="$2" locked
  locked=$(jq -r '.nodes.fleet.locked.rev // ""' "$flake/flake.lock" 2>/dev/null || true)
  mkdir -p "$(dirname "$status")"
  jq -n --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson ok "$ok" \
    --arg fleet "$locked" --arg message "$message" \
    '{at: $at, ok: $ok, fleet: $fleet, message: $message}' > "$status.tmp"
  mv "$status.tmp" "$status"
}

fail() {
  record false "$1"
  echo "upagent-update: $1" >&2
  exit 1
}

if [ -n "$rev" ]; then
  # Pinned the way flake.nix names agent-hosts, so the lock keeps following
  # the same repository afterwards.
  original=$(jq -c '.nodes.fleet.original' "$flake/flake.lock")
  case "$(jq -r .type <<<"$original")" in
    github) pinned="github:$(jq -r '.owner + "/" + .repo' <<<"$original")/$rev" ;;
    git) pinned="git+$(jq -r .url <<<"$original")?rev=$rev" ;;
    *) fail "agent-hosts is locked as $(jq -r .type <<<"$original"), which cannot be pinned" ;;
  esac
  nix flake lock "$flake" --override-input fleet "$pinned" ||
    fail "could not lock agent-hosts at $rev"
else
  nix flake update fleet --flake "$flake" || fail "could not fetch agent-hosts"
fi

nixos-rebuild switch --flake "$flake#host" || fail "the new configuration did not build or switch"
record true "switched"
