#!/bin/bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Felix Niederwanger
#
# Storage: named volumes, persistence, bind mounts and volume removal.

test_volume_create() {
	local v
	v=$(mkname sto-vol)
	quiet volume create "$v"
	eng volume ls --format '{{.Name}}'
	assert_match "$v" "$LAST_OUT" "created volume is listed"
	quiet volume rm "$v"
}

test_volume_attach_write() {
	local v
	v=$(mkname sto-vol2)
	quiet volume create "$v"
	add_cleanup volume "$v"
	assert_ok "the mount point is writable and a real mount" \
		engine run --rm --mount "type=volume,src=$v,dst=/data" "$IMAGE_BUSYBOX" \
			sh -c 'echo -n payload > /data/hello && mount | grep " on /data "'
}

test_volume_persistence() {
	local v w
	v=$(mkname sto-vol3)
	w=$(mkname sto-writer)
	quiet volume create "$v"
	add_cleanup volume "$v"
	eng run --name "$w" --mount "type=volume,src=$v,dst=/data" "$IMAGE_BUSYBOX" \
		sh -c 'echo -n payload > /data/hello'
	add_cleanup container "$w"
	assert_ok "removing the writing container" "$RUNTIME" rm "$w"
	# Same volume, same path: the content survives the writer.
	eng run --rm --mount "type=volume,src=$v,dst=/data" "$IMAGE_BUSYBOX" cat /data/hello
	assert_eq payload "$LAST_OUT" "content survives the writing container"
	# Same volume, different path: the file is found, unchanged.
	eng run --rm --mount "type=volume,src=$v,dst=/other" "$IMAGE_BUSYBOX" cat /data/hello
	assert_eq payload "$LAST_OUT" "content is independent of the mount path"
}

test_bind_mount() {
	local d
	d=$(new_bind_dir)
	echo -n planted > "$d/known.txt"
	eng run --rm --mount "type=bind,src=$d,dst=/data" "$IMAGE_BUSYBOX" \
		sh -c 'cat /data/known.txt && echo -n written > /data/from-container'
	assert_match planted "$LAST_OUT" "host file is readable inside the container"
	assert_eq written "$(cat "$d/from-container")" \
		"container write is visible on the host"
}

test_bind_mount_readonly() {
	local d
	d=$(new_bind_dir)
	echo -n planted > "$d/known.txt"
	assert_fail "a write into a read-only bind mount fails" \
		engine run --rm --mount "type=bind,src=$d,dst=/data,ro" "$IMAGE_BUSYBOX" \
			sh -c 'echo x > /data/newfile'
	assert_eq 0 "$(ls "$d" | grep -c newfile)" \
		"the host directory is unchanged"
}

test_volume_removal() {
	local v u
	v=$(mkname sto-vol4)
	u=$(mkname sto-user)
	quiet volume create "$v"
	add_cleanup volume "$v"
	RUNFLAGS=(--mount "type=volume,src=$v,dst=/data")
	start_bg "$u" sleep 300	assert_fail "removal while in use is refused" "$RUNTIME" volume rm "$v"
	eng volume ls --format '{{.Name}}'
	assert_match "$v" "$LAST_OUT" "the volume is still listed while in use"
	quiet rm -f "$u"
	assert_ok "removal succeeds once the volume is free" "$RUNTIME" volume rm "$v"
	eng volume ls --format '{{.Name}}'
	assert_not_grep "$v" "$LAST_OUT" "the removed volume is no longer listed"
}
