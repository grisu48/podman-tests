# Spec Delta

## Purpose

Verifies that the engine can give containers persistent storage: named
volumes and host bind mounts that are writable from inside a container
and whose contents outlive the container that wrote them.

## ADDED Requirements

### Requirement: Volume Creation
The engine SHALL create a named volume on request and SHALL list it
afterwards.

#### Scenario: Create a named volume
- **WHEN** a volume is created with the run-unique name
- **THEN** the call succeeds
- **AND** the volume appears in the engine's volume listing

### Requirement: Volume Attachment
The engine SHALL attach a named volume to a container at the requested
mount point, and the mount point SHALL be writable from inside the
container.

#### Scenario: Write into a mounted volume
- **WHEN** a container is run with the volume mounted at a test path and writes a file with known content there
- **THEN** the container's write command exits 0

#### Scenario: Mount point is a mount
- **WHEN** the container inspects its own mount table
- **THEN** the requested mount point is listed as a mount and not as part of the image's root filesystem

### Requirement: Volume Persistence
Data written to a named volume SHALL remain readable after the writing
container is removed, and SHALL be visible to a second container that
mounts the same volume.

#### Scenario: Data survives the container
- **WHEN** the container that wrote the file is removed and a second container mounts the same volume at the same path
- **THEN** the second container reads back the exact content that was written

#### Scenario: Volume is independent of the mount path
- **WHEN** the second container mounts the volume at a different path
- **THEN** the file is found under that different path with unchanged content

### Requirement: Bind Mount
The engine SHALL mount a host directory into a container, and writes made
inside the container SHALL be visible on the host.

#### Scenario: Host directory is visible inside
- **WHEN** a host directory holding a known file is bind mounted into a container
- **THEN** the container reads that file with unchanged content

#### Scenario: Container writes are visible on the host
- **WHEN** the container writes a new file into the bind mount and exits
- **THEN** the file exists on the host with the content the container wrote

#### Scenario: Read-only bind mount
- **WHEN** the bind mount is requested read-only and the container attempts to write into it
- **THEN** the write fails
- **AND** the host directory is unchanged

### Requirement: Volume Removal
The engine SHALL remove a named volume once no container uses it, and
SHALL refuse to remove one that is still in use.

#### Scenario: Remove an unused volume
- **WHEN** removal is requested for the volume after all its containers are gone
- **THEN** the call succeeds
- **AND** the volume no longer appears in the volume listing

#### Scenario: Removal while in use is refused
- **WHEN** removal is requested while a running container still mounts the volume
- **THEN** the call fails with a non-zero status
- **AND** the volume still appears in the volume listing
