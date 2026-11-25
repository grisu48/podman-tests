# Implementation Tasks: add-container-engine-functional-tests

Build order runs from the harness upward, so each area's tests have a
working runner, reporter and cleanup to rely on before they are written.

## 1. Harness Skeleton

- [x] 1.1 Create `run-tests.sh` with `set -euo pipefail`, a shebang of `#!/bin/bash`, and a license header
- [x] 1.2 Parse `--runtime`, `--filter`, `--list`, `--keep`, `--no-pull`, `--allow-unprivileged`, `--rootless-user`, `--skip-rootless`, `-v`, `-h`; reject unknown options and unknown `--runtime` values with exit 2
- [x] 1.3 Implement `-h/--help` covering every option, its default and the meaning of exit codes 0, 1 and 2
- [x] 1.4 Write the README: purpose, the standard-tools-only rule with its allowed and forbidden examples, usage, exit codes, required privilege

## 2. Reporting and Assertions

- [x] 2.1 Implement `ok`/`not ok`/`# SKIP` result lines with a running test counter
- [x] 2.2 Implement the final summary line with passed, failed and skipped counts
- [x] 2.3 Implement exit codes: 0 all passed or skipped, 1 any failure, 2 usage or environment error
- [x] 2.4 Implement assertions (`assert_eq`, `assert_match`, `assert_ok`, `assert_fail`) that print the assertion name, expected value, observed value and the last engine command with its output
- [x] 2.5 Implement `wait_for_state`: bounded polling with a deadline, reporting the deadline on timeout — no fixed sleeps

## 3. Engine Access

- [x] 3.1 Implement the `engine()` wrapper that prefixes the selected binary and records the last command, output and status
- [x] 3.2 Implement value queries through `--format '{{...}}'` templates only; no JSON parsing anywhere in the suite
- [x] 3.3 Implement preflight: engine present in `PATH` and responsive, otherwise `ENVIRONMENT:` message and exit 2
- [x] 3.4 Implement the privilege check: refuse to run with a non-zero UID unless `--allow-unprivileged`, with exit 2
- [x] 3.5 Implement capability probes `have_selinux`, `have_freezer`, `have_rootless`; these are the only places that may test which engine is selected
- [x] 3.6 Declare the external tool list in one place and check it in preflight; a missing suite-wide tool gives `ENVIRONMENT:` with the providing package and exit 2, a missing test-specific tool gives a skip

## 4. Images and Isolation

- [x] 4.1 Define the default image references under `registry.opensuse.org/opensuse/` (busybox as workhorse, tumbleweed where a full userland is needed) and their environment overrides
- [x] 4.2 Implement preflight image provisioning; on failure print the `IMAGE UNAVAILABLE:` message naming the reference, quoting the engine error and stating that this is an environment problem and not a container engine defect, then exit 2
- [x] 4.3 Honour `--no-pull`: use local images only and fail with the same wording, noting that pulling was disabled
- [x] 4.4 Report a post-preflight image loss as `not ok ... # IMAGE UNAVAILABLE` with the same wording
- [x] 4.5 Implement the run-unique `cetest-<pid>-` name prefix helper and use it for every created resource
- [x] 4.6 Implement the cleanup registry and `trap` on EXIT, INT and TERM; remove containers, volumes and networks even after a failure
- [x] 4.7 Honour `--keep`: skip cleanup and print the run prefix plus the removal command

## 5. Test Dispatch

- [x] 5.1 Source `tests/*.sh` and discover `test_*` functions by name
- [x] 5.2 Implement `--list`: print test names, create nothing, exit 0
- [x] 5.3 Implement `--filter`: run only matching tests; exit 2 when the pattern selects nothing
- [x] 5.4 Run each test in isolation so that one test's failure neither aborts the run nor leaks into the next test

## 6. Lifecycle Tests (`tests/10-lifecycle.sh`)

- [x] 6.1 Create a container without starting it; assert state `created` and that it is addressable by name
- [x] 6.2 Start it; assert state `running` and that an exec inside succeeds
- [x] 6.3 Pause it; assert state `paused`. Unpause; assert `running` and a working exec. Skip when `have_freezer` is false
- [x] 6.4 Stop it; assert the state is no longer `running` and that it is still listed; assert a second stop succeeds and changes nothing
- [x] 6.5 Assert foreground exit code propagation for 0 and 42
- [x] 6.6 Assert removal of a stopped container, refusal to remove a running one without force, and success with force

## 7. Storage Tests (`tests/20-storage.sh`)

- [x] 7.1 Create a named volume; assert it is listed
- [x] 7.2 Mount it, write known content, assert the write succeeds and the mount point appears in the container's mount table
- [x] 7.3 Remove the writer, mount the volume in a second container, assert the content reads back unchanged, including at a different mount path
- [x] 7.4 Bind mount a host directory: assert the host file is readable inside, a container write is visible on the host, and a read-only mount rejects writes
- [x] 7.5 Assert removal is refused while a container uses the volume, and succeeds once it is free

## 8. Network Tests (`tests/30-network.sh`)

- [x] 8.1 Create a `bridge` network; assert it is listed with driver `bridge`
- [x] 8.2 Assert a container on it gets a non-loopback IPv4 address and that the engine reports the same address
- [x] 8.3 Start a busybox `httpd` listener; assert a second container connects by address and receives the served payload unchanged
- [x] 8.4 Assert the same connection succeeds by container name, and that an unknown name fails to resolve
- [x] 8.5 Create a second network; assert a container on it cannot reach the listener on the first
- [x] 8.6 Implement the free-port picker (probe the candidate with `curl`, limited retries, clear failure reason)
- [x] 8.7 Implement the host HTTP check with `curl --fail --silent --show-error --connect-timeout --max-time`; assert status 200 and the expected body through a published port
- [x] 8.8 Assert the engine reports the port mapping, that an unpublished port is not reachable, and that the host port is free again after the container is removed

## 9. SELinux Tests (`tests/40-selinux.sh`)

- [x] 9.1 Implement the precondition: skip unless `/sys/fs/selinux/enforce` reads `1` and the engine's SELinux support is enabled, naming the reason
- [x] 9.2 Assert the container process context from `/proc/self/attr/current` is complete and carries a container type
- [x] 9.3 Assert two concurrent containers carry different MCS category sets
- [x] 9.4 Assert a `:Z` bind mount is readable and writable, and that the host context afterwards carries a container file type with the container's categories
- [x] 9.5 Assert the negative case: the same directory without a relabel option is denied, and its host context is unchanged
- [x] 9.6 Assert a directory relabelled for one container is denied to a second container with different categories
- [x] 9.7 Assert that disabling label separation makes the read succeed and leaves the container unconfined

## 10. Rootless Smoke Test (`tests/50-rootless.sh`)

- [x] 10.1 Resolve the rootless user from `--rootless-user`, else `SUDO_USER`; skip with a reason when neither resolves
- [x] 10.2 Skip with a named reason for: `--skip-rootless`, missing `/etc/subuid` or `/etc/subgid` entry, missing `newuidmap`, docker without a rootless endpoint, or an unusable `su -`
- [x] 10.3 Drop privilege with `su - <user> -c` and run a container printing a known string; assert exit 0 and the string
- [x] 10.4 Assert the engine reports rootless mode for that user
- [x] 10.5 Assert the effective UID inside the container is 0 while the host engine process is owned by the unprivileged user
- [x] 10.6 Assert a rootless skip keeps the run at exit 0 and is counted separately in the summary

## 11. Verification

- [ ] 11.1 Run the full suite against rootful podman on an SELinux-enforcing host; all tests pass or skip with a stated reason
- [ ] 11.2 Run the full suite with `--runtime docker`; same outcome
- [ ] 11.3 Verify the failure paths deliberately: unknown `--runtime`, missing engine, unprivileged without opt-in, and an unreachable image reference each exit 2 with the documented wording
- [ ] 11.4 Verify no resource carrying the run prefix survives a passing run, a failing run or a SIGINT
- [ ] 11.5 Confirm the tool rule by tracing the run and checking that every executed program is either a declared standard tool or the engine binary; in particular that no `nmap`, `jq`, `socat`, `netcat`, package manager or language runtime was started
- [x] 11.6 Verify the tool preflight by hiding a declared tool from `PATH`: the run must exit 2 with the tool and its package named
- [ ] 11.7 Check the suite with `bash -n` and ShellCheck; keep the total under roughly 400 lines
