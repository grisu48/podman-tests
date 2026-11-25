# SPDX-License-Identifier: MIT
# Rootless smoke test: drop privilege and run one container.

rootless_user() {
  if [ "$SKIP_ROOTLESS" -eq 1 ]; then skip "--skip-rootless"; return 1; fi
  local u="$ROOTLESS_USER"
  [ -n "$u" ] || u="${SUDO_USER:-}"
  if [ -z "$u" ] || ! id "$u" >/dev/null 2>&1; then
    skip "no rootless user could be determined; pass --rootless-user"
    return 1
  fi
  if ! command -v newuidmap >/dev/null 2>&1 || ! grep -q "^${u}:" /etc/subuid 2>/dev/null || ! grep -q "^${u}:" /etc/subgid 2>/dev/null; then
    skip "user '$u' has no subordinate id range, or newuidmap is missing"
    return 1
  fi
  if [ "$RUNTIME" = docker ] && ! su - "$u" -c 'systemctl --user status docker.service' >/dev/null 2>&1; then
    skip "rootless docker is not configured for user '$u'"
    return 1
  fi
  ROOTLESS_RESOLVED_USER=$u
  return 0
}

test_rootless_run_and_mode() {
  rootless_user || return 0
  local u=$ROOTLESS_RESOLVED_USER out st
  LAST_CMD="su - $u -c '$RUNTIME run --rm $IMAGE_BUSYBOX echo cetest-rootless-ok'"
  if out=$(su - "$u" -c "$RUNTIME run --rm $IMAGE_BUSYBOX echo cetest-rootless-ok" 2>&1); then st=0; else st=$?; fi
  LAST_OUT=$out
  assert_ok "rootless run exits 0" "$st" || return 1
  assert_contains "known string received" cetest-rootless-ok "$out" || return 1

  out=$(su - "$u" -c "$RUNTIME info --format '{{.Host.Security.Rootless}}'" 2>&1) || true
  [[ $out == *true* ]] || out=$(su - "$u" -c "$RUNTIME info" 2>&1) || true
  LAST_OUT=$out
  if [[ $out != *true* && $out != *[Rr]ootless* ]]; then
    fail_result "engine reports rootless mode" "true/rootless" "$out"
    return 1
  fi
}

test_rootless_userns_mapping() {
  rootless_user || return 0
  local u=$ROOTLESS_RESOLVED_USER c uid raw pid owner
  c=$(rname rootless-map); track container "$c"
  LAST_CMD="su - $u -c '$RUNTIME run --rm $IMAGE_BUSYBOX id -u'"
  uid=$(su - "$u" -c "$RUNTIME run --rm $IMAGE_BUSYBOX id -u" 2>/dev/null)
  LAST_OUT=$uid
  assert_eq "effective uid inside is 0" 0 "$uid" || return 1
  LAST_CMD="su - $u -c '$RUNTIME run -d --name $c $IMAGE_BUSYBOX sleep 10'"
  su - "$u" -c "$RUNTIME run -d --name $c $IMAGE_BUSYBOX sleep 10" >/dev/null 2>&1 || true
  pid=$(su - "$u" -c "$RUNTIME inspect $c --format '{{.State.Pid}}'" 2>/dev/null) || true
  owner=$(ps -o user= -p "$pid" 2>/dev/null | tr -d ' ') || true
  su - "$u" -c "$RUNTIME rm -f $c" >/dev/null 2>&1 || true
  LAST_OUT="host process pid $pid owned by '$owner'"
  assert_eq "host process owned by the unprivileged user" "$u" "$owner" || return 1
}
