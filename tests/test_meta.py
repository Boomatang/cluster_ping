import tomllib
from pathlib import Path

import cluster_ping


def test_release_version():
    pyproject_file = Path(__file__).parent.parent / "pyproject.toml"
    with open(pyproject_file, "rb") as pf:
        data = tomllib.load(pf)
        version = data["tool"]["poetry"]["version"]

    assert cluster_ping.__version__ == version, "Vesrion of the library is not the same as the project version"
