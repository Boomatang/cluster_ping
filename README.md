# Cluster_ping

This is a simple script to check if the user defined in a given kube config can ping the given cluster.
The result are currently saved to a yaml file in the operating systems temporary directory.

## Usage
### Installation
It is recommended to use [pipx](https://pipx.pypa.io/latest/installation/) to manage the installation.
```sh
pipx install cluster_ping
```

The cluster_ping command should then be in the path.
```sh
cluster_ping --help
```
This will list the help and prove the installation was complete.

By running the cluster_ping with the path to a kude config and the name of a cluster a yaml file is created with the results of the ping.
This file is created in the standard temporary directory for the OS.
On Linux this is `/tmp/`.
```sh
cluster_ping <Path/to/kube/confing> <Cluster Name>
```

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

## Release Steps
1. Create a release branch
1. Run `towncrier build --draft` and review the outpout.
1. Check that the verion in the top level __init__.py file is correct. `bat cluster_ping/__init__.py`
1. Run `towncrier build` to update the change log
1. Check the changes in the `CHANGELOG.md`
1. Check in the updates to the Change log.
1. Publish to pypi `poetry publish --build`
1. Tag the branch with the release vesion.
1. Merge the release branch into main.
1. push change to remote
1. push release tag `git push origin <tag>
