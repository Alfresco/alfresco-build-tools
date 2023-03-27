const core = require('@actions/core');
const github = require('@actions/github');
const { Octokit } = require('@octokit/rest');
const octokit = new Octokit({auth: core.getInput('github_token')});

exports.extractPrNumber = extractPrNumber
function extractPrNumber(message) {
  // Check as a merge commit
  let res = message.match(/^Merge pull request \#(\d+)/);
  if (res) {
    return res[1]
  }
  // Check as a squash commit
  res = message.match(/ \(\#(\d+)\)$/m);
  if (res) {
    return res[1]
  }
  return '';
}

async function main() {
  core.debug(`The context info: ${JSON.stringify(github.context, undefined, 2)}`);
  const eventName = github.context.eventName;
  const payload = github.context.payload;

  let prNumber;
  switch (eventName) {
    case 'pull_request':
      prNumber = payload['number'];
      break;
    case 'push':
      const fullName = payload['repository']['full_name'];
      const [owner, repo] = fullName.split('/');
      const headCommit = payload['head_commit'];

      prNumber = extractPrNumber(headCommit['message']);
      if (prNumber === '') {
        const {data: pulls} = await octokit.pulls.list({
          owner: owner,
          repo: repo,
          direction: 'asc',
        });

        const pull = pulls.find(pull => {
          return pull['head']['sha'] === headCommit['id']
        });
        if (pull) {
          prNumber = pull['number'];
        }
      }
      break;
    default:
      throw new Error(`Unsupported event: ${eventName}`);
  }
  if (prNumber === '') {
    console.log('The PR number could not be found');
  }
  core.setOutput('number', prNumber);
}

main().catch(error => core.setFailed(error.message));
