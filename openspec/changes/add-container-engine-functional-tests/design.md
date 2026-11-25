# Design

## Context

See proposal.md — Why. The hard constraint is plain bash calling only
standard Linux tools, on a host that may have nothing installed beyond
its distribution's default package set and the engine under test. The
line runs between what is already there and what an operator would have
to install: `curl` is on the allowed side, `nmap`, `jq` and `socat` are
not. That constraint drives most of the decisions below — in particular
it removes the usual JSON parser and the usual test framework, so each
has to be replaced by something the base system already offers.

## Goals / Non-Goals

Goals:

- One executable entry point, runnable from a checkout with no install
  step.
- The same test bodies run against podman and docker.
- Environment problems are distinguishable from engine defects by exit
  code alone.

Non-Goals:

- Testing the images themselves, the kernel, or the registry.
- Internal unit tests of the suite's own functions — not required; the
  suite is verified by running it, per project conventions.
- Performance, stress or soak testing.
- Complete rootless coverage; rootless is a smoke test in this change.
- Supporting engines other than podman and docker.
- Parallel test execution.

## Decisions

### Layout: one runner, one library, one file per area

```
run-tests.sh          argument parsing, preflight, test dispatch, summary
lib/common.sh         logging, assertions, engine wrapper, cleanup registry
tests/10-lifecycle.sh
tests/20-storage.sh
tests/30-network.sh
tests/40-selinux.sh
tests/50-rootless.sh
```

Each test file is sourced by the runner and exposes functions named
`test_<name>`. The runner discovers them by name, which keeps
registration free of boilerplate: no arrays to maintain, no per-test
registration call. Target size is about 400 lines in total.

Alternative considered: a single file. Rejected — `--filter` and `--list`
are cheaper to implement over discovered functions, and one file per area
keeps each area's helpers next to their tests.

### Engine abstraction: one wrapper, capability probes, no engine branches

All engine calls go through `engine()`, which prefixes the selected
binary and records the last command and its output for failure
diagnostics. Where podman and docker genuinely differ, the difference is
expressed as a named probe (`have_selinux`, `have_freezer`,
`have_rootless`) evaluated during preflight, not as an `if [ "$RUNTIME" =
docker ]` scattered through the tests. Only the probes may know which
engine is running.

Known divergences to absorb in probes: docker needs a reachable daemon
while podman does not; podman inspect output differs in field layout;
rootless docker needs a per-user socket.

### No JSON parsing

Inspect output is never parsed as JSON. Every value the tests need is
requested through the engine's own Go-template formatting
(`--format '{{.State.Status}}'`), which returns one bare value per call.
This is a feature of both engines and keeps the suite free of a JSON
parser.

Alternative considered: regex over JSON with bash pattern matching.
Rejected — brittle and unreadable, and the engines already offer the
right tool.

### Where the tool line is drawn

A tool is allowed when a default installation of the target
distributions already provides it, so that the suite adds no setup step
to the host it is meant to diagnose. `curl` qualifies; so do coreutils,
grep, sed, awk, util-linux and iproute2. A tool is forbidden when using
it would mean installing it first — `nmap`, `jq`, `socat`, `netcat`,
`bats` and anything carrying a language runtime. The test is "would an
operator have to install this", not "is this a nice tool".

The same rule applies inside containers, where it is stricter in
practice: nothing may be installed into a test container, because that
would need registry access from the container network and would make an
image problem look like an engine problem.

Everything the suite calls is declared in one list and checked in
preflight, so an absent tool produces `ENVIRONMENT:` and exit 2 rather
than a confusing mid-run error.

### HTTP with `curl`

Host-side verification of a published port is a `curl` request against
`127.0.0.1:<port>` with `--fail`, `--silent`, `--show-error`,
`--connect-timeout` and `--max-time`, checking the status and the body.
Bounded timeouts mean a broken mapping cannot stall the run, and
`curl`'s exit codes distinguish "refused" from "timed out" without
parsing a message — useful for the negative scenarios, where an
unpublished port must not answer.

Alternative considered: a hand-rolled client over bash's `/dev/tcp`
redirection. It needs no tool at all, but it costs about ten lines of
socket and parsing code to own, has no TLS should it ever be needed, and
depends on bash being built with net redirections enabled, which is not
universal. With `curl` inside the allowed set, that complexity buys
nothing.

Alternative considered: `podman run --network host ... wget` instead of
a host client. Rejected — it puts the engine under test inside the
measuring instrument, so a broken exec or host-network path would fail a
port-publishing assertion and point at the wrong requirement.

### Images: busybox from registry.opensuse.org, Tumbleweed only when needed

`registry.opensuse.org/opensuse/busybox` is the workhorse. It is an
openSUSE image, it is tiny, and it already carries `httpd`, `nc`, `wget`,
`ip` and `sh`. That removes any need to install a package inside a test
container, which would otherwise require registry access from the
container network and break the tool rule from the inside.
`registry.opensuse.org/opensuse/tumbleweed` is used only where a full
userland is required. Both references are overridable by environment
variable for air-gapped mirrors.

### Reachability is always TCP, never ICMP

Ping needs either privilege or a permissive `net.ipv4.ping_group_range`,
which the rootless smoke test cannot assume. Every reachability check is
therefore a TCP connection against a busybox `httpd` listener, which is
also a stronger statement than an ICMP echo.

### SELinux: assert the denial, not just the allow

Testing only that a `:Z` mount is readable would pass on a host where
SELinux does nothing. The suite therefore asserts the matching negative
case — the same directory mounted without a relabel option must be
denied — and refuses to run the pair at all unless
`/sys/fs/selinux/enforce` reads `1`. Contexts are read with `ls -Z` on
the host and by reading `/proc/self/attr/current` inside the container,
both of which stay within coreutils and plain file reads.

### Rootless: drop privilege with `su -`, keep it a smoke test

The suite runs rootful, so the rootless test re-enters the engine as the
selected unprivileged user through `su - <user> -c`. A login shell is
used so that `XDG_RUNTIME_DIR` and the user's environment are set up the
way the engine expects. The test asserts only that a container runs, that
the engine reports rootless mode, and that UID 0 inside maps to a
non-root host process. Everything else is left to a later change.

### Failure reporting carries the evidence

An assertion failure prints the assertion name, the expected value, the
observed value and the last engine command with its output. Without this,
a `not ok` line in CI costs a manual reproduction; with it, the log is
usually enough.

## Risks / Trade-offs

- Registry unreachable or image moved → preflight pulls everything before
  the first test and fails with the `IMAGE UNAVAILABLE:` wording and exit
  2, so the run is never mistaken for an engine regression.
- Host port already bound by an unrelated service → the suite picks a
  free high port by probing it with `curl` before publishing, and
  retries a small number of times before failing with a clear reason.
- "Standard tool" is a judgement, and a trimmed-down image may ship less
  than its distribution's default → the declared tool list plus the
  preflight check turns any disagreement into a named `ENVIRONMENT:`
  message instead of a mysterious failure, and keeps the allowed set
  visible in one place rather than spread across tests.
- Timing flakiness around state transitions → every state check is a
  bounded poll with a deadline rather than a sleep, and the deadline is
  reported on timeout.
- Leaked resources after a hard kill (SIGKILL cannot be trapped) → the
  run-unique `cetest-<pid>-` prefix makes leftovers obvious and the
  `--keep` message documents the removal command.
- Template output differences between podman and docker versions → the
  few templates in use are the stable, documented ones; a probe failure
  surfaces as an environment error, not a silent wrong answer.
- `su - <user>` behaves differently across PAM configurations → the
  rootless test treats a failure to drop privilege as a skip with the
  reason, not as an engine defect.

## Migration Plan

Not applicable; the repository is greenfield and nothing depends on it
yet.
