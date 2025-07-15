# Examples

This directory contains example integrations and usage patterns for `cluster_ping`.

## Fish Shell Integration

### `current_cluster.fish`

This Fish shell function demonstrates how to integrate `cluster_ping` into your shell prompt to display real-time Kubernetes cluster connectivity status.

#### What it does:

1. **Detects active kubeconfig**: Uses the `$KUBECONFIG` environment variable or defaults to `~/.kube/config`
2. **Gets current context**: Extracts the current context and cluster name from the kubeconfig
3. **Runs background connectivity check**: Executes `cluster_ping check` in the background to test connectivity
4. **Validates recent results**: Uses `cluster_ping validate` to check if recent connectivity data exists
5. **Provides colored output**: Returns color-coded cluster information for shell prompts

#### Color coding:

- **🟢 Magenta**: Connected and recent data (active connection)
- **⚫ Black**: Not connected but recent check (inactive connection)  
- **🟡 Yellow**: Stale or no recent data (unknown status)

#### Usage:

Source this function in your Fish config:

```fish
# In ~/.config/fish/config.fish
source /path/to/examples/current_cluster.fish

# Then use in your prompt function
function fish_prompt
    # Your existing prompt...
    echo (current_cluster)
    # Rest of your prompt...
end
```

#### Configuration:

- **Delay**: Default 300 seconds (5 minutes) for data freshness
- **File prefix**: Shows config file path when using custom `$KUBECONFIG`
- **Error handling**: Returns non-zero exit code if kubeconfig file doesn't exist

#### Dependencies:

- `cluster_ping` binary in PATH
- `yq` for YAML parsing
- Fish shell 3.0+

This integration allows you to see your current Kubernetes cluster status directly in your shell prompt, with efficient caching to avoid repeated kubectl calls. 