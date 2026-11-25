# Spec Delta

## Purpose

Verifies that the engine confines containers with SELinux on hosts where
SELinux is enforcing: container processes get a container domain, bind
mounts are relabelled when asked, and unlabelled mounts stay denied.

## ADDED Requirements

### Requirement: SELinux Precondition
The SELinux tests SHALL run only when the host enforces SELinux and the
engine has SELinux support enabled, and SHALL report a skip with the
reason otherwise.

#### Scenario: SELinux absent
- **WHEN** `/sys/fs/selinux/enforce` does not exist
- **THEN** each SELinux test reports a skip naming SELinux as unavailable

#### Scenario: SELinux permissive
- **WHEN** `/sys/fs/selinux/enforce` reads `0`
- **THEN** each SELinux test reports a skip naming permissive mode, because denials would not be enforced

#### Scenario: Engine SELinux support disabled
- **WHEN** the host enforces SELinux but the engine reports its SELinux support as disabled
- **THEN** each SELinux test reports a skip naming the engine setting

### Requirement: Container Process Label
A container process SHALL run in a confined SELinux domain that differs
from the unconfined domain of the engine's caller.

#### Scenario: Process carries a container domain
- **WHEN** a container reads `/proc/self/attr/current`
- **THEN** the value is a complete SELinux context
- **AND** its type field is a container type such as `container_t`

#### Scenario: Containers are separated by category
- **WHEN** two containers are started at the same time and each reads its own context
- **THEN** the two contexts carry different MCS category sets

### Requirement: Relabelled Bind Mount
A bind mount requested with the private relabel option SHALL be
readable and writable from inside the container.

#### Scenario: Relabelled mount is usable
- **WHEN** a host directory holding a known file is bind mounted with the `:Z` option and the container reads the file
- **THEN** the read succeeds with unchanged content
- **AND** a write into the same mount succeeds

#### Scenario: Relabel is applied on the host
- **WHEN** the host context of the directory is read before and after the container runs with `:Z`
- **THEN** the context afterwards carries a container file type
- **AND** it carries the MCS categories of the container that mounted it

### Requirement: Unlabelled Bind Mount Denial
A bind mount requested without any relabel option SHALL NOT be readable
from inside a confined container.

#### Scenario: Access without a label is denied
- **WHEN** the same host directory, carrying a non-container context, is bind mounted without `:Z` or `:z` and the container reads the file
- **THEN** the read fails with a permission error
- **AND** the host context of the directory is unchanged

#### Scenario: Label separation is enforced
- **WHEN** a directory relabelled for one container is mounted without relabelling into a second container with different categories
- **THEN** the second container cannot read it

### Requirement: Label Disabling
When SELinux separation is explicitly disabled for a container, that
container SHALL run unconfined with respect to the mount.

#### Scenario: Separation turned off
- **WHEN** a container is run with the security option that disables label separation and mounts the unlabelled directory
- **THEN** the read succeeds
- **AND** the container's own context is no longer a confined container type
