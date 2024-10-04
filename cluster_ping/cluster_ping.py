import argparse
import os
import subprocess  # nosec B404
import tempfile
from datetime import datetime
from pathlib import Path

import psutil
import yaml


def setup_args():
    parser = argparse.ArgumentParser(description="Check if current kude user can ping the current cluster")
    parser.add_argument("kubeconfig", help="path to kubeconfig file")
    parser.add_argument("cluster", help="name of cluster to ping")
    args = parser.parse_args()

    kubeconfig = Path(args.kubeconfig)
    if not kubeconfig.exists() and not kubeconfig.is_file():
        # kube config file does not exist
        exit(2)

    return kubeconfig, args.cluster


def can_connect(kubeconfig):
    env = os.environ.copy()
    env["KUBECONFIG"] = kubeconfig
    connected = True

    resp = subprocess.run(["kubectl", "version", "-o", "yaml"], capture_output=True, env=env)  # nosec B607, B603
    if len(resp.stderr) != 0:
        connected = False

    return connected


def write_data_file(kubeconfig, cluster, connected):
    data_file = Path(tempfile.gettempdir(), "cluster_ping.yaml")

    if not data_file.exists():
        data = {}
    else:
        with open(data_file) as df:
            data = yaml.safe_load(df)

    if data is None:
        return

    if not str(kubeconfig) in data:
        data.setdefault(str(kubeconfig), {})

    data[str(kubeconfig)][cluster] = {"connected": connected, "checked": str(datetime.now())}

    with open(data_file, "w") as df:
        df.write(yaml.dump(data))


def exit_if_running(kubeconfig: str, cluster: str):
    count = 0
    for process in psutil.process_iter():
        if process.name().startswith("python"):
            cmd = process.cmdline()
            if {kubeconfig, cluster} <= set(cmd):
                count += 1

            if count >= 2:
                exit()


def read_kubeconfig(kubeconfig, cluster):
    with open(kubeconfig) as kcf:
        kc = yaml.safe_load(kcf)

    if kc is None or not kc.get("current-context", False) == cluster:
        # the current context is not the same as the requested cluster
        exit(3)

    if kc.get("contexts", None) is None:
        exit()

    return kc


def get_user_and_server(kc, cluster):
    c_cluster = None
    for c in kc["contexts"]:
        if c["name"] == cluster:
            c_cluster = c["context"]["cluster"]
            user = c["context"]["user"]
            break

    if c_cluster is None:
        exit()

    for c in kc["clusters"]:
        if c["name"] == c_cluster:
            server = c["cluster"]["server"]

    if len(server) == 0:
        exit(4)

    return user


def none_user(kc, user):
    for u in kc["users"]:
        if u["name"] == user:
            if not u["user"]:
                return True
    return False


def action():
    kubeconfig, cluster = setup_args()
    exit_if_running(str(kubeconfig), cluster)
    kc = read_kubeconfig(kubeconfig, cluster)

    user = get_user_and_server(kc, cluster)

    if none_user(kc, user):
        write_data_file(kubeconfig, cluster, False)
        exit()

    connected = can_connect(kubeconfig)
    write_data_file(kubeconfig, cluster, connected)


if __name__ == "__main__":
    action()
