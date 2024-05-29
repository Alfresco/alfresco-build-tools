module.exports = async ({github, context,ref,environment})=>{
  const perPage = 100;
  let page = 1;
  let allDeployments = [];
  while(true){
    const deployments = await github.rest.repos.listDeployments({
        owner: context.repo.owner,
        repo: context.repo.repo,
        ref: ref,
        per_page: perPage,
        page: page,
        environment: environment
      });

    allDeployments = [...allDeployments, ...deployments.data];
    if (!deployments.data.length) {
      break;
    }
      page++;
    }


    await Promise.all(
      allDeployments.map(async (deployment) => {
        await github.rest.repos.createDeploymentStatus({
          owner: context.repo.owner,
          repo: context.repo.repo,
          deployment_id: deployment.id,
          state: 'inactive'
        });
        return github.rest.repos.deleteDeployment({
          owner: context.repo.owner,
          repo: context.repo.repo,
          deployment_id: deployment.id
        });
      })
    );
}
