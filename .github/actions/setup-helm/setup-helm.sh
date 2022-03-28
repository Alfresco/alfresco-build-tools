#!/bin/bash -e
HELM_VERSION=$1
WIN_PATH=${WIN_PATH:-$HOME/bin/}
LIN_PATH=${LIN_PATH:-/usr/local/bin/}
if [ "$RUNNER_OS" == "Windows" ]; then
    curl -fsSLo helm.zip https://get.helm.sh/helm-v${HELM_VERSION}-windows-amd64.zip
    unzip -o helm.zip windows-amd64/helm.exe && rm helm.zip && mv windows-amd64/helm.exe "${WIN_PATH}" && rmdir windows-amd64
elif [ "$RUNNER_OS" == "Linux" ]; then
    curl -fsSL https://get.helm.sh/helm-v${HELM_VERSION}-$(uname | tr '[:upper:]' '[:lower:]')-amd64.tar.gz | tar xz --strip=1 -C "${LIN_PATH}" $(uname | tr '[:upper:]' '[:lower:]')-amd64/helm
else
    echo "$RUNNER_OS not supported"
    exit 1
fi

echo helm $(helm version --client --short) has been installed
