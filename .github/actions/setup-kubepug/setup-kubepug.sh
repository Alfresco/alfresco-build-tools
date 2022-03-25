#!/bin/bash -e
KUBEPUG_VERSION=$1
if [[ "$RUNNER_OS" == "Windows" ]]; then
    curl -fsSLo kubepug.zip https://github.com/rikatz/kubepug/releases/download/v${KUBEPUG_VERSION}/kubepug_windows_amd64.zip
    unzip -o kubepug.zip kubepug.exe && rm kubepug.zip && mv kubepug.exe $HOME/bin/
elif [ "$RUNNER_OS" == "Linux" ]; then
    curl -fsSL https://github.com/rikatz/kubepug/releases/download/v${KUBEPUG_VERSION}/kubepug_$(uname | tr '[:upper:]' '[:lower:]')_amd64.tar.gz | tar xz -C /usr/local/bin/ kubepug
else
    echo "$RUNNER_OS not supported"
    exit 1
fi

kubepug version