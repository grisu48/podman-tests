# podman tests

System-level functional tests for OCI container engines written in plain bash.

The purpose of this test suite is to provide a high level functional test suite
that is easy to use and works out-of-the box with only Linux standard tools.

It drives a real engine binary from the outside — creating, running,
networking and destroying containers — and reports whether the engine
behaves as specified. It does not test the images or the kernel.

## Standard tools only

The suite calls only bash builtins, the utilities a distribution installs
by default (coreutils, grep, sed, awk, util-linux, iproute2, `curl`), and
the container engine binary under test. It never calls a tool an operator
would have to install first — `nmap`, `jq`, `socat`, `netcat` and language
runtimes are all out of scope. The same rule applies inside test
containers: nothing is installed into them, only what the openSUSE test
images already ship (busybox's `wget`, `ip`, `sh`; nginx's own HTTP server
for the one scenario that needs a TCP listener).

Every tool the suite needs is declared and checked during preflight, so a
missing one is reported as `ENVIRONMENT:` with the providing package,
rather than as a confusing mid-run failure.

## Usage

```sh
sudo ./run-tests.sh                        # test podman (default)
sudo ./run-tests.sh --runtime docker       # test docker
./run-tests.sh --list                      # list test names
sudo ./run-tests.sh --filter 'network_*'   # run a subset
sudo ./run-tests.sh --keep -v              # keep resources, verbose output
```

Run `./run-tests.sh --help` for every option.

## Exit codes

| Code | Meaning |
| --- | --- |
| 0 | Every test passed or was skipped. |
| 1 | At least one test failed — an engine defect. |
| 2 | Usage or environment error — the engine was not tested. |

## Privilege

The suite assumes rootful operation and refuses to run unprivileged
unless `--allow-unprivileged` is passed. A single rootless smoke test
drops privilege with `su -` to a selected or detected user; it is skipped
with a reason when the host cannot support it.

## Layout

```
run-tests.sh          argument parsing, preflight, dispatch, summary
lib/common.sh          logging, assertions, engine wrapper, cleanup
tests/10-lifecycle.sh   create, start, pause, stop, destroy
tests/20-storage.sh     named volumes and host bind mounts
tests/30-network.sh     bridge networks, reachability, port publishing
tests/40-selinux.sh     SELinux process and mount labelling
tests/50-rootless.sh    rootless smoke test
```

Every resource the suite creates carries a run-unique `cetest-<pid>-`
prefix and is removed on exit, including after a failure or an interrupt,
unless `--keep` is passed.
