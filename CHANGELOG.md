# cluster_ping 4.0.2 (2025-07-21)

### Features

- Added example use case for the tool.
- Port project to zig.

  The port to zig brings many advantages to the tool, being faster for one, but also a single binary.
- Validate flag

  The command to validate the cluster connection status has been add.

### Improved Documentation

- Update readme to match changes made due to the port

### Misc

- Add the check connection to the cluster as a command line input.
- upgrade pre-commit check versions


# Cluster_Ping 0.1.1 (2024-10-04)

### Bugfixes

- address edge case of data being a none type

### Misc

- document the step for the release process


# Cluster_Ping 0.1.0 (2024-09-12)

### Features

- Initial version of the cluster_ping entry point.
- Setup change log using towncrier

### Improved Documentation

- add some docs around the development setup

### Misc

- add unit test to ensure versions of package matches the pyproject version
