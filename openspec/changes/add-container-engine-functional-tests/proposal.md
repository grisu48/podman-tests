# Proposal

- Date: 2026-11-25

## Why

There is no lightweight way to answer "does the container engine on this
host still work?" without installing a test framework, a language runtime
and a pile of client tools onto the host under test. Existing engine test
suites are written in Go, Python or bats and pull in the very tooling that
a minimal or freshly installed system does not have. A suite made of plain
bash runs on any host that already has the engine, which is by definition
every host worth testing.

## What Changes

- Add a functional test suite, `run-tests.sh`, written in plain bash.
  It may call standard Linux tools — the utilities a distribution
  installs by default, `curl` among them — and the engine binary under
  test, but nothing an operator would have to install first, such as
  `nmap`, `jq` or `socat`.
- Add engine selection as a command line argument, `--runtime
  podman|docker`, defaulting to `podman`.
- Add functional coverage for: container creation, start/stop/pause,
  destruction, volumes, bridge networking between containers, port
  publishing to the host, SELinux labelling, and a rootless smoke test.
- Use only openSUSE images from `registry.opensuse.org`. Required images
  are pulled during preflight; a pull failure fails the run with a message
  that names it as an environment problem rather than an engine defect.
- Assume rootful operation by default. Rootless coverage is a single
  smoke test that may be skipped when the host cannot support it.

## Capabilities

### New Capabilities

- `test-harness`: command line surface, engine selection and probing,
  image provisioning, resource isolation and cleanup, result reporting
  and exit codes.
- `container-lifecycle`: create, start, stop, pause, unpause and destroy
  a container, verified by observed container state.
- `container-storage`: named volumes attached to containers, data
  persistence across containers, and volume removal.
- `container-networking`: user-defined bridge networks, container to
  container reachability and name resolution, and port publishing to the
  host.
- `container-selinux`: SELinux labelling of container processes and of
  bind mounts, including the denial case.
- `container-rootless`: a smoke test proving rootless operation works,
  skippable when the host does not support it.

### Modified Capabilities

None — the repository is greenfield.

## Impact

- Affected specs: none; six new capabilities are added.
- Affected code: new suite at `run-tests.sh`, `lib/common.sh` and
  `tests/NN-<area>.sh`; no other code exists yet.
- Operational impact: the suite creates and destroys real containers,
  volumes and networks on the host it runs on, and binds a loopback port.
  It must therefore run on a test host, not a production one. Rootful
  privilege is required unless the operator opts out.
