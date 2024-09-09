# Cluster_ping

This is a simple script to check if the user defined in a given kube config can ping the given cluster.
The result are currently saved to a yaml file in the operating systems temporary directory.

## Development

### Changelog
The change log is managed by [towncrier](https://towncrier.readthedocs.io).

### Git Hooks
The use of pre-commit is used to set up git hooks.
Use `pre-commit install` to install the hooks.

To run the hooks outside a commit using `pre-commit run -a`.

### Testing
`pytest` is the test runner.
Run tests with `pytest`.
