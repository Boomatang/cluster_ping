# Cluster_ping

This is a simple tool to check if the user defined in a given kube config can connect to the given cluster.
The results are stored in a simple text file in the operating system's temporary directory for fast retrieval.

This is a Zig port of the original Python implementation, providing better performance and no runtime dependencies.

## Usage

### Installation

#### From Source
Clone the repository and build with Zig:
```sh
git clone <repository-url>
cd cluster_ping
zig build
```

The binary will be available at `zig-out/bin/cluster_ping`.

#### System Installation
You can install the binary to your system PATH:
```sh
zig build --prefix ~/.local  # Install to ~/.local/bin
# Or copy manually:
cp zig-out/bin/cluster_ping ~/.local/bin/
```

### Dependencies
The tool requires the following external commands to be available:
- `kubectl` - for testing cluster connectivity
- `yq` - for parsing YAML kubeconfig files

### Basic Usage
```sh
cluster_ping --help
```
This will display the help information.

#### Check Connectivity
To test connectivity to a cluster and store the result:
```sh
cluster_ping check <path/to/kube/config> <context-name>
```

#### Validate Recent Connectivity
To check if there's recent connectivity data (within 300 seconds by default):
```sh
cluster_ping validate <path/to/kube/config> <context-name>
```

You can specify a custom timeout in seconds:
```sh
cluster_ping validate <path/to/kube/config> <context-name> 600
```

### Shell Integration Example
See `examples/current_cluster.fish` for an example of how to integrate this into a Fish shell prompt. The script:
- Runs connectivity checks in the background
- Provides colored output based on connection status
- Shows cluster information in shell prompts

For detailed usage instructions and additional examples, see the [examples directory](examples/).

## Development

### Building
Build the project:
```sh
zig build
```

### Testing
Run the unit tests:
```sh
zig build test
```

### Running
Run the application directly:
```sh
zig build run -- check ~/.kube/config my-cluster
```

### Changelog
The change log is managed by [towncrier](https://towncrier.readthedocs.io).

### Code Quality
The project uses standard Zig formatting. Format code with:
```sh
zig fmt src/
```

## How It Works

1. **Check Command**: 
   - Prevents duplicate processes from running
   - Parses the kubeconfig file (YAML → JSON via `yq`)
   - Validates the user configuration
   - Tests connectivity using `kubectl version`
   - Stores results with timestamps in `/tmp/cluster_ping`

2. **Validate Command**:
   - Reads stored connectivity data
   - Checks if the data is recent (within specified delay)
   - Returns connection status and data freshness

The tool stores connectivity results in a simple format in `/tmp/cluster_ping`, allowing for fast retrieval without repeated kubectl calls.

## Output Format

The validate command outputs:
```
connected=<true|false> recent=<true|false>
```

This format is designed for easy parsing in shell scripts and prompt integrations.
