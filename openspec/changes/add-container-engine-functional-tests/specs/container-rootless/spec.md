# Spec Delta

## Purpose

Provides a smoke test that the engine also works without root privilege,
so that a host advertising rootless support is proven to actually run an
unprivileged container with a working user namespace mapping.

## ADDED Requirements

### Requirement: Rootless Precondition
The rootless test SHALL run only when an unprivileged user able to use
the engine can be determined, and SHALL report a skip with the reason
otherwise.

#### Scenario: User selected explicitly
- **WHEN** `--rootless-user <name>` names an existing unprivileged user
- **THEN** the test runs as that user

#### Scenario: User taken from the invocation
- **WHEN** no `--rootless-user` is given and `SUDO_USER` names an existing unprivileged user
- **THEN** the test runs as that user

#### Scenario: No user available
- **WHEN** neither source yields an existing unprivileged user
- **THEN** the test reports a skip stating that no rootless user could be determined

#### Scenario: Subordinate id ranges missing
- **WHEN** the selected user has no entry in `/etc/subuid` or `/etc/subgid`, or `newuidmap` is not installed
- **THEN** the test reports a skip naming the missing prerequisite

#### Scenario: Runtime without a rootless mode
- **WHEN** the selected runtime is `docker` and no rootless endpoint is configured for the user
- **THEN** the test reports a skip stating that rootless docker is not configured

#### Scenario: Explicitly disabled
- **WHEN** `--skip-rootless` is passed
- **THEN** the test reports a skip naming the option
- **AND** no privilege is dropped and no container is created

### Requirement: Rootless Container Execution
The engine SHALL run a container as an unprivileged user, and the
container's command SHALL execute successfully.

#### Scenario: Container runs unprivileged
- **WHEN** the suite drops to the selected user and runs a container from the test image with a command printing a known string
- **THEN** the engine exits 0
- **AND** the known string is received

#### Scenario: Engine reports rootless mode
- **WHEN** the engine is queried for its mode while running as that user
- **THEN** it reports that it is running rootless

### Requirement: Rootless User Namespace Mapping
A rootless container SHALL see itself as UID 0 inside its user namespace
while its host process remains owned by the unprivileged user.

#### Scenario: Mapping is in effect
- **WHEN** the rootless container reports its own effective UID
- **THEN** the value is 0

#### Scenario: Host ownership is unprivileged
- **WHEN** the owner of the engine process on the host is examined during that run
- **THEN** it is the selected unprivileged user and not root

### Requirement: Rootless Result Is Not Fatal To The Run
A skipped rootless test SHALL NOT fail the run, while a rootless test
that runs and fails SHALL fail the run like any other test.

#### Scenario: Skip keeps the run green
- **WHEN** the rootless test is skipped and every other test passes
- **THEN** the suite exits 0
- **AND** the summary counts the skip separately

#### Scenario: Failure is reported normally
- **WHEN** the rootless test runs and an assertion fails
- **THEN** the suite reports `not ok` for it and exits 1
