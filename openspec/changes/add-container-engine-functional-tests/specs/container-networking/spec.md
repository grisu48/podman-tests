# Spec Delta

## Purpose

Verifies that containers attached to a bridge network get working
connectivity: an address, name resolution, reachability to each other,
isolation from other networks, and ports published onto the host.

## ADDED Requirements

### Requirement: Bridge Network Creation
The engine SHALL create a user-defined bridge network on request and
SHALL list it afterwards.

#### Scenario: Create a bridge network
- **WHEN** a network of driver `bridge` is created with the run-unique name
- **THEN** the call succeeds
- **AND** the network appears in the engine's network listing with driver `bridge`

### Requirement: Container Network Interface
A container attached to a bridge network SHALL receive a network
interface with an IPv4 address that is not the loopback address.

#### Scenario: Interface is configured
- **WHEN** a container is run on the bridge network and reports its own interface addresses
- **THEN** an interface other than `lo` carries an IPv4 address
- **AND** the engine reports the same address for that container on that network

### Requirement: Container To Container Reachability
Two containers attached to the same bridge network SHALL be able to open
a TCP connection to each other.

#### Scenario: TCP connection over the bridge
- **WHEN** one container listens on a TCP port and a second container on the same network connects to the first container's IPv4 address on that port
- **THEN** the connection is established
- **AND** the payload served by the listener is received unchanged by the client

### Requirement: Network Name Resolution
Containers on a user-defined bridge network SHALL resolve each other by
container name.

#### Scenario: Reach a peer by name
- **WHEN** the client container connects to the listening container by its container name instead of its address
- **THEN** the name resolves to that container's address on the network
- **AND** the connection succeeds

#### Scenario: Unknown name does not resolve
- **WHEN** the client container resolves a name that belongs to no container on the network
- **THEN** the resolution fails

### Requirement: Network Isolation
A container SHALL NOT reach a container that is attached only to a
different bridge network.

#### Scenario: Cross-network connection is refused
- **WHEN** a second bridge network is created and a container on it attempts to connect to the listener on the first network
- **THEN** the connection does not succeed within the test timeout

### Requirement: Port Publishing
The engine SHALL publish a container port onto a host address, and a
client on the host SHALL reach the containerised service through it.

#### Scenario: Published port is reachable from the host
- **WHEN** a container serving HTTP is run with its port published to `127.0.0.1` on a free host port
- **AND** the host requests `/` from that address with its HTTP client, under a bounded connect and transfer timeout
- **THEN** the response status is 200
- **AND** the response body is the content served by the container

#### Scenario: Published port is reported
- **WHEN** the engine is asked for the container's port mapping
- **THEN** it reports the container port mapped to the chosen host address and port

#### Scenario: Unpublished port is not reachable
- **WHEN** the host connects to a port that was not published
- **THEN** the connection is refused or times out

### Requirement: Port Release
The engine SHALL release a published host port when the publishing
container stops.

#### Scenario: Port is free after the container stops
- **WHEN** the publishing container is stopped and removed
- **THEN** a host connection to the formerly published port no longer succeeds
- **AND** a new container may publish the same host port successfully
