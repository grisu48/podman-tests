#!/bin/bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Felix Niederwanger
#
# SELinux: process labels, relabelled and unlabelled bind mounts, and
# label disabling. Runs only on an enforcing host with an engine that
# labels containers.

selinux_precondition() {
	[ -r /sys/fs/selinux/enforce ] ||
		skip_test "SELinux is not available on this host"
	[ "$(cat /sys/fs/selinux/enforce)" = 1 ] ||
		skip_test "SELinux is permissive, so denials cannot be asserted"
	have_selinux ||
		skip_test "the engine reports its SELinux support as disabled"
}

ctx_field() { # <line> <field> — awk -F:
	awk -F: -v f="$2" '{ print $f }' <<<"$1"
}

test_selinux_container_domain() {
	selinux_precondition
	engine run --rm "$IMAGE_TUMBLEWEED" cat /proc/self/attr/current
	local ctx type
	ctx=$LAST_OUT
	assert_match '^[^:]+:[^:]+:[^:]+:[^:]+$' "$ctx" \
		"container process reports a complete SELinux context"
	type=$(ctx_field "$ctx" 3)
	assert_eq container_t "$type" "the domain is a container type"
}

test_selinux_mcs_separation() {
	selinux_precondition
	local c1 c2 k1 k2
	c1=$(mkname sel-mcs1)
	c2=$(mkname sel-mcs2)
	eng run -d --name "$c1" "$IMAGE_TUMBLEWEED" sleep 120
	add_cleanup container "$c1"
	eng run -d --name "$c2" "$IMAGE_TUMBLEWEED" sleep 120
	add_cleanup container "$c2"
	eng exec "$c1" cat /proc/self/attr/current
	k1=$(ctx_field "$LAST_OUT" 4)
	eng exec "$c2" cat /proc/self/attr/current
	k2=$(ctx_field "$LAST_OUT" 4)
	assert_not_eq "$k1" "$k2" \
		"two containers carry different MCS category sets"
}

test_selinux_relabelled_mount() {
	selinux_precondition
	local d
	d=$(new_bind_dir)
	echo -n planted > "$d/known.txt"
	assert_ok "the relabelled mount is readable and writable" \
		engine run --rm --volume "$d:/data:Z" "$IMAGE_TUMBLEWEED" \
			sh -c 'cat /proc/self/attr/current; cat /data/known.txt; echo -n written > /data/note.txt'
	# the first line of output is the container's context, the second is
	# the body of the file read through the mount
	local seen mcs
	seen=$LAST_OUT
	assert_eq planted "$(tail -n 1 <<<"$seen")" "relabelled mount is readable"
	mcs=$(ctx_field "$(head -n 1 <<<"$seen")" 4)
	log "container categories: $mcs"
	local hostctx
	hostctx=$(ls -Zd "$d")
	assert_match container_file_t "$hostctx" "host type after :Z is a container type"
	assert_match "$mcs" "$hostctx" "host context carries the container's categories"
	rm -rf "$d"
}

test_selinux_unlabelled_denied() {
	selinux_precondition
	local d before
	d=$(new_bind_dir)
	echo -n planted > "$d/known.txt"
	before=$(ls -Zd "$d")
	assert_fail "a read without a label is denied" \
		engine run --rm --volume "$d:/data" "$IMAGE_TUMBLEWEED" cat /data/known.txt
	assert_eq "$before" "$(ls -Zd "$d")" \
		"the host context is unchanged by the denied access"
	rm -rf "$d"
}

test_selinux_label_separation() {
	selinux_precondition
	local d
	d=$(new_bind_dir)
	echo -n planted > "$d/known.txt"
	# Relabel for one container, then read from another: denied.
	assert_ok "the relabelled read succeeds for its own container" \
		engine run --rm --volume "$d:/data:Z" "$IMAGE_TUMBLEWEED" \
			sh -c 'cat /data/known.txt >/dev/null'
	assert_fail "another container with other categories is denied" \
		engine run --rm --volume "$d:/data" "$IMAGE_TUMBLEWEED" cat /data/known.txt
	rm -rf "$d"
}

test_selinux_disabled() {
	selinux_precondition
	local d
	d=$(new_bind_dir)
	echo -n planted > "$d/known.txt"
	engine run --rm --security-opt label=disable \
		--volume "$d:/data" "$IMAGE_TUMBLEWEED" cat /proc/self/attr/current
	local type
	type=$(ctx_field "$LAST_OUT" 3)
	assert_not_eq container_t "$type" \
		"label disabling gives an unconfined domain"
	engine run --rm --security-opt label=disable \
		--volume "$d:/data" "$IMAGE_TUMBLEWEED" cat /data/known.txt
	assert_eq planted "$LAST_OUT" "the read succeeds without separation"
	rm -rf "$d"
}
