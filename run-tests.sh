#!/bin/bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Felix Niederwanger
#
# container-engine functional tests. Drives a real engine (podman by
# default, or docker) and reports whether it behaves as specified.
# Exit codes: 0 all passed or skipped, 1 a test failed (engine defect),
# 2 usage or environment error — the engine was not tested.
set -euo pipefail

cd "$(dirname "$(realpath "$0")")" || exit 2
# shellcheck source=lib/common.sh
source lib/common.sh

USAGE=$(cat <<'EOF'
container-engine functional tests

usage: run-tests.sh [options]

  --runtime podman|docker   engine under test (default: podman)
  --filter <pattern>        run only tests whose name matches (substring)
  --list                    print the test names and exit
  --keep                    keep created resources; print the removal command
  --no-pull                 use local images only; fail when absent
  --allow-unprivileged      permit a run without root (tests may skip)
  --rootless-user <name>    user for the rootless smoke test
                            (default: SUDO_USER, else skip)
  --skip-rootless           skip the rootless smoke test
  -v                        also print diagnostics of passing tests
  -h, --help                print this help and exit

exit codes: 0 all tests passed or skipped; 1 at least one test failed;
2 usage or environment error — the engine was not tested.
EOF
)

usage_error() {
	{ echo "usage error: $*" ; echo ; echo "$USAGE" ; } >&2
	exit 2
}
show_help() { echo "$USAGE" ; exit 0 ; }

env_abort() { echo "ENVIRONMENT: $*" >&2 ; exit 2 ; }

# ---------- arguments -------------------------------------------------------
RUNTIME=podman ; FILTER="" ; WANT_LIST=0 ; KEEP="" ; NO_PULL=0
ALLOW_UNPRIV="" ; ROOTLESS_USER="" ; SKIP_ROOTLESS="" ; VERBOSE=0
declare -i TCOUNT=0 PASS=0 FAIL=0 SKIP=0

while [ $# -gt 0 ] ; do
	case $1 in
	--runtime)	[ $# -gt 1 ] || usage_error "--runtime needs a value"
			RUNTIME=$2 ; shift 2 ;;
	--filter)	[ $# -gt 1 ] || usage_error "--filter needs a pattern"
			FILTER=$2 ; shift 2 ;;
	--rootless-user) [ $# -gt 1 ] || usage_error "--rootless-user needs a name"
			ROOTLESS_USER=$2 ; shift 2 ;;
	--list)		WANT_LIST=1 ; shift ;;
	--keep)		KEEP=1 ; shift ;;
	--no-pull)	NO_PULL=1 ; shift ;;
	--allow-unprivileged) ALLOW_UNPRIV=1 ; shift ;;
	--skip-rootless) SKIP_ROOTLESS=1 ; shift ;;
	-v)		VERBOSE=1 ; shift ;;
	-h|--help)	show_help ;;
	*)		usage_error "unknown option: $1" ;;
	esac
done

case $RUNTIME in
	podman|docker) : ;;
	*) usage_error "unsupported engine '$RUNTIME' — accepted values: podman, docker" ;;
esac

# ---------- test discovery ---------------------------------------------------
# The test files are plain sources; the runner discovers test_<name>
# functions by name, so there is no registration call to maintain.
for tf in tests/*.sh ; do
	# shellcheck source=/dev/null
	source "$tf"
done

declare -a TESTS=()
for fn in $(declare -F | awk '{print $3}' | sort) ; do
	[[ $fn != test_* ]] && continue
	fn=${fn#test_}
	[ -z "$FILTER" ] || [[ $fn == *"$FILTER"* ]] || continue
	TESTS+=("$fn")
done

if [ "$WANT_LIST" = 1 ] ; then printf '%s\n' "${TESTS[@]}" ; exit 0 ; fi
[ "${#TESTS[@]}" -gt 0 ] ||
	usage_error "no test matches --filter '$FILTER'"

# ---------- traps: cleanup on exit, failure and interrupt --------------------
on_exit() {
	local rc=$?
	set +e
	do_cleanup
	[ -n "${KEEP:-}" ] || sweep
	exit "$rc"       # a failing cleanup must not mask the status
}
trap on_exit EXIT
trap 'exit 130' INT        # through on_exit, carrying 130 out
trap 'exit 143' TERM

# ---------- preflight --------------------------------------------------------
tool_check() {
	local missing=() t
	for t in "${SUITE_TOOLS[@]}" ; do
		have "$t" || missing+=("$t (${PROVIDER[$t]})")
	done
	[ "${#missing[@]}" = 0 ] || env_abort "missing standard tools: ${missing[*]}"
}

privilege_check() {
	[ "$(id -u)" -eq 0 ] && return 0
	[ -n "$ALLOW_UNPRIV" ] || env_abort \
		"root privilege is required (effective UID $(id -u)); re-run as root or pass --allow-unprivileged"
}

engine_check() {
	have "$RUNTIME" || env_abort "engine '$RUNTIME' not found in PATH"
	if ! "$RUNTIME" version >/dev/null 2>&1 ; then
		echo "ENVIRONMENT: engine '$RUNTIME' is installed but not responsive:" >&2
		"$RUNTIME" version 2>&1 | head -5 >&2 || true
		echo "no test was run." >&2
		exit 2
	fi
}

obtain_image() { # <reference>
	local ref=$1
	if [ "$NO_PULL" = 1 ] ; then
		engine image inspect "$ref" || {
			image_unavailable "$ref" "not present locally" \
				"pulling was disabled (--no-pull)"
			exit 2
		}
		return 0
	fi
	engine pull "$ref" >/dev/null 2>&1 || {
		image_unavailable "$ref" "${LAST_ERR:-image pull failed}"
		exit 2
	}
}

images_provision() {
	local ref
	for ref in "$IMAGE_TUMBLEWEED" "$IMAGE_BUSYBOX" ; do obtain_image "$ref" ; done
}

probe_framework() {
	have_freezer ||
		log "probe: the host offers no freezer (pause tests will skip)"
	have_rootless ||
		log "probe: no rootless mode (the rootless test will skip)"
}

# ---------- running ----------------------------------------------------------
describe_run() {
	echo "container-engine tests: runtime=$RUNTIME images:" \
		"$IMAGE_BUSYBOX, $IMAGE_TUMBLEWEED"
	[ -n "$KEEP" ] && echo "keep: resources stay (--keep)"
	[ "$NO_PULL" = 1 ] && echo "note: pulling disabled (--no-pull)"
	[ -n "$ALLOW_UNPRIV" ] && echo "note: unprivileged run allowed"
	[ -n "$SKIP_ROOTLESS" ] && echo "note: rootless smoke test disabled"
	return 0
}

run_one() { # <function>; classification by the subshell's exit status
	local rc=0 out evidence f outword
	f=$(mktemp "/tmp/${PREFIX}out-XXXXXX")
	out=$("$1" 2>"$f") || rc=$?
	evidence=$(<"$f") ; rm -f "$f"
	case $rc in
	0)	outword=ok ;      PASS+=1 ;;
	99)	outword=ok ;      SKIP+=1 ;;
	*)	outword="not ok" ; FAIL+=1 ;;
	esac
	if [ "$rc" = 99 ] ; then
		printf '%s %d - %s # SKIP %s\n' "$outword" "$TCOUNT" "$TEST_NAME" "${out#SKIP }"
	else
		printf '%s %d - %s\n' "$outword" "$TCOUNT" "$TEST_NAME"
	fi
	if [ -n "$evidence" ] && { [ "$rc" != 0 ] || [ "$VERBOSE" = 1 ] ; } ; then
		printf '%s\n' "$evidence"
	fi
}

run_suite() {
	local fn
	for fn in "${TESTS[@]}" ; do
		TCOUNT+=1
		TEST_NAME=$fn
		run_one "test_$fn"
		if [ -z "$KEEP" ] ; then do_cleanup ; sweep ; fi
	done
}

summarize() {
	echo "# tests: ${TCOUNT} passed: ${PASS} failed: ${FAIL} skipped: ${SKIP}"
	[ "$FAIL" -gt 0 ] && return 1 || return 0
}

main() {
	tool_check
	privilege_check
	engine_check
	describe_run
	images_provision
	probe_framework
	run_suite
	summarize
}

main
