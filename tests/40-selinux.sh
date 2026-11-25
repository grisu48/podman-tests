# SPDX-License-Identifier: MIT
# SELinux confinement: process labels, relabelled and unlabelled bind
# mounts, label separation, label disabling.

selinux_precondition() {
  if [ ! -r /sys/fs/selinux/enforce ]; then skip "selinux is not available on this host"; return 1; fi
  if [ "$(cat /sys/fs/selinux/enforce)" != "1" ]; then skip "selinux is permissive"; return 1; fi
  if ! have_selinux; then skip "engine selinux support is disabled"; return 1; fi
  return 0
}

test_selinux_process_label() {
  selinux_precondition || return 0
  local c1 c2 ctx1 ctx2; c1=$(rname selinux-1); track container "$c1"; c2=$(rname selinux-2); track container "$c2"
  engine run -d --name "$c1" "$IMAGE_BUSYBOX" sleep 300
  engine run -d --name "$c2" "$IMAGE_BUSYBOX" sleep 300
  wait_for_state "$c1" running 10 || { fail_result "c1 running" running "$LAST_OUT"; return 1; }
  wait_for_state "$c2" running 10 || { fail_result "c2 running" running "$LAST_OUT"; return 1; }
  engine exec "$c1" cat /proc/self/attr/current; ctx1=$LAST_OUT
  engine exec "$c2" cat /proc/self/attr/current; ctx2=$LAST_OUT
  assert_match "complete context with a container type" '^[a-z0-9_]+:[a-z0-9_]+:container_[a-z0-9_]*t:' "$ctx1" || return 1
  if [ "${ctx1#*:*:*:}" = "${ctx2#*:*:*:}" ]; then
    fail_result "different MCS categories" "distinct category sets" "$ctx1 == $ctx2"
    return 1
  fi
}

test_selinux_relabel_and_separation() {
  selinux_precondition || return 0
  local dir c1 ctr_ctx ctr_cat host_ctx
  dir=$(mktemp -d "/tmp/${PREFIX}selinux.XXXXXX")
  c1=$(rname selinux-relabel); track container "$c1"
  echo known-content > "$dir/f"

  engine run --name "$c1" -v "$dir:/data:Z" "$IMAGE_BUSYBOX" sh -c 'cat /data/f && echo more >> /data/f && cat /proc/self/attr/current'
  assert_ok "read and write with :Z" "$LAST_STATUS" || { rm -rf "$dir"; return 1; }
  ctr_ctx=${LAST_OUT##*$'\n'}
  ctr_cat=${ctr_ctx#*:*:*:}
  host_ctx=$(host_ctx "$dir")
  if [[ $host_ctx != *container_file_t* ]]; then
    fail_result "host relabelled to a container file type" "*container_file_t*" "$host_ctx"
    rm -rf "$dir"; return 1
  fi
  if [[ $host_ctx != *"$ctr_cat"* ]]; then
    fail_result "host carries the container's categories" "$ctr_cat" "$host_ctx"
    rm -rf "$dir"; return 1
  fi

  engine run --rm -v "$dir:/data" "$IMAGE_BUSYBOX" cat /data/f
  assert_fail "a second container without relabel is denied" "$LAST_STATUS" || { rm -rf "$dir"; return 1; }
  rm -rf "$dir"
}

test_selinux_unlabelled_denied() {
  selinux_precondition || return 0
  local dir before after
  dir=$(mktemp -d "/tmp/${PREFIX}selinux-deny.XXXXXX")
  echo known-content > "$dir/f"
  before=$(host_ctx "$dir")
  engine run --rm -v "$dir:/data" "$IMAGE_BUSYBOX" cat /data/f
  assert_fail "read without relabel is denied" "$LAST_STATUS" || { rm -rf "$dir"; return 1; }
  after=$(host_ctx "$dir")
  assert_eq "host context unchanged" "$before" "$after" || { rm -rf "$dir"; return 1; }
  rm -rf "$dir"
}

test_selinux_label_disabling() {
  selinux_precondition || return 0
  local dir ctx
  dir=$(mktemp -d "/tmp/${PREFIX}selinux-nolabel.XXXXXX")
  echo known-content > "$dir/f"
  engine run --rm --security-opt label=disable -v "$dir:/data" "$IMAGE_BUSYBOX" sh -c 'cat /data/f && cat /proc/self/attr/current'
  assert_ok "read succeeds with label disabled" "$LAST_STATUS" || { rm -rf "$dir"; return 1; }
  ctx=${LAST_OUT##*$'\n'}
  if [[ $ctx == *container_*_t* || $ctx == *container_t* ]]; then
    fail_result "container runs unconfined" "non-container type" "$ctx"
    rm -rf "$dir"; return 1
  fi
  rm -rf "$dir"
}
