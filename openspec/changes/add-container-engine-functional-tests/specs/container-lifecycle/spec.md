# Spec Delta

## Purpose

Verifies that the engine can take a container through its whole life —
created, running, paused, stopped and finally destroyed — and that the
container's observable state matches the transition that was requested.

## ADDED Requirements

### Requirement: Container Creation
The engine SHALL create a container from an openSUSE image without
starting it, and the created container SHALL be reported in the `created`
state.

#### Scenario: Create without running
- **WHEN** a container is created from the test image with a command that does not terminate
- **THEN** the create call succeeds and prints the container id
- **AND** the container is listed by the engine in state `created`
- **AND** no process of that container is running

#### Scenario: Created container is addressable by name
- **WHEN** the container was created with the run-unique name
- **THEN** a state query by that name returns the same container

### Requirement: Container Start
The engine SHALL start a created container, and the container SHALL then
be reported in the `running` state.

#### Scenario: Start a created container
- **WHEN** the created container is started
- **THEN** its reported state becomes `running` within the test timeout
- **AND** a command executed inside it succeeds

### Requirement: Container Pause and Unpause
The engine SHALL pause a running container, SHALL report it as `paused`,
and SHALL return it to `running` when unpaused.

#### Scenario: Pause a running container
- **WHEN** the running container is paused
- **THEN** its reported state becomes `paused`

#### Scenario: Unpause a paused container
- **WHEN** the paused container is unpaused
- **THEN** its reported state returns to `running`
- **AND** a command executed inside it succeeds again

#### Scenario: Pause unsupported by the host
- **WHEN** the host kernel offers no freezer for the engine to use and the pause call fails for that reason
- **THEN** the test reports a skip naming the missing freezer support

### Requirement: Container Stop
The engine SHALL stop a running container, and the stopped container
SHALL be reported in a non-running state while remaining listable.

#### Scenario: Stop a running container
- **WHEN** the running container is stopped
- **THEN** its reported state is no longer `running`
- **AND** the container is still listed when stopped containers are included

#### Scenario: Stopping twice is harmless
- **WHEN** a stop is issued against an already stopped container
- **THEN** the call succeeds
- **AND** the container state is unchanged

### Requirement: Exit Code Propagation
The engine SHALL report the exit status of the container's command as the
exit status of a foreground run.

#### Scenario: Successful command
- **WHEN** a container is run in the foreground with a command that exits 0
- **THEN** the engine exits 0

#### Scenario: Failing command
- **WHEN** a container is run in the foreground with a command that exits 42
- **THEN** the engine exits 42

### Requirement: Container Destruction
The engine SHALL remove a stopped container on request and SHALL refuse
to remove a running one unless removal is forced.

#### Scenario: Remove a stopped container
- **WHEN** the stopped container is removed
- **THEN** the call succeeds
- **AND** the container is no longer listed, including when stopped containers are included
- **AND** a state query for its name fails

#### Scenario: Removing a running container is refused
- **WHEN** removal is requested for a running container without the force option
- **THEN** the call fails with a non-zero status
- **AND** the container is still running afterwards

#### Scenario: Forced removal
- **WHEN** removal of that running container is requested with the force option
- **THEN** the call succeeds and the container is no longer listed
