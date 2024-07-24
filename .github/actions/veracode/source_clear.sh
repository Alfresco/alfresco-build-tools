#!/usr/bin/env bash

echo "=========================== Starting SourceClear Script ==========================="
PS4="\[\e[35m\]+ \[\e[m\]"
set +e -v -x

srcclr scan --loud > scan.log

SUCCESS=$?   # this will read exit code of the previous command

grep -e 'Full Report Details' -e 'Failed' scan.log

set +vex
echo "=========================== Finishing SourceClear Script =========================="

exit ${SUCCESS}
