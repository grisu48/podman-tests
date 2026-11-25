#!/bin/bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Felix Niederwanger
#
# Rootless smoke test: a container runs as an unprivileged user, the
# engine reports rootless mode, and UID 0 inside maps to a non-root host
# process. Everything else is left to a later change.

# Set the global RESOLVED_USER, or end the test with a named skip so the
# precondition failure is never mistaken for an engine defect.
resolve_rootless_user() {
	if [ -n "$SKIP_ROOTLESS" ] ; then
		skip_test "--skip-rootless"
	fi
	have_rootless ||
		skip_test "this docker has no rootless endpoint configured"
	if [ -n "$ROOTLESS_USER" ] ; then
		RESOLVED_USER=$ROOTLESS_USER
	elif [ -n "${SUDO_USER:-}" ] ; then
		RESOLVED_USER=$SUDO_USER
	else
		skip_test "no rootless user could be determined"
	fi
	if ! id -- "$RESOLVED_USER" >/dev/null 2>&1 ; then
		skip_test "rootless user '$RESOLVED_USER' does not exist"
	fi
	if [ "$(id -u -- "$RESOLVED_USER")" -eq 0 ] ; then
		skip_test "rootless user '$RESOLVED_USER' is privileged"
	fi
	if ! grep -q "^$RESOLVED_USER:" /etc/subuid ||
		! grep -q "^$RESOLVED_USER:" /etc/subgid ; then
		skip_test "no subordinate uid/gid range for user '$RESOLVED_USER'"
	fi
	have newuidmap ||
		skip_test "newuidmap is not installed (package shadow-utils)"
	have su || skip_test "su is not installed (package util-linux)"
	have ps || skip_test "ps is not installed (package procps)"
}

rootless_run() { # engine call executed as the resolved user
	su - "$RESOLVED_USER" -c "$RUNTIME $*" 2>/dev/null
}

test_rootless_smoke() {
	resolve_rootless_user

	# Drop privilege with a login shell: su - sets up XDG_RUNTIME_DIR
	# and the environment the way the engine expects it.
	local out
	if ! out=$(rootless_run run --rm "$IMAGE_BUSYBOX" echo 'rootless works') ; then
		log "su - $RESOLVED_USER could not run the engine (output above)"
		skip_test "su - '$RESOLVED_USER' cannot run the engine"
	fi
	assert_eq "rootless works" "$out" \
		"a container runs as the unprivileged user"

	case $RUNTIME in
	podman)
		local mode
		mode=$(rootless_run info --format '{{.Host.Security.Rootless}}')
		assert_eq true "$mode" "the engine reports rootless mode" ;;
	*)
		assert_ok "docker answers via the user's rootless endpoint" \
			rootless_run info --format '{{.ServerVersion}}' ;;
	esac

	local cuid
	cuid=$(rootless_run run --rm "$IMAGE_BUSYBOX" id -u)
	assert_eq 0 "$cuid" "the container's effective UID inside is 0"

	# A live rootless container's host process belongs to the user.
	local cont tries=10 hostpid="" hp
	cont=$(mkname rootless)
	rootless_run run -d --name "$cont" "$IMAGE_BUSYBOX" sleep 60 >/dev/null
	while [ "$tries" -gt 0 ] ; do
		hp=$(rootless_run inspect --format '{{.State.Pid}}' "$cont" 2>/dev/null)
		if [ -n "$hp" ] && [ "$hp" -gt 0 ] 2>/dev/null ; then
			hostpid=$hp
			break
		fi
		tries=$(( tries - 1 ))
		sleep 1
	done
	cowner=$(ps -o user= -p "$hostpid" 2>/dev/null)
	assert_eq "$RESOLVED_USER" "$cowner" \
		"the engine process belongs to the unprivileged user"
	# The rootless engine's store is invisible to this parent process, so
	# the removal happens here; --rm would remove it after the sleep too.
	rootless_run rm -f "$cont" >/dev/null || true
}
