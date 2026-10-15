# upagent-update [--rev <commit>]
#
# Moves this machine to the head of the agent-hosts branch its host.json
# follows (updates.branch, stable by default), or to <commit>, and switches to
# it. The pull timer runs it, and so does upagent-anywhere over SSH, so both
# paths leave the same record in /var/lib/upagent/last-update.json.
#
# A switch that leaves the agent or SSH down, or GitHub unreachable, is rolled
# back, and that commit is skipped until a newer one, or --rev, asks for it.
# A machine that was already unhealthy before the switch is not rolled back.

flake=/etc/upagent
status=/var/lib/upagent/last-update.json
rejected=/var/lib/upagent/rolled-back
rev=""
explicit=false

while [ $# -gt 0 ]; do
  case "$1" in
    --rev) rev="$2"; explicit=true; shift 2 ;;
    *) echo "upagent-update: unknown argument $1" >&2; exit 2 ;;
  esac
done

if [ "$(id -u)" -ne 0 ]; then
  echo "upagent-update: run as root" >&2
  exit 1
fi

# The timer and upagent-anywhere must not both rewrite flake.lock.
exec 9>/run/upagent-update.lock
if ! flock -n 9; then
  echo "upagent-update: another update is running" >&2
  exit 1
fi

locked() {
  jq -r '.nodes.fleet.locked.rev // ""' "$flake/flake.lock" 2>/dev/null || true
}

record() {
  local ok="$1" message="$2"
  mkdir -p "$(dirname "$status")"
  jq -n --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson ok "$ok" \
    --arg fleet "$(locked)" --arg message "$message" \
    '{at: $at, ok: $ok, fleet: $fleet, message: $message}' > "$status.tmp"
  mv "$status.tmp" "$status"
}

fail() {
  record false "$1"
  echo "upagent-update: $1" >&2
  exit 1
}

# healthy <attempts>: tries every 10s.
healthy() {
  local attempt
  for attempt in $(seq "$1"); do
    if systemctl is-active --quiet upstacked-agent.service sshd.service &&
      curl -fsS --max-time 10 -o /dev/null https://github.com; then
      return 0
    fi
    [ "$attempt" -lt "$1" ] && sleep 10
  done
  return 1
}

was_healthy=false
healthy 1 && was_healthy=true

cp "$flake/flake.lock" "$flake/flake.lock.previous"

# Pinned the way flake.nix names agent-hosts: the lock keeps flake.nix's
# reference as its original, so it stays the same repository afterwards.
original=$(jq -c '.nodes.fleet.original' "$flake/flake.lock")
case "$(jq -r .type <<<"$original")" in
  github)
    repo=$(jq -r '.owner + "/" + .repo' <<<"$original")
    remote="https://github.com/$repo.git"
    pin="github:$repo/"
    ;;
  git)
    remote=$(jq -r .url <<<"$original")
    pin="git+$remote?rev="
    ;;
  *) fail "agent-hosts is locked as $(jq -r .type <<<"$original"), which cannot be pinned" ;;
esac

if [ -z "$rev" ]; then
  branch=$(jq -r '.updates.branch // "stable"' "$flake/host.json")
  rev=$(git ls-remote "$remote" "refs/heads/$branch" | cut -f1) ||
    fail "could not fetch agent-hosts"
  [ -n "$rev" ] || fail "agent-hosts has no branch $branch"
fi

nix flake lock "$flake" --override-input fleet "$pin$rev" ||
  fail "could not lock agent-hosts at $rev"
target=$(locked)

if [ "$explicit" = false ] && grep -qxF "$target" "$rejected" 2>/dev/null; then
  mv "$flake/flake.lock.previous" "$flake/flake.lock"
  fail "agent-hosts $target was rolled back here before; waiting for a newer commit"
fi

nixos-rebuild switch --flake "$flake#host" || {
  mv "$flake/flake.lock.previous" "$flake/flake.lock"
  fail "agent-hosts $target did not build or switch"
}

if [ "$was_healthy" = true ] && ! healthy 12; then
  echo "$target" >> "$rejected"
  mv "$flake/flake.lock.previous" "$flake/flake.lock"
  nixos-rebuild switch --rollback ||
    fail "agent-hosts $target left this machine unhealthy, and rolling back failed"
  fail "agent-hosts $target left this machine unhealthy, so it was rolled back"
fi

rm -f "$flake/flake.lock.previous"
record true "switched"
