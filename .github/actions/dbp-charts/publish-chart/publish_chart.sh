#!/bin/bash -e
HELM_REPO_BASE_URL="https://kubernetes-charts.alfresco.com"
CHART_VERSION=$(yq eval .version helm/"${PROJECT_NAME}"/Chart.yaml)

if [[ "$CHART_VERSION" == *"$ALPHA_SUFFIX"* ]]; then
  export HELM_REPO=incubator
else
  export HELM_REPO=stable
fi

COMMIT_MESSAGE="Publishing ${PROJECT_NAME} v${CHART_VERSION} on ${HELM_REPO} repo"
echo "$COMMIT_MESSAGE"
echo '---'

git config --global user.name "${GH_USERNAME}"
git config --global user.email "${GH_EMAIL}"
git clone https://"${GH_TOKEN}"@github.com/Alfresco/charts.git
echo using PROJECT_NAME="${PROJECT_NAME}",HELM_REPO="${HELM_REPO}"
mkdir repo
helm package --dependency-update --destination repo helm/"${PROJECT_NAME}"
helm repo index repo --url "${HELM_REPO_BASE_URL}"/"${HELM_REPO}" --merge charts/"${HELM_REPO}"/index.yaml
mv repo/* charts/"${HELM_REPO}"
cd charts
git add "${HELM_REPO}"
git commit -m "$COMMIT_MESSAGE"
git push --quiet origin master
