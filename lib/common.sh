#!/bin/bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Felix Niederwanger
#
# Suite-wide library: logging, assertions, engine wrapper, probes and
# cleanup. Sourced by run-tests.sh, never executed directly.

# Declared tools -> providing package, for the ENVIRONMENT: wording.
declare -A PROVIDER=(
	[curl]=curl [grep]=grep [sed]=sed [awk]=gawk [id]=coreutils
	[mktemp]=coreutils [ls]=coreutils [ip]=iproute2 [su]=util-linux
	[date]=coreutils [sleep]=coreutils [head]=coreutils [tail]=coreutils
)
SUITE_TOOLS=(curl grep sed awk id mktemp ls ip date sleep head tail)
declare -a RESOURCES=()

# A test function runs in a subshell; its exit status classifies it:
# 0 pass, 99 skip ("SKIP <reason>" on stdout), otherwise failed.
# Diagnostics go to stderr; the runner attaches them to the result line.
log() { printf '# %s\n' "${TEST_NAME:-suite}: $*" >&2 ; }
have() { command -v "$1" >/dev/null 2>&1 ; }
die() { log "$*" ; exit 1 ; }        # fail the current test, evidence printed
skip_test() { echo "SKIP $*" ; exit 99 ; }

# engine: one single invocation (run is effectful); records the command,
# stdout (LAST_OUT), stderr (LAST_ERR) and status (LAST_ST).
engine() {
	local ef
	LAST_CMD="$RUNTIME $*"
	ef=$(mktemp "/tmp/${PREFIX}e-XXXXXX")
	LAST_OUT=$("$RUNTIME" "$@" 2>"$ef")
	LAST_ST=$?
	LAST_ERR=$(<"$ef")
	rm -f "$ef"
	return "$LAST_ST"
}

# eng: engine call whose failure fails the current test, with evidence.
# When the failure is a vanished image, the wording names it as an
# environment problem instead of a defect, per the image spec.
eng() {
	engine "$@" && return 0
	log "engine call failed: $RUNTIME $*"
	log "engine said: ${LAST_ERR:-<no output>}"
	if grep -qE 'no such image|not found on host|missing in local storage' \
		<<<"${LAST_ERR:-}" && last_image_ref "$@" ; then
		image_unavailable "$LAST_OUT" "${LAST_ERR:-}"
		die "image lost after preflight"
	fi
	die "engine call failed: $RUNTIME $*"
}

last_image_ref() {	# the first argument naming a configured image
	local a
	for a in "$@" ; do
		case $a in
		registry.opensuse.org/*) printf '%s' "$a" ; exit 0 ;;
		esac
	done
	exit 1
}

# Probes: the only places that may branch on the engine name.
have_selinux() {
	case $RUNTIME in
	docker)	engine info --format '{{.SecurityOptions}}' &&
		grep -q selinux <<<"$LAST_OUT" ;;
	*)	engine run --rm "$IMAGE_TUMBLEWEED" cat /proc/self/attr/current &&
		grep -qE 'container_|svirt' <<<"$LAST_OUT" ;;
	esac
}

have_freezer() {	# empirical: pause and unpause a sleeper
	local c rc
	c=$(mkname freezer-probe)
	if engine run -d --rm --name "$c" "$IMAGE_BUSYBOX" sleep 240 ; then
		if engine pause "$c" && engine unpause "$c" ; then rc=0 ; else rc=1 ; fi
		engine rm -f "$c" >/dev/null
	else
		rc=1
	fi
	return "$rc"
}

have_rootless() {	# podman always can; docker needs the user socket
	[ "$RUNTIME" != docker ] ||
		[ -S "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/docker.sock" ]
}

# Naming and the cleanup registry. Every resource carries the run-unique
# prefix, so the sweep can clean what a dead subshell's registry missed.
PREFIX="cetest-$$-"
mkname() { printf '%s%s' "$PREFIX" "$1" ; }
add_cleanup() {						# <kind> <name>
	printf 'created %s %s\n' "$1" "$2" >&2
	RESOURCES+=("$1 $2")
}

do_cleanup() {
	local r kind name
	if [ -n "${KEEP:-}" ] ; then
		{
			echo "KEEP: resources with prefix $PREFIX stay; remove with:"
			for r in "${RESOURCES[@]}" ; do
				kind=${r%% *} ; name=${r#* }
				case $kind in
				container) echo "  $RUNTIME rm -f $name" ;;
				volume)    echo "  $RUNTIME volume rm $name" ;;
				network)   echo "  $RUNTIME network rm $name" ;;
				file)      echo "  rm -rf '$name'" ;;
				esac
			done
			echo "  rm -rf /tmp/$PREFIX*"
		} >&2
		return 0
	fi
	for r in "${RESOURCES[@]}" ; do
		kind=${r%% *} ; name=${r#* }
		case $kind in
		container) "$RUNTIME" rm -f "$name" >/dev/null 2>&1 || true ;;
		volume)    "$RUNTIME" volume rm "$name" >/dev/null 2>&1 || true ;;
		network)   "$RUNTIME" network rm "$name" >/dev/null 2>&1 || true ;;
		file)      rm -rf "$name" 2>/dev/null || true ;;
		esac
	done
	rm -rf /tmp/"$PREFIX"* 2>/dev/null || true
}

sweep() {	# backstop: remove everything still carrying the prefix
	local kind verb sel f name names
	for kind in ps volume network ; do
		case $kind in
		ps)      verb="rm -f"      ; sel="ps --all"   ; f=Names ;;
		volume)  verb="volume rm"  ; sel="volume ls"  ; f=Name  ;;
		network) verb="network rm" ; sel="network ls" ; f=Name  ;;
		esac
		names=$("$RUNTIME" $sel --format "{{$f}}" 2>/dev/null | grep -F -- "$PREFIX") || true
		for name in $names ; do "$RUNTIME" $verb "$name" >/dev/null 2>&1 || true ; done
	done
	rm -rf /tmp/"$PREFIX"* 2>/dev/null || true
}

wait_for_state() {	# <name> <state> [timeout secs] — bounded poll
	local name=$1 want=$2 secs=${3:-15} got
	local deadline=$(( $(date +%s) + secs ))
	while : ; do
		eng inspect --format '{{.State.Status}}' "$name"
		got=$LAST_OUT
		[ "$got" = "$want" ] && return 0
		if [ "$(date +%s)" -ge "$deadline" ] ; then
			log "wait_for_state $name: still '$got' after ${secs}s, not '$want'"
			die "state '$want' not reached for $name"
		fi
		sleep 1
	done
}

: "${IMAGE_BUSYBOX:=registry.opensuse.org/opensuse/busybox}"
: "${IMAGE_TUMBLEWEED:=registry.opensuse.org/opensuse/tumbleweed}"

image_unavailable() {	# <ref> <engine error> [extra]
	{
		echo "IMAGE UNAVAILABLE: $1"
		echo "engine said: $2"
		echo "The required openSUSE image $1 could not be obtained."
		echo "This is an environment problem and not a container engine defect."
		[ -n "${3:-}" ] && echo "$3"
	} >&2
}

assert_report() {	# <expected> <observed> <name>
	printf '  assertion: %s\n  expected : %s\n  observed : %s\n' \
		"$3" "$1" "${2:-<empty>}" >&2
	if [ -n "${LAST_CMD:-}" ] ; then
		printf '  engine   : %s\n  output   : %s\n' \
			"$LAST_CMD" "${LAST_OUT:-${LAST_ERR:-<none>}}" >&2
	fi
	die "$3"
}

assert_eq() { [ "$1" = "$2" ] || assert_report "$1" "$2" "${3:-assert_eq}" ; }
assert_match() { [[ "$2" =~ $1 ]] || assert_report "$1" "$2" "${3:-assert}" ; }
assert_not_eq() { [ "$1" != "$2" ] ||
	assert_report "not '$1'" "$2" "${3:-assert_not_eq}" ; }
assert_not_grep() { grep -qxFe -- "$1" <<<"$2" &&
	assert_report "no line '$1'" "$2" "${3:-assert_not_grep}" ; }
assert_ok() {	# <name> <cmd...> — must succeed
	local name=$1 ; shift
	"$@" || assert_report "exit 0" "exit $? from: $*" "$name"
}
assert_fail() {	# <name> <cmd...> — must not succeed
	local name=$1 ; shift
	if "$@" >/dev/null 2>&1 ; then
		assert_report "non-zero exit" "exit 0 from: $*" "$name"
	fi
}

# start_bg <name> <cmd...>: background container, failing the test on
# error. Extra run flags via the RUNFLAGS array, e.g.
#   RUNFLAGS=(--mount "type=volume,src=$v,dst=/data") start_bg n sleep 300
start_bg() {
	local name=$1 ; shift
	eng run -d --name "$name" ${RUNFLAGS[@]:+"${RUNFLAGS[@]}"} \
		"$IMAGE_BUSYBOX" "$@" ; RUNFLAGS=()
	add_cleanup container "$name"
	wait_for_state "$name" running
}

quiet() { "$RUNTIME" "$@" >/dev/null 2>&1 ; }	# for setup/teardown calls
new_bind_dir() { mktemp -d "/tmp/${PREFIX}XXXXXX" ; }
