setup() {
    DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"
    SCRIPT="$DIR/../setup-helm.sh"

    WORK_DIR="$(mktemp -d)"
    export GITHUB_OUTPUT="$WORK_DIR/output"
    export GITHUB_PATH="$WORK_DIR/path"
    export INSTALL_DIR="$WORK_DIR/bin"
    export BASE_URL="file://$WORK_DIR/mirror"
    : > "$GITHUB_OUTPUT"
    : > "$GITHUB_PATH"
    unset VERSION VERSION_FILE

    OS=$(uname | tr '[:upper:]' '[:lower:]')
    case $(uname -m) in
        x86_64) ARCH=amd64 ;;
        aarch64 | arm64) ARCH=arm64 ;;
    esac

    publish_fake_helm 4.2.3
}

teardown() {
    rm -rf "$WORK_DIR"
}

# Mimics a get.helm.sh release: tarball with OS-ARCH/helm plus its .sha256sum
publish_fake_helm() {
    local version=$1
    local tarball="helm-v${version}-${OS}-${ARCH}.tar.gz"
    local staging="$WORK_DIR/staging/${OS}-${ARCH}"
    mkdir -p "$staging" "$WORK_DIR/mirror"
    printf '#!/bin/sh\necho "v%s"\n' "$version" > "$staging/helm"
    chmod +x "$staging/helm"
    tar -czf "$WORK_DIR/mirror/$tarball" -C "$WORK_DIR/staging" "${OS}-${ARCH}"
    (cd "$WORK_DIR/mirror" && shasum -a 256 "$tarball" > "$tarball.sha256sum")
    rm -rf "$WORK_DIR/staging"
}

@test "installs the requested version and adds it to the PATH" {
    export VERSION=4.2.3

    run "$SCRIPT"

    [ "$status" -eq 0 ]
    [ "$("$INSTALL_DIR/helm")" = "v4.2.3" ]
    grep -qx "$INSTALL_DIR" "$GITHUB_PATH"
    grep -qx "version=4.2.3" "$GITHUB_OUTPUT"
}

@test "accepts a version with a leading v" {
    export VERSION=v4.2.3

    run "$SCRIPT"

    [ "$status" -eq 0 ]
    grep -qx "version=4.2.3" "$GITHUB_OUTPUT"
}

@test "reads the helm version from a .tool-versions file" {
    publish_fake_helm 3.19.0
    cat > "$WORK_DIR/.tool-versions" <<EOF
# pinned tools
nodejs 24.11.0
helm   3.19.0 # comment after the version
kubectl 1.34.2
EOF
    export VERSION_FILE="$WORK_DIR/.tool-versions"

    run "$SCRIPT"

    [ "$status" -eq 0 ]
    [ "$("$INSTALL_DIR/helm")" = "v3.19.0" ]
    grep -qx "version=3.19.0" "$GITHUB_OUTPUT"
}

@test "fails when the version file has no helm entry" {
    echo "nodejs 24.11.0" > "$WORK_DIR/.tool-versions"
    export VERSION_FILE="$WORK_DIR/.tool-versions"

    run "$SCRIPT"

    [ "$status" -ne 0 ]
    [[ "$output" == *"No helm version found in $VERSION_FILE"* ]]
}

@test "fails when the version file does not exist" {
    export VERSION_FILE="$WORK_DIR/missing"

    run "$SCRIPT"

    [ "$status" -ne 0 ]
    [[ "$output" == *"$VERSION_FILE not found"* ]]
}

@test "fails when neither version nor version file is set" {
    run "$SCRIPT"

    [ "$status" -ne 0 ]
    [[ "$output" == *"Set either version or version-file"* ]]
}

@test "fails when both version and version file are set" {
    echo "helm 4.2.3" > "$WORK_DIR/.tool-versions"
    export VERSION=4.2.3
    export VERSION_FILE="$WORK_DIR/.tool-versions"

    run "$SCRIPT"

    [ "$status" -ne 0 ]
    [[ "$output" == *"Set either version or version-file"* ]]
}

@test "rejects a version that is not an exact release" {
    export VERSION=latest

    run "$SCRIPT"

    [ "$status" -ne 0 ]
    [[ "$output" == *"Invalid helm version: latest"* ]]
}

@test "fails and installs nothing when the checksum does not match" {
    echo "0000000000000000000000000000000000000000000000000000000000000000  helm-v4.2.3-${OS}-${ARCH}.tar.gz" \
        > "$WORK_DIR/mirror/helm-v4.2.3-${OS}-${ARCH}.tar.gz.sha256sum"
    export VERSION=4.2.3

    run "$SCRIPT"

    [ "$status" -ne 0 ]
    [ ! -e "$INSTALL_DIR/helm" ]
    [ ! -s "$GITHUB_PATH" ]
}

@test "fails when the release does not exist" {
    export VERSION=9.9.9

    run "$SCRIPT"

    [ "$status" -ne 0 ]
    [ ! -e "$INSTALL_DIR/helm" ]
}
