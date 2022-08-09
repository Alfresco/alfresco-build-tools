#!/bin/bash -e

if [ -z "${COMMIT_MESSAGE}" ]; then
  echo "COMMIT_MESSAGE variable is not set"
  exit 2
fi
if [ -z "${ACM_CERTIFICATE}" ]; then
  echo "ACM_CERTIFICATE variable is not set"
  exit 2
fi
if [ -z "${AWS_SG}" ]; then
  echo "AWS_SG variable is not set"
  exit 2
fi
if [ -z "${GITHUB_RUN_NUMBER}" ]; then
  echo "GITHUB_RUN_NUMBER variable is not set"
  exit 2
fi
if [ -z "${DOMAIN}" ]; then
  echo "DOMAIN variable is not set"
  exit 2
fi
if [ -z "${BRANCH_NAME}" ]; then
  echo "BRANCH_NAME variable is not set"
  exit 2
fi

GIT_DIFF="$(git diff origin/master --name-only .)"
namespace=$(echo "${BRANCH_NAME}" | cut -c1-28 | tr /_ - | tr -d '[:punct:]' | awk '{print tolower($0)}')"-${GITHUB_RUN_NUMBER}"
release_name_ingress=aps-ing-"${GITHUB_RUN_NUMBER}"
release_name_aps=aps-"${GITHUB_RUN_NUMBER}"
HOST=${namespace}.${DOMAIN}

export values_file=helm/"${PROJECT_NAME}"/values.yaml

if [[ "${BRANCH_NAME}" == "master" ]] ||
  [[ "${COMMIT_MESSAGE}" == *"[run all tests]"* ]] ||
  [[ "${COMMIT_MESSAGE}" == *"[release]"* ]] ||
  [[ "${GIT_DIFF}" == *helm/${PROJECT_NAME}/templates* ]] ||
  [[ "${GIT_DIFF}" == *helm/${PROJECT_NAME}/charts* ]] ||
  [[ "${GIT_DIFF}" == *helm/${PROJECT_NAME}/requirements* ]] ||
  [[ "${GIT_DIFF}" == *${values_file}* ]] ||
  [[ "${GIT_DIFF}" == *test/postman/helm* ]]; then
  echo "deploying..."
else
  echo "::warning ::Skipping tests since we are not on master and no changes has been made to helm folder"
  exit 0
fi

# Main
(umask 066 && aws eks update-kubeconfig --name acs-cluster --region=eu-west-1)
prepare_namespace
kubectl create secret generic quay-registry-secret --from-file=.dockerconfigjson="${HOME}"/.docker/config.json --type=kubernetes.io/dockerconfigjson -n "${namespace}"

# install ingress
helm upgrade --install "${release_name_ingress}" --repo https://kubernetes.github.io/ingress-nginx ingress-nginx --version=4.0.18 \
  --set controller.scope.enabled=true \
  --set controller.scope.namespace="${namespace}" \
  --set rbac.create=true \
  --set controller.config."proxy-body-size"="100m" \
  --set controller.service.targetPorts.https=80 \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-backend-protocol"="http" \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-ssl-ports"="https" \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-ssl-cert"="${ACM_CERTIFICATE}" \
  --set controller.service.annotations."external-dns\.alpha\.kubernetes\.io/hostname"="${HOST}" \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-ssl-negotiation-policy"="ELBSecurityPolicy-TLS-1-2-2017-01" \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-security-groups"="${AWS_SG}" \
  --set controller.publishService.enabled=true \
  --set controller.admissionWebhooks.enabled=false \
  --set controller.ingressClassResource.enabled=false \
  --wait \
  --namespace "${namespace}"

# install acs
helm dep up helm/"${PROJECT_NAME}"
helm upgrade --install "${release_name_aps}" helm/"${PROJECT_NAME}" \
  --values="${values_file}" \
  --set externalPort="443" \
  --set externalProtocol="https" \
  --set externalHost="${HOST}" \
  --set persistence.enabled=true \
  --set persistence.storageClass.enabled=true \
  --set persistence.storageClass.name="nfs-client" \
  --set postgresql.persistence.existingClaim="" \
  --set global.alfrescoRegistryPullSecrets=quay-registry-secret \
  --wait \
  --timeout 20m0s \
  --namespace="${namespace}"

# check dns and pods
DNS_PROPAGATED=0
DNS_COUNTER=0
DNS_COUNTER_MAX=90
DNS_SLEEP_SECONDS=10

echo "Trying to perform a trace DNS query to prevent caching"
dig +trace "${HOST}" @8.8.8.8
while [ "${DNS_PROPAGATED}" -eq 0 ] && [ "${DNS_COUNTER}" -le "${DNS_COUNTER_MAX}" ]; do
  host "${HOST}" 8.8.8.8
  if [ "$?" -eq 1 ]; then
    DNS_COUNTER=$((DNS_COUNTER + 1))
    echo "DNS Not Propagated - Sleeping ${DNS_SLEEP_SECONDS} seconds"
    sleep "${DNS_SLEEP_SECONDS}"
  else
    echo "DNS Propagated"
    DNS_PROPAGATED=1
  fi
done

[ "${DNS_PROPAGATED}" -ne 1 ] && echo "DNS entry for ${HOST} did not propagate within expected time" && exit 1

pods_ready || exit 1

if [[ "${COMMIT_MESSAGE}" != *"[keep env]"* ]]; then
  helm delete "${release_name_ingress}" "${release_name_aps}" -n "${namespace}"
  kubectl delete namespace "${namespace}" --grace-period=1
fi
