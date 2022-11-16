#!/bin/bash -e

HELM_REPO_BASE_URL="https://kubernetes-charts.alfresco.com"
CHART_VERSION=$(yq eval .version helm/"${PROJECT_NAME}"/Chart.yaml)

if [[ "${RELEASE_TYPE}" == "stable" ]]; then
  export HELM_REPO=stable
else
  export HELM_REPO=incubator
  ALPHA_BUILD_VERSION="${CHART_VERSION%-*}-${ALPHA_SUFFIX}"
  echo "Changing Chart version to ${ALPHA_BUILD_VERSION} as this is a feature branch..."
  sed -i s,"${CHART_VERSION}","${ALPHA_BUILD_VERSION}",g helm/"${PROJECT_NAME}"/Chart.yaml
fi

COMMIT_MESSAGE_FIRST_LINE=$(git log --pretty=format:%s --max-count=1)
echo using COMMIT_MESSAGE_FIRST_LINE="${COMMIT_MESSAGE_FIRST_LINE}"
git config --global user.name "${GH_USERNAME}"
git config --global user.email "${GH_EMAIL}"
git clone https://"${GH_TOKEN}"@github.com/Alfresco/charts.git
echo using PROJECT_NAME="${PROJECT_NAME}",BRANCH="${BRANCH_NAME}",HELM_REPO="${HELM_REPO}"
mkdir repo
helm package --dependency-update --destination repo helm/"${PROJECT_NAME}"
helm repo index repo --url "${HELM_REPO_BASE_URL}"/"${HELM_REPO}" --merge charts/"${HELM_REPO}"/index.yaml
mv repo/* charts/"${HELM_REPO}"
cd charts
git add "${HELM_REPO}"
git commit -m "${COMMIT_MESSAGE_FIRST_LINE}"
git push --quiet origin master
