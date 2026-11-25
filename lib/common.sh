# SPDX-License-Identifier: MIT
# Shared helpers: logging, assertions, engine wrapper, cleanup, probes.

PREFIX="cetest-$$-"
IMAGE_BUSYBOX="${CETEST_IMAGE_BUSYBOX:-registry.opensuse.org/opensuse/busybox}"
IMAGE_TUMBLEWEED="${CETEST_IMAGE_TUMBLEWEED:-registry.opensuse.org/opensuse/tumbleweed}"
IMAGE_NGINX="${CETEST_IMAGE_NGINX:-registry.opensuse.org/opensuse/nginx}"
CLEANUP_ITEMS=()

die_env() {
  echo "ENVIRONMENT: $1" >&2
  exit 2
}

die_image() {
  echo "IMAGE UNAVAILABLE: $1 could not be obtained: $2" >&2
  echo "This is an environment problem, not a container engine defect." >&2
  exit 2
}

# Runs the selected engine, never fails under set -e: check $LAST_STATUS.
engine() {
  LAST_CMD="$RUNTIME $*"
  if LAST_OUT=$("$RUNTIME" "$@" 2>&1); then
    LAST_STATUS=0
  else
    LAST_STATUS=$?
  fi
  [ "$VERBOSE" -eq 1 ] && printf '# + %s\n%s\n' "$LAST_CMD" "$LAST_OUT" | sed 's/^/# /' >&2
  return 0
}

# rname suffix -> prints a run-unique resource name.
rname() {
  printf '%s%s' "$PREFIX" "$1"
}

# track kind name -> registers a resource for cleanup.
# kind is one of: container, volume, network. Must run in the main shell,
# never inside a $(...) substitution, or the registration is lost.
track() {
  CLEANUP_ITEMS+=("$1:$2")
}

run_cleanup() {
  if [ "$KEEP" -eq 1 ]; then
    [ "${#CLEANUP_ITEMS[@]}" -eq 0 ] && return 0
    echo "# --keep: left ${#CLEANUP_ITEMS[@]} resource(s) with prefix '$PREFIX'"
    echo "# remove with: $RUNTIME ps -a --filter name=$PREFIX --format '{{.Names}}' | xargs -r $RUNTIME rm -f"
    return 0
  fi
  local i item kind nm
  for ((i = ${#CLEANUP_ITEMS[@]} - 1; i >= 0; i--)); do
    item=${CLEANUP_ITEMS[i]}
    kind=${item%%:*}
    nm=${item#*:}
    case "$kind" in
      container) "$RUNTIME" rm -f "$nm" >/dev/null 2>&1 || true ;;
      volume) "$RUNTIME" volume rm -f "$nm" >/dev/null 2>&1 || true ;;
      network) "$RUNTIME" network rm -f "$nm" >/dev/null 2>&1 || true ;;
    esac
  done
}

wait_for_state() {
  local cname=$1 want=$2 timeout=${3:-10} waited=0
  while [ "$waited" -lt "$timeout" ]; do
    engine inspect "$cname" --format '{{.State.Status}}'
    [ "$LAST_STATUS" -eq 0 ] && [ "$LAST_OUT" = "$want" ] && return 0
    sleep 1
    waited=$((waited + 1))
  done
  return 1
}

# run_bg name [args...] -> runs a detached container and waits for it to
# reach the running state. On failure, $LAST_OUT carries the reason.
run_bg() {
  local c=$1; shift
  engine run -d --name "$c" "$@"
  [ "$LAST_STATUS" -eq 0 ] && wait_for_state "$c" running 10
}

fail_result() {
  RESULT_STATE=fail
  RESULT_MSG=$(printf 'assertion: %s\n  expected: %s\n  observed: %s\n  command:  %s\n  output:   %s' \
    "$1" "$2" "$3" "${LAST_CMD:-}" "${LAST_OUT:-}")
}

skip() {
  RESULT_STATE=skip
  RESULT_MSG=$1
}

assert_eq() {
  [ "$2" = "$3" ] && return 0
  fail_result "$1" "$2" "$3"
  return 1
}

assert_match() {
  [[ $3 =~ $2 ]] && return 0
  fail_result "$1" "matches /$2/" "$3"
  return 1
}

assert_contains() {
  printf '%s\n' "$3" | grep -qxF "$2" && return 0
  fail_result "$1" "list containing '$2'" "$3"
  return 1
}

assert_ok() {
  [ "$2" -eq 0 ] && return 0
  fail_result "$1" "exit 0" "exit $2"
  return 1
}

assert_fail() {
  [ "$2" -ne 0 ] && return 0
  fail_result "$1" "non-zero exit" "exit 0"
  return 1
}

run_test() {
  local idx=$1 fn=$2 label=${2#test_}
  RESULT_STATE=pass
  RESULT_MSG=""
  "$fn" || true
  case "$RESULT_STATE" in
    pass)
      echo "ok $idx - $label"
      pass=$((pass + 1))
      ;;
    skip)
      echo "ok $idx - $label # SKIP $RESULT_MSG"
      skip=$((skip + 1))
      ;;
    fail)
      echo "not ok $idx - $label"
      printf '%s\n' "$RESULT_MSG" | sed 's/^/# /'
      fail=$((fail + 1))
      ;;
  esac
}

have_selinux() {
  [ -r /sys/fs/selinux/enforce ] || return 1
  [ "$(cat /sys/fs/selinux/enforce)" = "1" ] || return 1
  case "$RUNTIME" in
    podman) "$RUNTIME" info --format '{{.Host.Security.SELinuxEnabled}}' 2>/dev/null | grep -qi true ;;
    docker) "$RUNTIME" info 2>/dev/null | grep -qi selinux ;;
  esac
}

host_ctx() {
  ls -Zd "$1" | awk '{print $1}'
}

have_freezer() {
  [ -d /sys/fs/cgroup/freezer ] && return 0
  [ -e /sys/fs/cgroup/cgroup.freeze ] && return 0
  return 1
}

# preflight: tools, privilege, engine, images — in that order, each one
# a named ENVIRONMENT/IMAGE UNAVAILABLE failure, before any test runs.
preflight() {
  local spec tool pkg img
  for spec in curl:curl ip:iproute2 su:util-linux; do
    tool=${spec%%:*}
    pkg=${spec##*:}
    command -v "$tool" >/dev/null 2>&1 || die_env "missing tool '$tool' (package: $pkg)"
  done

  if [ "$(id -u)" -ne 0 ] && [ "$ALLOW_UNPRIVILEGED" -ne 1 ]; then
    die_env "rootful privilege is required; pass --allow-unprivileged to run as a non-root user"
  fi

  command -v "$RUNTIME" >/dev/null 2>&1 || die_env "$RUNTIME not found in PATH"
  if ! info_out=$("$RUNTIME" info 2>&1); then
    echo "ENVIRONMENT: $RUNTIME is installed but not responsive; no test was run" >&2
    echo "$info_out" >&2
    exit 2
  fi

  for img in "$IMAGE_BUSYBOX" "$IMAGE_TUMBLEWEED" "$IMAGE_NGINX"; do
    "$RUNTIME" image inspect "$img" >/dev/null 2>&1 && continue
    if [ "$NO_PULL" -eq 1 ]; then
      die_image "$img" "pulling was disabled (--no-pull) and the image is not present locally"
    fi
    if ! pull_out=$("$RUNTIME" pull "$img" 2>&1); then
      die_image "$img" "$pull_out"
    fi
  done
}
