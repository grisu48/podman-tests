#!/bin/bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Felix Niederwanger
#
# Lifecycle: create, start, pause, stop, exit codes and removal.

test_lifecycle_create() {
	local c
	c=$(mkname life-create)
	eng create --name "$c" "$IMAGE_BUSYBOX" sleep 300
	add_cleanup container "$c"
	eng inspect --format '{{.State.Status}}' "$c"
	assert_eq created "$LAST_OUT" "created container reports state 'created'"
	eng inspect --format '{{.State.Running}}' "$c"
	assert_eq false "$LAST_OUT" "created container is not running"
	eng inspect --format '{{.Name}}' "$c"
	assert_eq "$c" "${LAST_OUT#*/}" "created container is addressable by name"
	quiet rm -f "$c"
}

test_lifecycle_start() {
	local c
	c=$(mkname life-start)
	start_bg "$c" sleep 300
	assert_ok "exec inside a started container succeeds" engine exec "$c" true
	quiet rm -f "$c"
}

test_lifecycle_pause_unpause() {
	have_freezer || skip_test "the host offers no freezer for pause"
	local c
	c=$(mkname life-pause)
	start_bg "$c" sleep 300
	eng pause "$c"
	wait_for_state "$c" paused
	eng unpause "$c"
	wait_for_state "$c" running
	assert_ok "exec works again after unpause" engine exec "$c" true
	quiet rm -f "$c"
}

test_lifecycle_stop() {
	local c listed
	c=$(mkname life-stop)
	start_bg "$c" sleep 300
	eng stop "$c"
	wait_for_state "$c" exited
	eng ps --all --format '{{.Names}}'
	listed=$LAST_OUT
	assert_match "$c" "$listed" "stopped container is still listed"
	eng stop "$c"			# a second stop must be harmless
	eng inspect --format '{{.State.Status}}' "$c"
	assert_eq exited "$LAST_OUT" "second stop leaves the state unchanged"
	quiet rm -f "$c"
}

test_lifecycle_exit_codes() {
	engine run --rm "$IMAGE_BUSYBOX" true || true
	assert_eq 0 "$LAST_ST" "foreground exit code 0 propagates"
	engine run --rm "$IMAGE_BUSYBOX" sh -c 'exit 42' || true
	assert_eq 42 "$LAST_ST" "foreground exit code 42 propagates"
}

test_lifecycle_removal() {
	local c d
	# A stopped container is removed; a running one needs force.
	c=$(mkname life-rm)
	start_bg "$c" sleep 300
	assert_fail "unforced removal of a running container is refused" \
		engine rm "$c"
	eng inspect --format '{{.State.Status}}' "$c"
	assert_eq running "$LAST_OUT" "the container still runs"
	assert_ok "forced removal succeeds" engine rm -f "$c"
	eng ps --all --format '{{.Names}}'
	assert_not_grep "$c" "$LAST_OUT" "removed container is no longer listed"

	d=$(mkname life-rm2)
	eng create --name "$d" "$IMAGE_BUSYBOX" sleep 300
	assert_ok "removing a stopped container succeeds" engine rm "$d"
	assert_fail "a state query for a removed container fails" engine inspect "$d"
}
