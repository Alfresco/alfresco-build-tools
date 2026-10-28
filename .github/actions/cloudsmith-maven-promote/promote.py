"""Promote complete Maven packages using Cloudsmith's API and an OIDC token."""

import json
import os
import re
import sys
import time
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlencode
from urllib.request import Request, urlopen


class Cloudsmith:
    def __init__(self, namespace, token):
        self.namespace = namespace
        self.token = token

    def request(self, repository, suffix="", data=None, params=None):
        path = f"{quote(self.namespace, safe='')}/{quote(repository, safe='')}/{suffix}"
        url = f"https://api.cloudsmith.io/v1/packages/{path}"
        if params:
            url += "?" + urlencode(params)
        request = Request(
            url,
            data=json.dumps(data).encode() if data is not None else None,
            headers={"X-Api-Key": self.token, "Content-Type": "application/json"},
        )
        try:
            with urlopen(request, timeout=30) as response:
                return json.load(response), response.headers
        except HTTPError as error:
            # Do not print request headers or response bodies containing credentials.
            raise RuntimeError(f"Cloudsmith API failed for {repository}: HTTP {error.code}") from None
        except URLError:
            raise RuntimeError(f"Cannot reach Cloudsmith API for {repository}") from None

    def packages(self, repository, group, version):
        query = f"format:maven AND maven_group_id:^{group}$ AND version:^{version}$"
        packages = []
        page = 1
        while True:
            items, headers = self.request(
                repository,
                params={"query": query, "page": page, "page_size": 100, "include_connected_repositories": "false"},
            )
            if not isinstance(items, list):
                raise RuntimeError("Cloudsmith returned an unexpected package listing")
            if any(item.get("format") != "maven" or item.get("version") != version for item in items):
                raise RuntimeError("Cloudsmith returned packages outside the requested release")
            packages.extend(items)
            total_pages = int(headers["X-Pagination-PageTotal"])
            if page >= total_pages:
                return packages
            page += 1

    def move(self, repository, package, destination):
        identifier = quote(package["slug_perm"], safe="")
        self.request(repository, suffix=f"{identifier}/move/", data={"destination": destination})


def by_name(packages):
    indexed = {package["name"]: package for package in packages}
    if len(indexed) != len(packages):
        raise RuntimeError("Duplicate Maven coordinates found; resolve them before promoting")
    return indexed


def ready(packages):
    for package in packages:
        if package.get("is_sync_failed") or package.get("is_quarantined"):
            raise RuntimeError(f"Package {package['name']} failed synchronization or is quarantined")
    return all(package.get("is_sync_completed") and package.get("is_downloadable") for package in packages)


def wait_for(fetch, accept, timeout):
    deadline = time.monotonic() + timeout
    while True:
        result = fetch()
        if accept(result):
            return result
        if time.monotonic() >= deadline:
            raise RuntimeError("Timed out waiting for the complete Cloudsmith release to be downloadable")
        time.sleep(min(10, max(0, deadline - time.monotonic())))


def promote(api, source, destination, group, version, timeout):
    def fetch():
        return api.packages(source, group, version), api.packages(destination, group, version)

    staged, released = wait_for(
        fetch,
        lambda result: bool(result[0] or result[1]) and ready(result[0] + result[1]),
        timeout,
    )
    staged_by_name, released_by_name = by_name(staged), by_name(released)
    if staged_by_name.keys() & released_by_name.keys():
        raise RuntimeError("Maven coordinates exist in staging and releases; refusing to overwrite a release")
    expected = staged_by_name.keys() | released_by_name.keys()
    print(f"Promoting {len(staged)} Maven packages; {len(released)} already released for {group}:{version}")
    # Materialize all pages before moving anything: deleting from a paginated source
    # while reading it would skip packages on subsequent pages.
    for package in staged:
        api.move(source, package, destination)
    wait_for(
        lambda: api.packages(destination, group, version),
        lambda result: expected <= by_name(result).keys() and ready(result),
        timeout,
    )
    print(f"Verified {len(expected)} downloadable Maven packages in {destination}")


def main():
    namespace = os.environ["CLOUDSMITH_NAMESPACE"]
    source = os.environ["SOURCE_REPOSITORY"]
    destination = os.environ["DESTINATION_REPOSITORY"]
    group = os.environ["MAVEN_GROUP"]
    version = os.environ["RELEASE_VERSION"]
    for value in (namespace, source, destination, group, version):
        if not re.fullmatch(r"[A-Za-z0-9_.+-]+", value):
            raise ValueError("Namespace, repository, group and version must be literal identifiers")
    timeout = int(os.environ["TIMEOUT_SECONDS"])
    if source == destination or version.endswith("-SNAPSHOT") or timeout <= 0:
        raise ValueError("Use distinct repositories, a release version and a positive timeout")
    token = os.environ["CLOUDSMITH_API_KEY"]
    if not token:
        raise ValueError("Authenticate with cloudsmith-auth before promotion")
    promote(Cloudsmith(namespace, token), source, destination, group, version, timeout)


if __name__ == "__main__":
    try:
        main()
    except (KeyError, ValueError, RuntimeError) as error:
        print(f"::error::{error}", file=sys.stderr)
        sys.exit(1)
