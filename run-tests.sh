#!/bin/bash
# SPDX-License-Identifier: MIT
# Functional test suite for OCI container engines (podman/docker).
set -euo pipefail

SELF_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$SELF_DIR/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: run-tests.sh [options]

Options:
  --runtime <podman|docker>  Engine to test (default: podman)
  --filter <pattern>         Run only tests whose name matches pattern (glob)
  --list                     List test names and exit
  --keep                     Do not remove created resources
  --no-pull                  Do not pull images; fail if missing locally
  --allow-unprivileged       Allow running as a non-root user
  --rootless-user <name>     User to use for the rootless smoke test
  --skip-rootless            Skip the rootless smoke test
  -v                         Verbose: print every engine command and output
  -h, --help                 Show this help

Exit codes:
  0  every test passed or was skipped
  1  at least one test failed (an engine defect)
  2  usage or environment error (the engine was not tested)
EOF
}

RUNTIME=podman
FILTER=""
LIST=0
KEEP=0
NO_PULL=0
ALLOW_UNPRIVILEGED=0
ROOTLESS_USER=""
SKIP_ROOTLESS=0
VERBOSE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --runtime) RUNTIME=$2; shift 2 ;;
    --filter) FILTER=$2; shift 2 ;;
    --list) LIST=1; shift ;;
    --keep) KEEP=1; shift ;;
    --no-pull) NO_PULL=1; shift ;;
    --allow-unprivileged) ALLOW_UNPRIVILEGED=1; shift ;;
    --rootless-user) ROOTLESS_USER=$2; shift 2 ;;
    --skip-rootless) SKIP_ROOTLESS=1; shift ;;
    -v) VERBOSE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "usage error: unknown option '$1'" >&2; usage >&2; exit 2 ;;
  esac
done

case "$RUNTIME" in
  podman|docker) ;;
  *) echo "usage error: --runtime must be 'podman' or 'docker', got '$RUNTIME'" >&2; exit 2 ;;
esac

for f in "$SELF_DIR"/tests/*.sh; do . "$f"; done

mapfile -t TEST_NAMES < <(declare -F | awk '{print $3}' | grep '^test_')

if [ "$LIST" -eq 1 ]; then
  printf '%s\n' "${TEST_NAMES[@]#test_}"
  exit 0
fi

if [ -n "$FILTER" ]; then
  filtered=()
  for t in "${TEST_NAMES[@]}"; do
    case "${t#test_}" in
      $FILTER) filtered+=("$t") ;;
    esac
  done
  TEST_NAMES=("${filtered[@]}")
  if [ "${#TEST_NAMES[@]}" -eq 0 ]; then
    echo "usage error: --filter '$FILTER' matched no test" >&2
    exit 2
  fi
fi

preflight
trap run_cleanup EXIT INT TERM

echo "# engine: $RUNTIME"
[ "$IMAGE_BUSYBOX" != "registry.opensuse.org/opensuse/busybox" ] && echo "# image override: busybox=$IMAGE_BUSYBOX"
[ "$IMAGE_TUMBLEWEED" != "registry.opensuse.org/opensuse/tumbleweed" ] && echo "# image override: tumbleweed=$IMAGE_TUMBLEWEED"

n=0
pass=0
fail=0
skip=0
for t in "${TEST_NAMES[@]}"; do
  n=$((n + 1))
  run_test "$n" "$t"
done

echo "# passed $pass, failed $fail, skipped $skip"
[ "$fail" -eq 0 ]
