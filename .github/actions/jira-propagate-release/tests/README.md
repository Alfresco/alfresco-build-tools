# E2E test

To perform an end-to-end test, we need:

- 1 end-to-end dedicated ticket -> [OPSEXP-3885](https://hyland.atlassian.net/browse/OPSEXP-3885)
- 1 implementation ticket -> the one you are using to perform the action update
- a test repository -> [jira-propagate-release-test](https://github.com/Alfresco/jira-propagate-release-test)

## The scenario

1. make commits and PRs to the test repository
2. make a release
3. verify the target resources have been created/updated

## Tools needed

- git
- GitHub CLI

## Detailed steps

- In the commands below please use the implementation ticket as the JIRA ticket reference.

```bash
git clone git@github.com:Alfresco/jira-propagate-release-test.git
cd jira-propagate-release-test
./test-release.sh <JIRA_TICKET>
```

- When the script is done, it displays the GitHub release name
- Go to the [release page](https://github.com/Alfresco/jira-propagate-release-test/releases) and check the GitHub release exists
- Go to the [action page](https://github.com/Alfresco/jira-propagate-release-test/actions) and check the release workflow executed correctly for both Jira releases (2 separate steps)
- Go to the [OPSEXP releases page](https://hyland.atlassian.net/projects/OPSEXP?selectedItem=com.atlassian.jira.jira-projects-plugin%3Arelease-page) and check the new Jira releases have been added
- Go to the [E2E dedicated ticket](https://hyland.atlassian.net/browse/OPSEXP-3885) and check 2 fix versions matching the releases names have been added
- Go to the implementation ticket and check 2 fix versions matching the releases names have been added

If you've reached the last step without any issue, then the action works as expected.

## Cleanup

- Set the user and token for JIRA API as environment variables (JIRA_API_USER and JIRA_API_TOKEN)
- If you're using `alfresco-build-tools@hyland.com` you don't have to set the user, it is the default one
- Delete the created releases using the following command:

```bash
./jira_delete_release_by_name.sh <RELEASE_NAME>
```

- One starts with `test` and the other one starts with `Propagate Release Action Tests`
- The fix versions will be automatically deleted when the release is deleted, so no need to delete them manually
