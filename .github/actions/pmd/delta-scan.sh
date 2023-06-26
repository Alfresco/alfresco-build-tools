#!/usr/bin/env bash
echo "=========================== Starting PMD Script ==========================="
set -e

# The git reference for the branch to merge the PR into.
target_ref=$1
# The git reference for the branch containing the PR changes.
head_ref=$2
# Set to "true" if an increase in PMD violations should cause the build to fail.
fail_on_new_issues=$3

# Requires pmd/pmd-github-action to have been executed already, as this will download PMD to this location.
run_pmd="/opt/hostedtoolcache/pmd/${PMD_VERSION}/x64/pmd-bin-${PMD_VERSION}/bin/run.sh"

# Create a temporary directory for storing files.
tmp_dir=$(mktemp -d)

# Create a list of the files changed by this PR.
baseline_ref=$(git merge-base "${target_ref}" "${head_ref}")
git diff --name-only ${baseline_ref} ${head_ref} > ${tmp_dir}/file-list.txt

# Run PMD against the baseline commit.
git checkout ${baseline_ref}
for file in $(cat ${tmp_dir}/file-list.txt)
do
    if [[ -f ${file} ]]
    then
        echo ${file} > ${tmp_dir}/old-files.txt
    fi
done
${run_pmd} pmd --cache ${tmp_dir}/pmd.cache --file-list ${tmp_dir}/old-files.txt -R ${ACTION_PATH}/pmd-ruleset.xml -r ${tmp_dir}/old_report.txt --fail-on-violation false
old_issue_count=$(cat ${tmp_dir}/old_report.txt | wc -l)

# Rerun PMD against the PR head commit.
git checkout ${head_ref}
for file in $(cat ${tmp_dir}/file-list.txt)
do
    if [[ -f ${file} ]]
    then
        echo ${file} > ${tmp_dir}/new-files.txt
    fi
done
${run_pmd} pmd --cache ${tmp_dir}/pmd.cache --file-list ${tmp_dir}/new-files.txt -R ${ACTION_PATH}/pmd-ruleset.xml -r ${tmp_dir}/new_report.txt --fail-on-violation false
new_issue_count=$(cat ${tmp_dir}/new_report.txt | wc -l)

# Display the differences between the two files in the log.
diff ${tmp_dir}/old_report.txt ${tmp_dir}/new_report.txt | true

# Tidy up.
rm -rf ${tmp_dir}

# Fail the build if there are more issues now than before.
if [[ ${new_issue_count} > ${old_issue_count} ]]
then
    echo "ERROR: Number of PMD issues in edited files increased from ${old_issue_count} to ${new_issue_count}"
    if [[ ${fail_on_new_issues} == "true" ]]
    then
        exit 1
    fi
else
    echo "Number of PMD issues in edited files went from ${old_issue_count} to ${new_issue_count}"
fi

set +e
echo "=========================== Finishing PMD Script =========================="
