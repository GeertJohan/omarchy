echo "Install the fingerprint resume hook on existing fingerprint setups"

# omarchy-setup-security-fingerprint gained a system-sleep hook that restarts
# fprintd on resume, so a verify wedged by suspend cannot leave the reader dead
# on the lock screen. New setups install it; a machine that enrolled a finger
# before the hook existed never re-runs setup, so drop it in here.

hook_src="${OMARCHY_FPRINTD_RESUME_SRC:-$OMARCHY_PATH/default/systemd/system-sleep/fprintd-resume}"
hook_dst="${OMARCHY_FPRINTD_RESUME_DST:-/usr/lib/systemd/system-sleep/fprintd-resume}"
timeout_src="${OMARCHY_FPRINTD_STOP_TIMEOUT_SRC:-$OMARCHY_PATH/default/systemd/system/fprintd.service.d/stop-timeout.conf}"
timeout_dst="${OMARCHY_FPRINTD_STOP_TIMEOUT_DST:-/etc/systemd/system/fprintd.service.d/stop-timeout.conf}"
lock_pam="${OMARCHY_LOCK_FINGERPRINT_PAM:-/etc/pam.d/omarchy-lock-fingerprint}"

# Only where fingerprint is configured.
[[ -f $lock_pam ]] || exit 0

# Each half is guarded on its own: a machine that already took the hook still
# needs the cap. Only install what is absent -- an existing copy may be newer
# or hand-edited, so leave it alone. install -Dm755 sets the executable bit
# explicitly, which systemd-sleep requires to run the hook.
if [[ -f $hook_src && ! -e $hook_dst ]]; then
  echo "Installing the fprintd resume hook"
  sudo install -Dm755 "$hook_src" "$hook_dst"
fi

# The hook restarts fprintd while sessions are frozen, and a wedged fprintd
# ignores SIGTERM, so without this cap the recovery costs more than the bug.
if [[ -f $timeout_src && ! -e $timeout_dst ]]; then
  echo "Capping the fprintd stop timeout"
  sudo install -Dm644 "$timeout_src" "$timeout_dst"
  sudo systemctl daemon-reload
fi
