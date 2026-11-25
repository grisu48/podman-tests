# SPDX-License-Identifier: MIT
# Container lifecycle: create, start, pause/unpause, stop, destroy.

test_lifecycle() {
  local c; c=$(rname lifecycle); track container "$c"
  engine create --name "$c" "$IMAGE_BUSYBOX" sleep 300
  assert_ok "create" "$LAST_STATUS" || return 1
  engine inspect "$c" --format '{{.State.Status}}'
  assert_eq "state after create" created "$LAST_OUT" || return 1
  engine ps -a --filter "name=^${c}\$" --format '{{.Names}}'
  assert_contains "addressable by name" "$c" "$LAST_OUT" || return 1

  engine start "$c"
  assert_ok "start" "$LAST_STATUS" || return 1
  wait_for_state "$c" running 10 || { fail_result "started" running "$LAST_OUT"; return 1; }
  engine exec "$c" true
  assert_ok "exec in running container" "$LAST_STATUS" || return 1

  engine stop -t 5 "$c"
  assert_ok "stop" "$LAST_STATUS" || return 1
  engine inspect "$c" --format '{{.State.Status}}'
  [ "$LAST_OUT" != running ] || { fail_result "stopped state" "not running" "$LAST_OUT"; return 1; }
  engine ps -a --filter "name=^${c}\$" --format '{{.Names}}'
  assert_contains "still listed when stopped" "$c" "$LAST_OUT" || return 1
  engine stop -t 5 "$c"
  assert_ok "second stop is harmless" "$LAST_STATUS" || return 1

  engine rm "$c"
  assert_ok "remove stopped" "$LAST_STATUS" || return 1
  engine inspect "$c"
  assert_fail "inspect after removal" "$LAST_STATUS" || return 1
}

test_remove_running_requires_force() {
  local c; c=$(rname lifecycle-rm-running); track container "$c"
  run_bg "$c" "$IMAGE_BUSYBOX" sleep 300 || { fail_result "precondition running" running "$LAST_OUT"; return 1; }
  engine rm "$c"
  assert_fail "remove running without force" "$LAST_STATUS" || return 1
  engine inspect "$c" --format '{{.State.Status}}'
  assert_eq "still running" running "$LAST_OUT" || return 1
  engine rm -f "$c"
  assert_ok "forced remove" "$LAST_STATUS" || return 1
}

test_pause_unpause() {
  if ! have_freezer; then skip "no cgroup freezer on this host"; return 0; fi
  local c; c=$(rname lifecycle-pause); track container "$c"
  run_bg "$c" "$IMAGE_BUSYBOX" sleep 300 || { fail_result "precondition running" running "$LAST_OUT"; return 1; }
  engine pause "$c"
  if [ "$LAST_STATUS" -ne 0 ]; then skip "pause not supported: $LAST_OUT"; return 0; fi
  wait_for_state "$c" paused 5 || { fail_result "paused" paused "$LAST_OUT"; return 1; }
  engine unpause "$c"
  assert_ok "unpause" "$LAST_STATUS" || return 1
  wait_for_state "$c" running 5 || { fail_result "unpaused" running "$LAST_OUT"; return 1; }
  engine exec "$c" true
  assert_ok "exec after unpause" "$LAST_STATUS" || return 1
}

test_exit_code_propagation() {
  engine run --rm "$IMAGE_BUSYBOX" sh -c 'exit 0'
  assert_eq "exit 0 propagated" 0 "$LAST_STATUS" || return 1
  engine run --rm "$IMAGE_BUSYBOX" sh -c 'exit 42'
  assert_eq "exit 42 propagated" 42 "$LAST_STATUS" || return 1
}
