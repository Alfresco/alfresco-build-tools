#!/usr/bin/env python3

import os
import subprocess
import sys

import rancher

RANCHER2_ACCESS_KEY = os.getenv("RANCHER2_ACCESS_KEY")
RANCHER2_SECRET_KEY = os.getenv("RANCHER2_SECRET_KEY")
CLUSTER_NAME = os.getenv("CLUSTER_NAME")
RANCHER2_URL = os.getenv("RANCHER2_URL") + "/v3"

# The first time the API was called, it doesn't work.
_client = rancher.Client(url=RANCHER2_URL, access_key=RANCHER2_ACCESS_KEY, secret_key=RANCHER2_SECRET_KEY)

client = rancher.Client(url=RANCHER2_URL, access_key=RANCHER2_ACCESS_KEY, secret_key=RANCHER2_SECRET_KEY)


def register_cluster():
    """Register cluster to rancher"""
    for cluster in client.list_cluster():
        if cluster["name"] == CLUSTER_NAME:
            if cluster["state"] == "active":
                print(f"Cluster {CLUSTER_NAME} already registered, skip register")
                return
            print(f"Trying to register {CLUSTER_NAME} cluster...")
            registation_token = client.list_cluster_registration_token(clusterId=cluster["id"])
            cmd = registation_token["data"][0]["command"]
            subprocess.run(cmd, shell=True)
            return
    print(f"Cluster {CLUSTER_NAME} not found, doing nothing")


def get_cluster_id():
    """Get cluster id based on cluster name"""
    for cluster in client.list_cluster():
        if cluster["name"] == CLUSTER_NAME:
            return cluster["id"]
    return False


def detach_cluster():
    """Detach cluster from rancher"""
    cluster_id = get_cluster_id()
    if cluster_id:
        cluster = client.by_id_cluster(cluster_id)
        client.delete(cluster)
        print(f"Cluster {CLUSTER_NAME} detach sent")
    else:
        print(f"Cluster {CLUSTER_NAME} not found, nothing to detach")


if __name__ == "__main__":
    option = sys.argv[1]

    # register require kubeconfig setup
    if option == "register":
        register_cluster()
    elif option == "detach":
        detach_cluster()
