#!/usr/bin/env bash
echo "=========================== Starting PMD Script ==========================="
set -e

# The location of the PMD ruleset.
ruleset_location=$1
# The git reference for the branch to merge the PR into.
target_ref=$2
# The git reference for the branch containing the PR changes.
head_ref=$3
# Set to "true" if an increase in PMD violations should cause the build to fail.
fail_on_new_issues=$4

# Requires pmd/pmd-github-action to have been executed already, as this will download PMD to this location.
run_pmd="/opt/hostedtoolcache/pmd/${PMD_VERSION}/x64/pmd-bin-${PMD_VERSION}/bin/run.sh"

# Create a temporary directory for storing files.
tmp_dir=$(mktemp -d)

# Create a list of the files changed by this PR.
baseline_ref=$(git merge-base "${target_ref}" "${head_ref}")
git diff --name-only ${baseline_ref} ${head_ref} > ${tmp_dir}/file-list.txt
git diff ${baseline_ref} ${head_ref} > ${tmp_dir}/full-diff.txt

# Run PMD against the baseline commit.
git checkout ${baseline_ref}
old_file_count=0
for file in $(cat ${tmp_dir}/file-list.txt)
do
    if [[ -f ${file} ]]
    then
        echo ${file} >> ${tmp_dir}/old-files.txt
        old_file_count=$((old_file_count+1))
    fi
done
${run_pmd} pmd --cache ${tmp_dir}/pmd.cache --file-list ${tmp_dir}/old-files.txt -R ${ruleset_location} -r ${tmp_dir}/old_report.txt --fail-on-violation false
old_issue_count=$(cat ${tmp_dir}/old_report.txt | wc -l)
echo "${old_issue_count} issue(s) found in ${old_file_count} old file(s) on ${baseline_ref}"

# Rerun PMD against the PR head commit.
git checkout ${head_ref}
new_file_count=0
for file in $(cat ${tmp_dir}/file-list.txt)
do
    if [[ -f ${file} ]]
    then
        echo ${file} >> ${tmp_dir}/new-files.txt
        new_file_count=$((new_file_count+1))
    fi
done
${run_pmd} pmd --cache ${tmp_dir}/pmd.cache --file-list ${tmp_dir}/new-files.txt -R ${ruleset_location} -r ${tmp_dir}/new_report.txt --fail-on-violation false
new_issue_count=$(cat ${tmp_dir}/new_report.txt | wc -l)
echo "${new_issue_count} issue(s) found in ${new_file_count} updated file(s) on ${head_ref}"

# Display the differences between the two files in the log.
diff ${tmp_dir}/old_report.txt ${tmp_dir}/new_report.txt || true

# Tidy up.
rm -rf ${tmp_dir}

# Fail the build if there are more issues now than before.
if [[ ${new_issue_count} > ${old_issue_count} ]]
then
    echo "ERROR: Number of PMD issues in edited files increased from ${old_issue_count} to ${new_issue_count}"
    if [[ ${fail_on_new_issues} == "true" ]]
    then
        exit 1
    else
        echo "Increase in errors ignored as fail_on_new_issues set to ${fail_on_new_issues}"
    fi
else
    echo "Number of PMD issues in edited files went from ${old_issue_count} to ${new_issue_count}"
fi

# Store references to the files created.
echo "OLD_REPORT_FILE=${tmp_dir}/old_report.txt" >> "$GITHUB_ENV"
echo "NEW_REPORT_FILE=${tmp_dir}/new_report.txt" >> "$GITHUB_ENV"
echo "FULL_DIFF_FILE=${tmp_dir}/full-diff.txt" >> "$GITHUB_ENV"
echo "HEAD_REF=${head_ref}" >> "$GITHUB_ENV"
echo "BASELINE_REF=${baseline_ref}" >> "$GITHUB_ENV"

set +e
echo "=========================== Finishing PMD Script =========================="
