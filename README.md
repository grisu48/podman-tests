# container-engine functional tests

System-level functional tests for OCI container engines written in plain
bash. It drives a real engine binary from the outside — creating, running,
networking and destroying containers — and reports whether the engine
behaves as specified. It tests the engine, not the images and not the
kernel.

The suite runs out of the box on any host that already has bash, the
engine under test and nothing else.

## The standard-tools-only rule

The suite may only call standard Linux tools: bash builtins and the
utilities a distribution installs by default — coreutils, `grep`, `sed`,
`awk`, util-linux, `ip` and, explicitly allowed, `curl` — plus the
container engine binary under test.

Anything an operator would have to install first is forbidden. Examples:

| allowed                 | forbidden            |
|-------------------------|----------------------|
| `curl`, `grep`, `ip`    | `nmap`, `jq`, `socat`|
| `sed`, `awk`, `su`      | `netcat`, `bats`     |
| coreutils, util-linux   | any language runtime |

The declared tool list is checked in preflight; a missing tool is
reported as an environment problem (`ENVIRONMENT:`, exit 2) rather than
being mistaken for an engine defect.

Inside test containers, only what the openSUSE images already ship is
used; nothing is ever installed into a container. Only openSUSE images
from `registry.opensuse.org` are used. The two image references can be
overridden for air-gapped mirrors by setting `IMAGE_BUSYBOX` and
`IMAGE_TUMBLEWEED`.

## Usage

```
./run-tests.sh [options]
```

| option | meaning |
|--------|---------|
| `--runtime podman\|docker` | engine under test (default: `podman`) |
| `--filter <pattern>` | run only tests whose name matches the pattern |
| `--list` | print all test names and exit |
| `--keep` | keep created resources; print the removal command |
| `--no-pull` | use local images only; fail when absent |
| `--allow-unprivileged` | allow a run without root (tests may skip) |
| `--rootless-user <name>` | user for the rootless smoke test (default: `$SUDO_USER`) |
| `--skip-rootless` | skip the rootless smoke test |
| `-v` | also print diagnostics of passing tests |
| `-h`, `--help` | print full usage and exit |

## Required privilege

Rootful operation is the default assumption: the suite needs root
privilege (or full capabilities for the engine). Without it, preflight
fails with exit 2 unless `--allow-unprivileged` is passed; tests that
cannot work unprivileged then report a skip with their reason. The
rootless smoke test re-enters the engine as an unprivileged user via
`su -`.

The suite creates and destroys real containers, volumes and networks on
the host it runs on and binds a loopback port — run it on a test host,
not a production one. Every resource it creates carries a run-unique
`cetest-<pid>-` name prefix and is removed again, including after a
failure or an interrupt, unless `--keep` is passed.

## Exit codes

| code | meaning |
|------|---------|
| 0 | all tests passed or were skipped |
| 1 | at least one test failed — an engine defect |
| 2 | usage or environment error — the engine was not tested |

Environment problems (missing engine, missing tool, missing privilege,
unavailable image) are reported with `ENVIRONMENT:` or
`IMAGE UNAVAILABLE:` wording and never fail a run with exit 1, so a red
run is never ambiguous.

Individual results are printed in TAP-like form:

```
ok 1 - lifecycle_create
not ok 2 - lifecycle_start
ok 3 - rootless_smoke # SKIP no rootless user could be determined
```
