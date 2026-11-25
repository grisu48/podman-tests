# Spec Delta

## Purpose

Provides the command line entry point that selects a container engine,
prepares the environment, runs the functional tests in isolation and
reports their results so that engine defects and environment problems are
never confused with each other.

## ADDED Requirements

### Requirement: Bash Implementation
The suite SHALL be implemented in bash. It SHALL NOT use a test
framework and SHALL NOT carry parts written in another programming
language.

#### Scenario: Runnable from a checkout
- **WHEN** the suite is run from a checkout on a host with bash and the engine
- **THEN** it executes without a build, an install or an interpreter other than bash

#### Scenario: No framework in the dependency path
- **WHEN** the suite's files are examined
- **THEN** no test framework is invoked, vendored or required

### Requirement: Standard Tool Dependencies
The suite SHALL call only standard Linux tools: bash builtins, the
utilities a distribution installs by default — coreutils, grep, sed,
awk, util-linux, iproute2, `curl` and their peers — and the container
engine binary under test. It SHALL NOT call a tool an operator would
have to install first.

#### Scenario: Standard tool is used
- **WHEN** a test needs an HTTP request, text processing or address information
- **THEN** it uses a default-installed utility such as `curl`, `grep` or `ip`

#### Scenario: Specialist tool is not used
- **WHEN** the suite's files are examined for the programs they execute
- **THEN** none of `nmap`, `jq`, `socat`, `netcat`, `bats` or a language runtime appears

#### Scenario: Minimal host
- **WHEN** the suite runs on a host carrying only its distribution's default package set and the engine
- **THEN** every test executes without reporting a missing command

### Requirement: Tool Preflight
The suite SHALL declare the external tools it needs and SHALL verify
they are present before the first test runs.

#### Scenario: Required tool missing
- **WHEN** a declared tool is not found in `PATH`
- **THEN** the suite prints `ENVIRONMENT:` naming the missing tool and the package that provides it
- **AND** exits with status 2 without running any test

#### Scenario: Tool needed by one area only
- **WHEN** a tool is needed by a single test rather than by the suite as a whole and it is absent
- **THEN** that test reports a skip naming the tool
- **AND** the remaining tests run

### Requirement: No Package Installation
The suite SHALL NOT install software, neither on the host nor inside a
test container. It SHALL use only what the openSUSE test images already
provide.

#### Scenario: Container tooling comes from the image
- **WHEN** a test needs a listener, a client or an address query inside a container
- **THEN** it uses a program the image already ships

#### Scenario: No package manager call
- **WHEN** the suite runs
- **THEN** no package manager is invoked on the host or in any container

### Requirement: Engine Selection
The suite SHALL select the engine under test from the command line
argument `--runtime <podman|docker>` and SHALL default to `podman` when
the argument is absent.

#### Scenario: Default engine
- **WHEN** the suite is started without `--runtime`
- **THEN** all engine commands are issued to `podman`
- **AND** the selected engine is named in the run header

#### Scenario: Explicit engine
- **WHEN** the suite is started with `--runtime docker`
- **THEN** all engine commands are issued to `docker`

#### Scenario: Unknown engine
- **WHEN** the suite is started with a `--runtime` value other than `podman` or `docker`
- **THEN** it prints a usage error naming the accepted values
- **AND** exits with status 2 without creating any resource

### Requirement: Engine Preflight
The suite SHALL verify before the first test that the selected engine is
installed and responsive, and SHALL stop with an environment error when it
is not.

#### Scenario: Engine binary missing
- **WHEN** the selected engine is not found in `PATH`
- **THEN** the suite prints `ENVIRONMENT:` followed by the engine name and exits with status 2

#### Scenario: Engine not responsive
- **WHEN** the engine is installed but a trivial query such as its version or info call fails
- **THEN** the suite reports the engine's own error text and exits with status 2
- **AND** the message states that no test was run

### Requirement: Privilege Mode
The suite SHALL assume rootful operation and SHALL refuse to run
unprivileged unless the operator passes `--allow-unprivileged`.

#### Scenario: Run as root
- **WHEN** the suite is started with an effective UID of 0
- **THEN** preflight passes and all tests run

#### Scenario: Run unprivileged without opt-in
- **WHEN** the effective UID is not 0 and `--allow-unprivileged` was not passed
- **THEN** the suite prints `ENVIRONMENT:` with the reason that rootful privilege is required
- **AND** exits with status 2 without running any test

#### Scenario: Unprivileged opt-in
- **WHEN** the effective UID is not 0 and `--allow-unprivileged` was passed
- **THEN** the suite runs
- **AND** tests that cannot work unprivileged report a skip with their reason instead of failing

### Requirement: openSUSE Test Images
The suite SHALL use only openSUSE images, referenced from
`registry.opensuse.org`, and SHALL allow each image reference to be
overridden by an environment variable.

#### Scenario: Default images
- **WHEN** no image override is set
- **THEN** every container is created from an image whose reference begins with `registry.opensuse.org/opensuse/`

#### Scenario: Overridden image
- **WHEN** an image override variable is set to another reference
- **THEN** the suite uses that reference and names it in the run header

### Requirement: Image Provisioning
The suite SHALL obtain every required image during preflight, before the
first test runs, and SHALL fail the run when an image cannot be obtained.
It SHALL NOT treat a missing image as a skip.

#### Scenario: Pull succeeds
- **WHEN** preflight pulls the required images and the engine reports success
- **THEN** the tests run

#### Scenario: Pull fails
- **WHEN** an image cannot be pulled
- **THEN** the suite prints a message prefixed `IMAGE UNAVAILABLE:` that names the image reference, quotes the engine's error, and states in plain words that the required openSUSE image could not be obtained and that this is an environment problem and not a container engine defect
- **AND** exits with status 2

#### Scenario: Pull is suppressed
- **WHEN** `--no-pull` is passed and a required image is not present locally
- **THEN** the suite reports the same `IMAGE UNAVAILABLE:` message, noting that pulling was disabled, and exits with status 2

#### Scenario: Image lost during the run
- **WHEN** a test cannot obtain its image after preflight succeeded
- **THEN** that test reports `not ok` with an `IMAGE UNAVAILABLE` reason carrying the same wording

### Requirement: Resource Isolation
Every resource the suite creates SHALL carry a name prefixed with
`cetest-<pid>-`, so that concurrent runs and pre-existing host resources
cannot collide.

#### Scenario: Named resources
- **WHEN** a test creates a container, volume or network
- **THEN** its name begins with the run-unique prefix

#### Scenario: Foreign resources untouched
- **WHEN** the host already holds containers, volumes or networks not carrying the prefix
- **THEN** the suite neither inspects, modifies nor removes them

### Requirement: Cleanup
The suite SHALL remove every resource it created before exiting,
including after a test failure, an error, or an interrupt, unless
`--keep` was passed.

#### Scenario: Cleanup after success
- **WHEN** all tests pass
- **THEN** no container, volume or network carrying the run prefix remains

#### Scenario: Cleanup after failure
- **WHEN** a test fails part way through
- **THEN** the resources that test created are still removed
- **AND** the remaining tests still run

#### Scenario: Cleanup on interrupt
- **WHEN** the run receives SIGINT or SIGTERM
- **THEN** cleanup runs before the process exits

#### Scenario: Cleanup suppressed for debugging
- **WHEN** `--keep` was passed
- **THEN** resources are left in place
- **AND** the suite prints the run prefix and the removal command the operator can use

### Requirement: Result Reporting
The suite SHALL print one result line per test in the form `ok <n> -
<name>` or `not ok <n> - <name>`, SHALL mark a skipped test with `# SKIP
<reason>`, and SHALL close with a summary of the counts.

#### Scenario: Passing test
- **WHEN** a test completes its assertions successfully
- **THEN** a line `ok <n> - <name>` is printed

#### Scenario: Failing test
- **WHEN** an assertion fails
- **THEN** a line `not ok <n> - <name>` is printed
- **AND** the following diagnostic lines name the assertion, the expected value, the observed value and the engine command that produced it

#### Scenario: Skipped test
- **WHEN** a test cannot run because the host lacks a prerequisite it declares
- **THEN** a line `ok <n> - <name> # SKIP <reason>` is printed
- **AND** the run is not failed by it

#### Scenario: Summary
- **WHEN** the run ends
- **THEN** a final line reports the number of tests passed, failed and skipped

### Requirement: Exit Codes
The suite SHALL exit 0 when every test passed or was skipped, 1 when any
test failed, and 2 for a usage or environment error.

#### Scenario: All green
- **WHEN** no test reported `not ok`
- **THEN** the exit status is 0

#### Scenario: Engine defect
- **WHEN** at least one test reported `not ok`
- **THEN** the exit status is 1

#### Scenario: Environment problem
- **WHEN** the run stops for a usage error, a missing engine, insufficient privilege or an unavailable image
- **THEN** the exit status is 2
- **AND** the status is documented as meaning that the engine was not tested

### Requirement: Test Selection
The suite SHALL support listing the available tests and running a subset
of them.

#### Scenario: List tests
- **WHEN** `--list` is passed
- **THEN** the suite prints each test name, one per line, and exits 0 without creating any resource

#### Scenario: Filter tests
- **WHEN** `--filter <pattern>` is passed
- **THEN** only tests whose name matches the pattern run
- **AND** the summary counts only those tests

#### Scenario: Filter matches nothing
- **WHEN** the pattern matches no test
- **THEN** the suite reports that no test was selected and exits with status 2

### Requirement: Usage Help
The suite SHALL document its own command line when asked.

#### Scenario: Help requested
- **WHEN** `-h` or `--help` is passed
- **THEN** every accepted option, its default and the meaning of each exit code are printed
- **AND** the exit status is 0
