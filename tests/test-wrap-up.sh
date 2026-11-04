#!/usr/bin/env bash
# Tests for git/wrap-up's offload-mirror.py, the cleanup of a worktree's mirror on mybaze's
# second test machine. ssh and docker are fakes on PATH: the fake ssh runs the remote script
# locally under a throwaway HOME, and the fake docker keeps the database list in a file.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCRIPT="$ROOT/plugins/git/skills/wrap-up/scripts/offload-mirror.py"
PYTHON=$(command -v python3)
WORK=$(cd "$(mktemp -d)" && pwd -P)
SLEEPER=""
cleanup() {
  if [ -n "$SLEEPER" ]; then kill "$SLEEPER" 2>/dev/null || true; fi
  rm -rf "$WORK"
}
trap cleanup EXIT

fail() { printf 'FAIL %s\n' "$1"; exit 1; }
ok() { printf 'ok   %s\n' "$1"; }
field() { "$PYTHON" -c 'import json,sys; v=json.load(sys.stdin)[sys.argv[1]]; print(v if isinstance(v,str) else json.dumps(v))' "$1"; }

# The worktree name and remote name of a real mirror, computed by mybaze's own code.
NAME=mybaze_a_full_suite_runs_on_the_pc_while_df507c91bb96
REMOTE=mybaze_offload_9a6c9c2578bf

BIN="$WORK/bin"; mkdir -p "$BIN" "$WORK/home"
DBFILE="$WORK/dbs"
export FAKE_HOME="$WORK/home" DBFILE

cat > "$BIN/docker" <<'EOF'
#!/usr/bin/env bash
# docker exec mybaze.postgres-test psql ... | dropdb ... NAME
[ "$1" = exec ] && [ "$2" = mybaze.postgres-test ] || { echo "unexpected docker call: $*" >&2; exit 9; }
case "$3" in
  psql) cat "$DBFILE" ;;
  dropdb) db="${!#}"; grep -vx -- "$db" "$DBFILE" > "$DBFILE.new" || true; mv "$DBFILE.new" "$DBFILE" ;;
  *) exit 9 ;;
esac
EOF

write_ssh() {
  cat > "$BIN/ssh" <<EOF
#!/usr/bin/env bash
$1
EOF
  chmod +x "$BIN/ssh" "$BIN/docker"
}

# The working fake: run the "bash -lc SCRIPT" argument locally, without a login shell, so the
# fake docker stays first on PATH.
# shellcheck disable=SC2016  # expands inside the fake ssh, not here
LOCAL_SSH='last="${!#}"; eval "set -- $last"; HOME="$FAKE_HOME" exec bash -c "$3"'

run() { PATH="$BIN:$PATH" "$PYTHON" "$SCRIPT" "$@"; }

# 1. The remote name matches mybaze's remote_name for a real worktree, with or without test_.
write_ssh "$LOCAL_SSH"
out=$(MYBAZE_SUITE_REMOTE='' run inspect "$NAME")
[ "$(field remote_name <<<"$out")" = "$REMOTE" ] || fail "remote name: $out"
out=$(MYBAZE_SUITE_REMOTE='' run inspect "test_$NAME")
[ "$(field remote_name <<<"$out")" = "$REMOTE" ] || fail "remote name with test_: $out"
ok "remote name matches mybaze's offload.remote_name"

# 2. Unset or empty: skipped, and ssh is never called.
write_ssh 'echo called > "'"$WORK"'/ssh-called"; exit 1'
out=$(env -u MYBAZE_SUITE_REMOTE PATH="$BIN:$PATH" "$PYTHON" "$SCRIPT" inspect "$NAME")
[ "$(field status <<<"$out")" = skipped ] || fail "unset: $out"
out=$(MYBAZE_SUITE_REMOTE=" " run remove "$NAME")
[ "$(field status <<<"$out")" = skipped ] || fail "empty: $out"
[ ! -e "$WORK/ssh-called" ] || fail "ssh was called while the variable was unset"
ok "unset or empty MYBAZE_SUITE_REMOTE skips without contacting anything"

# 3. A login that prints a browser check URL and waits ends at the timeout, unopened.
write_ssh 'echo "To authenticate, visit: https://login.tailscale.com/a/abc123" >&2; sleep 30'
start=$(date +%s)
out=$(MYBAZE_SUITE_REMOTE=pc run inspect "$NAME" --timeout 2)
[ $(( $(date +%s) - start )) -lt 10 ] || fail "browser check was not bounded"
[ "$(field status <<<"$out")" = unreachable ] || fail "browser check: $out"
grep -q 'browser login check' <<<"$out" || fail "browser check detail: $out"
grep -q 'login.tailscale.com' <<<"$out" && fail "the URL leaked into the result: $out"
ok "a browser login check is bounded, reported, and its URL not passed on"

# 4. ssh failing on its own is unreachable.
write_ssh 'echo "ssh: connect to host pc port 22: Connection refused" >&2; exit 255'
out=$(MYBAZE_SUITE_REMOTE=pc run remove "$NAME")
[ "$(field status <<<"$out")" = unreachable ] || fail "ssh 255: $out"
ok "an ssh failure is unreachable"

# 5. inspect lists the mirror and exactly its databases; remove drops only those.
write_ssh "$LOCAL_SSH"
MIRROR="$FAKE_HOME/mybaze-offload/$REMOTE"; mkdir -p "$MIRROR/sub" "$FAKE_HOME/mybaze-offload/mybaze_offload_000000000000"
printf '%s\n' postgres "test_$REMOTE" "test_${REMOTE}_gw0" "test_${REMOTE}_gw7" \
  "test_${REMOTE}_gwx" "test_${REMOTE}2" test_mybaze_offload_000000000000 > "$DBFILE"
out=$(MYBAZE_SUITE_REMOTE=pc run inspect "$NAME")
[ "$(field status <<<"$out")" = present ] || fail "inspect: $out"
[ "$(field databases <<<"$out")" = "[\"test_$REMOTE\", \"test_${REMOTE}_gw0\", \"test_${REMOTE}_gw7\"]" ] || fail "inspect databases: $out"
ok "inspect finds the mirror and exactly its databases"

# 6. A pytest whose working directory is in the mirror makes both commands touch nothing.
(cd "$MIRROR/sub" && exec -a pytest sleep 30) &
SLEEPER=$!
sleep 0.5
out=$(MYBAZE_SUITE_REMOTE=pc run remove "$NAME")
[ "$(field status <<<"$out")" = busy ] || fail "busy: $out"
if [ ! -d "$MIRROR" ] || ! grep -qx "test_$REMOTE" "$DBFILE"; then fail "a busy mirror was touched"; fi
kill "$SLEEPER"; wait "$SLEEPER" 2>/dev/null || true; SLEEPER=""
ok "a live run in the mirror leaves everything in place"

out=$(MYBAZE_SUITE_REMOTE=pc run remove "$NAME")
[ "$(field status <<<"$out")" = removed ] || fail "remove: $out"
[ "$(field dropped <<<"$out")" = "[\"test_$REMOTE\", \"test_${REMOTE}_gw0\", \"test_${REMOTE}_gw7\"]" ] || fail "dropped: $out"
[ ! -e "$MIRROR" ] || fail "mirror still there"
[ -d "$FAKE_HOME/mybaze-offload/mybaze_offload_000000000000" ] || fail "another mirror was removed"
[ "$(tr '\n' ' ' < "$DBFILE")" = "postgres test_${REMOTE}_gwx test_${REMOTE}2 test_mybaze_offload_000000000000 " ] || fail "wrong databases left: $(cat "$DBFILE")"
ok "remove deletes the mirror and drops only its databases"

out=$(MYBAZE_SUITE_REMOTE=pc run inspect "$NAME")
[ "$(field status <<<"$out")" = absent ] || fail "after remove: $out"
ok "inspect reports absent afterwards"

[ ! -d "$ROOT/plugins/git/skills/wrap-up/scripts/__pycache__" ] || fail "the script left __pycache__ in the plugin"
ok "the script left no __pycache__ in the plugin"
