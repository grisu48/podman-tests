# Project: container-engine-tests

A functional test suite for OCI container engines. It drives a real engine
binary from the outside — creating, running, networking and destroying
containers — and reports whether the engine behaves as specified. It tests
the engine, not the images and not the kernel.

Supported engines: `podman` (default) and `docker`.

## Conventions

- Spec-first development: every change starts as an OpenSpec change under
  `openspec/changes/`, then is implemented and archived.
- The suite is written in plain bash. No test framework and no second
  implementation language.
- Only standard Linux tools may be called: bash builtins and the
  utilities a distribution installs by default, such as coreutils,
  `grep`, `sed`, `awk`, `util-linux`, `ip` and `curl`, plus the container
  engine binary under test. Anything an operator would have to install
  first is forbidden — `nmap`, `jq`, `socat`, `netcat` and
  language-runtime helpers are all out of scope. e.g. `curl` is allowed;
  `nmap` is not.
- Every external tool the suite uses is declared and checked in
  preflight, so a missing one is reported as an environment problem
  rather than as an engine defect.
- Inside test containers, only what the openSUSE image already ships is
  used. Installs a package into a container is strongly discouraged.
- Only openSUSE images are used for testing, referenced from
  `registry.opensuse.org`.
- The default engine is `podman`; the engine is selected via an environment
  variable.
- Rootful operation is the default assumption. Rootless coverage is
  explicitly marked and may be skipped.
- Every test is self-contained: it creates its own resources with a
  run-unique name prefix and removes them again, including on failure.
- Environment problems (missing image, missing privilege, missing engine)
  are reported distinctly from engine defects, so a red run is never
  ambiguous.
- Keep the code small and tidy. Prefer the minimal construct that is
  still readable; no defensive scaffolding for cases the spec does not
  describe.
- Requirements use RFC 2119 key words (SHALL/MUST, SHOULD, MAY) and must
  be objectively verifiable; every requirement carries at least one
  WHEN/THEN scenario.

## Purposes

1. Detect functional regressions in a container engine on a given host,
   at the level a user experiences them.
2. Run anywhere with nothing installed but bash and the engine itself.
3. Produce output a human and a CI job can both read, with environment
   failures clearly separated from engine failures.
