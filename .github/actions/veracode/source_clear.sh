#!/usr/bin/env bash

echo "=========================== Starting SourceClear Script ==========================="
PS4="\[\e[35m\]+ \[\e[m\]"
set +e -v -x

srcclr scan \
  --scm-uri="$SRCCLR_SCM_URI" \
  --scm-ref="$SRCCLR_SCM_REF" \
  --scm-ref-type="$SRCCLR_SCM_REF_TYPE" \
  --scm-rev="$SRCCLR_SCM_REV" > scan.log

SUCCESS=$?   # this will read exit code of the previous command

grep -e 'Full Report Details' scan.log

set +vex
echo "=========================== Finishing SourceClear Script =========================="

exit ${SUCCESS}
