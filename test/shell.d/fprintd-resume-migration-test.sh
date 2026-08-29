#!/bin/bash

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

migration=$(grep -rl 'Install the fingerprint resume hook on existing fingerprint setups' "$ROOT/migrations" | head -n 1 || true)
[[ -n $migration ]] || fail "fprintd resume hook migration exists"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# The migration installs to a system path via sudo; stub it so the test writes
# into a temp tree instead of /usr.
stub_bin="$TMPDIR/bin"
mkdir -p "$stub_bin"
cat >"$stub_bin/sudo" <<'STUB'
#!/bin/bash
exec "$@"
STUB
chmod +x "$stub_bin/sudo"

# The migration reloads systemd after dropping the cap in. Record the call
# instead of reloading the machine running the test.
cat >"$stub_bin/systemctl" <<STUB
#!/bin/bash
printf '%s\\n' "\$*" >>"$TMPDIR/systemctl.log"
STUB
chmod +x "$stub_bin/systemctl"

src="$TMPDIR/fprintd-resume"
printf '#!/bin/bash\n' >"$src"
chmod +x "$src"
dst="$TMPDIR/system-sleep/fprintd-resume"
timeout_dst="$TMPDIR/fprintd.service.d/stop-timeout.conf"
lock_pam="$TMPDIR/omarchy-lock-fingerprint"

# omarchy-migrate runs each migration with `bash -euo pipefail`; match it.
run_migration() {
  PATH="$stub_bin:$PATH" \
    OMARCHY_PATH="$ROOT" \
    OMARCHY_FPRINTD_RESUME_SRC="$src" \
    OMARCHY_FPRINTD_RESUME_DST="$dst" \
    OMARCHY_FPRINTD_STOP_TIMEOUT_DST="$timeout_dst" \
    OMARCHY_LOCK_FINGERPRINT_PAM="$lock_pam" \
    bash -euo pipefail "$migration" >/dev/null ||
    fail "migration exits clean"
}

# The migration exits clean when its source is missing, so a hook moved
# without updating it would silently install nothing and mark itself done.
# Run once against the real default source under the repo to pin that path.
rm -rf "$TMPDIR/system-sleep" "$TMPDIR/fprintd.service.d"
: >"$lock_pam"
: >"$TMPDIR/systemctl.log"
PATH="$stub_bin:$PATH" \
  OMARCHY_PATH="$ROOT" \
  OMARCHY_FPRINTD_RESUME_DST="$dst" \
  OMARCHY_FPRINTD_STOP_TIMEOUT_DST="$timeout_dst" \
  OMARCHY_LOCK_FINGERPRINT_PAM="$lock_pam" \
  bash -euo pipefail "$migration" >/dev/null ||
  fail "migration exits clean from its default source"
[[ -x $dst ]] || fail "migration finds the hook at its default source path" "dst: $(stat -c '%A' "$dst" 2>/dev/null || echo missing)"
cmp -s "$dst" "$ROOT/default/systemd/system-sleep/fprintd-resume" || fail "migration installs the shipped hook from its default source"
pass "migration installs the shipped hook from its default source"

# The cap has the same failure mode as the hook: moved without updating the
# migration, it would silently install nothing and still mark itself done.
[[ -f $timeout_dst ]] ||
  fail "migration finds the stop timeout at its default source path" "dst: $(stat -c '%A' "$timeout_dst" 2>/dev/null || echo missing)"
cmp -s "$timeout_dst" "$ROOT/default/systemd/system/fprintd.service.d/stop-timeout.conf" ||
  fail "migration installs the shipped stop timeout from its default source"
[[ $(stat -c '%a' "$timeout_dst") == 644 ]] ||
  fail "migration installs the stop timeout world-readable, not executable" "mode: $(stat -c '%a' "$timeout_dst")"
grep -qx 'daemon-reload' "$TMPDIR/systemctl.log" ||
  fail "migration reloads systemd so the cap takes effect" "systemctl: $(<"$TMPDIR/systemctl.log")"
pass "migration installs the shipped stop timeout and reloads systemd"

# A machine with fingerprint configured but no hook yet gets it, executable.
: >"$lock_pam"
rm -rf "$TMPDIR/system-sleep"
run_migration
[[ -x $dst ]] || fail "migration installs the hook, executable" "dst: $(stat -c '%A' "$dst" 2>/dev/null || echo missing)"
pass "migration installs the hook, executable"

# Running twice must not fail (the hook now exists) and must not touch it.
printf 'sentinel\n' >>"$dst"
printf 'sentinel\n' >>"$timeout_dst"
: >"$TMPDIR/systemctl.log"
run_migration
grep -q sentinel "$dst" || fail "migration leaves an existing hook alone"
pass "migration leaves an existing hook alone"

grep -q sentinel "$timeout_dst" || fail "migration leaves an existing stop timeout alone"
[[ ! -s $TMPDIR/systemctl.log ]] ||
  fail "migration does not reload systemd when it changed nothing" "systemctl: $(<"$TMPDIR/systemctl.log")"
pass "migration leaves an existing stop timeout alone"

# The whole reason each half is guarded separately: a machine that took the
# hook on an earlier run still has no cap, and must get one.
rm -f "$timeout_dst"
: >"$TMPDIR/systemctl.log"
run_migration
[[ -f $timeout_dst ]] || fail "migration adds the cap to a machine that already has the hook"
grep -q sentinel "$dst" || fail "migration adds the cap without disturbing the hook"
grep -qx 'daemon-reload' "$TMPDIR/systemctl.log" ||
  fail "migration reloads systemd after adding the cap" "systemctl: $(<"$TMPDIR/systemctl.log")"
pass "migration adds the cap to a machine that already has the hook"

# No fingerprint configured -> nothing to fix, so nothing is installed.
rm -f "$lock_pam"
rm -rf "$TMPDIR/system-sleep" "$TMPDIR/fprintd.service.d"
run_migration
[[ ! -e $dst ]] || fail "migration skips machines without fingerprint configured"
[[ ! -e $timeout_dst ]] || fail "migration skips the cap without fingerprint configured"
pass "migration skips machines without fingerprint configured"
