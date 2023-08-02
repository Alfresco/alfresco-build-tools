#!/usr/bin/env bash

echo "=========================== Starting SourceClear Script ==========================="
PS4="\[\e[35m\]+ \[\e[m\]"
set +e -v -x

mvn -B -q clean install \
    -DskipTests \
    -Dmaven.javadoc.skip=true \
    com.srcclr:srcclr-maven-plugin:scan \
    -Dcom.srcclr.apiToken=${SRCCLR_API_TOKEN} > scan.log \
    $ADDITIONAL_SETTINGS

SUCCESS=$?   # this will read exit code of the previous command

grep -e 'Full Report Details' -e 'Failed' scan.log

set +vex
echo "=========================== Finishing SourceClear Script =========================="

exit ${SUCCESS}
