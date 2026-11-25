# SPDX-License-Identifier: MIT
# Named volumes and host bind mounts.

test_volume_create_and_mount() {
  local v c; v=$(rname vol); track volume "$v"; c=$(rname vol-w); track container "$c"
  engine volume create "$v"
  assert_ok "volume create" "$LAST_STATUS" || return 1
  engine volume ls --format '{{.Name}}'
  assert_contains "volume listed" "$v" "$LAST_OUT" || return 1
  engine run --name "$c" -v "$v:/data" "$IMAGE_BUSYBOX" sh -c 'echo hello > /data/f'
  assert_ok "write into mounted volume" "$LAST_STATUS" || return 1
  engine run --rm -v "$v:/data" "$IMAGE_BUSYBOX" sh -c 'mount | grep -q " /data "'
  assert_ok "mount point is a mount" "$LAST_STATUS" || return 1
}

test_volume_persistence() {
  local v w; v=$(rname vol-p); track volume "$v"; w=$(rname vol-p-w); track container "$w"
  engine volume create "$v"
  engine run --name "$w" -v "$v:/data" "$IMAGE_BUSYBOX" sh -c 'echo known-content > /data/f'
  assert_ok "write" "$LAST_STATUS" || return 1
  engine rm -f "$w"
  engine run --rm -v "$v:/data" "$IMAGE_BUSYBOX" cat /data/f
  assert_eq "readback after writer removed" known-content "$LAST_OUT" || return 1
  engine run --rm -v "$v:/other" "$IMAGE_BUSYBOX" cat /other/f
  assert_eq "readback at a different path" known-content "$LAST_OUT" || return 1
}

test_bind_mount() {
  local dir; dir=$(mktemp -d "/tmp/${PREFIX}bind.XXXXXX")
  echo known-content > "$dir/f"
  engine run --rm -v "$dir:/data:ro" "$IMAGE_BUSYBOX" cat /data/f
  assert_eq "host file readable inside" known-content "$LAST_OUT" || { rm -rf "$dir"; return 1; }
  engine run --rm -v "$dir:/data" "$IMAGE_BUSYBOX" sh -c 'echo written > /data/g'
  assert_ok "container write succeeds" "$LAST_STATUS" || { rm -rf "$dir"; return 1; }
  assert_eq "write visible on host" written "$(cat "$dir/g" 2>/dev/null)" || { rm -rf "$dir"; return 1; }
  engine run --rm -v "$dir:/data:ro" "$IMAGE_BUSYBOX" sh -c 'echo nope > /data/h'
  assert_fail "write into read-only mount fails" "$LAST_STATUS" || { rm -rf "$dir"; return 1; }
  if [ -e "$dir/h" ]; then fail_result "host unchanged" "no h file" "h file exists"; rm -rf "$dir"; return 1; fi
  rm -rf "$dir"
}

test_volume_removal() {
  local v c; v=$(rname vol-rm); track volume "$v"; c=$(rname vol-rm-c); track container "$c"
  engine volume create "$v"
  run_bg "$c" -v "$v:/data" "$IMAGE_BUSYBOX" sleep 300 || { fail_result "precondition running" running "$LAST_OUT"; return 1; }
  engine volume rm "$v"
  assert_fail "removal refused while in use" "$LAST_STATUS" || return 1
  engine rm -f "$c"
  engine volume rm "$v"
  assert_ok "removal once unused" "$LAST_STATUS" || return 1
  engine volume ls --format '{{.Name}}'
  if printf '%s\n' "$LAST_OUT" | grep -qxF "$v"; then
    fail_result "removed from listing" "absent" "present"
    return 1
  fi
}
