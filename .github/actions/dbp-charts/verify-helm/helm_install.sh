#!/bin/bash -e

if [ -n "$K8SNS" ]; then echo "Deploying in namespace $K8SNS"
  namespace=$K8SNS
else echo "Could not find a namespace set in the NS env variable"
  exit 3
fi

release_name_ingress="ing-${RELEASE_PREFIX}-${GITHUB_RUN_NUMBER}"
release_name="${RELEASE_PREFIX}-${GITHUB_RUN_NUMBER}"
HOST=${namespace}.${DOMAIN}

# pod status
pod_status() {
  kubectl get pods --namespace "${namespace}" -o=custom-columns=NAME:.metadata.name,STATUS:.status.phase,READY:.status.conditions[?\(@.type==\'Ready\'\)].status
}

# failed pods logs
failed_pod_logs() {
  pod_status | grep False | awk '{print $1}' | \
    while read pod; do
      echo -e '\e[1;31m' "${pod}" '\e[0m' && \
      kubectl get event --namespace "${namespace}" --field-selector involvedObject.name="${pod}"
      kubectl logs "${pod}" --namespace "${namespace}" --tail 1024
    done
}

wait_for_connection() {
  declare -ir MAX_SECONDS=600
  declare -ir TIMEOUT=$SECONDS+$MAX_SECONDS
  while [[ $SECONDS < $TIMEOUT ]] && [[ "${http_resp}" != "200" ]]; do
    local http_resp=$(curl -s -o - -I "${HOST}"/alfresco/ | grep HTTP/1.1 | awk '{print $2}')
    echo "http response=${http_resp} from ${HOST}/alfresco/"
    sleep 10
  done
}

# pods ready
pods_ready() {
  PODS_COUNTER=0
  PODS_COUNTER_MAX=60
  PODS_SLEEP_SECONDS=10

  while [ "${PODS_COUNTER}" -lt "${PODS_COUNTER_MAX}" ]; do
    totalpods=$(pod_status | grep -v NAME | wc -l | sed 's/ *//')
    readypodcount=$(pod_status | grep ' True' | wc -l | sed 's/ *//')
    if [ "${readypodcount}" -eq "${totalpods}" ]; then
      echo "     ${readypodcount}/${totalpods} pods ready now"
      pod_status
      echo "All pods are ready!"
      break
    fi
    PODS_COUNTER=$((PODS_COUNTER + 1))
    echo "just ${readypodcount}/${totalpods} pods ready now - sleeping ${PODS_SLEEP_SECONDS} seconds - counter ${PODS_COUNTER}"
    sleep "${PODS_SLEEP_SECONDS}"
    continue
  done

  if [ "${PODS_COUNTER}" -ge "${PODS_COUNTER_MAX}" ]; then
    pod_status
    echo "Pods did not start - failing build"
    failed_pod_logs
    return 1
  fi
}

newman() {
  # shellcheck disable=SC2048
  # shellcheck disable=SC2086
  for i in {1..5}; do
    docker run -t -v "${PWD}/test/postman:/etc/newman" postman/newman:5.3 $* && return 0
    echo "newman run failed, trying again ($i run)"
    sleep 120
  done
  return 1
}

prepare_namespace() {
  cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
    name: ${namespace}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: ${namespace}:psp
  namespace: ${namespace}
rules:
- apiGroups:
  - policy
  resourceNames:
  - kube-system
  resources:
  - podsecuritypolicies
  verbs:
  - use
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ${namespace}:psp:default
  namespace: ${namespace}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: ${namespace}:psp
subjects:
- kind: ServiceAccount
  name: default
  namespace: ${namespace}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ${namespace}:psp:${release_name_ingress}-nginx-ingress
  namespace: ${namespace}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: ${namespace}:psp
subjects:
- kind: ServiceAccount
  name: ${release_name_ingress}-nginx-ingress
  namespace: ${namespace}
---
EOF
}

# Main
(umask 066 && aws eks update-kubeconfig --name acs-cluster --region=eu-west-1)
prepare_namespace
kubectl create secret generic quay-registry-secret --from-file=.dockerconfigjson="${HOME}"/.docker/config.json --type=kubernetes.io/dockerconfigjson -n "${namespace}"

echo "Starting helm install of ${release_name_ingress} completed."

# install ingress
helm upgrade --install "${release_name_ingress}" --repo https://kubernetes.github.io/ingress-nginx ingress-nginx --version=4.2.5 \
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
  --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-extra-security-groups"="${AWS_SG}" \
  --set controller.publishService.enabled=true \
  --set controller.admissionWebhooks.enabled=false \
  --set controller.ingressClassResource.enabled=false \
  --wait \
  --namespace "${namespace}"

echo "Helm install of ${release_name_ingress} completed."

values_file="helm/${PROJECT_NAME}/values.yaml"
if [[ -n "${ACS_VERSION}" && "${ACS_VERSION}" != "latest" ]]; then
  values_file="helm/${PROJECT_NAME}/${ACS_VERSION}_values.yaml"
fi
echo "Using values file for deployment: ${values_file}"
export values_file

# install acs
helm dep up helm/"${PROJECT_NAME}"
helm upgrade --install "${release_name}" helm/"${PROJECT_NAME}" \
  --values="${values_file}" \
  --set global.tracking.sharedsecret="$(openssl rand -hex 24)" \
  --set global.alfrescoRegistryPullSecrets=quay-registry-secret \
  --set global.known_urls=https://${HOST} \
  --set repository.persistence.enabled=true \
  --set repository.persistence.storageClass="nfs-client" \
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

if [[ "${TEST_NEWMAN}" == "true" ]]; then
  # run acs checks
  wait_for_connection
  newman run helm/acs-test-helm-collection.json --global-var "protocol=https" --global-var "url=${HOST}"
  TEST_RESULT=$?
  echo "TEST_RESULT=${TEST_RESULT}"
  if [[ "${TEST_RESULT}" == "0" ]]; then
    TEST_RESULT=0
    # run sync service checks
    if [[ ${ACS_VERSION} != "community" ]]; then
      wait_for_connection
      newman run "helm/sync-service-test-helm-collection.json" --global-var "protocol=https" --global-var "url=${HOST}"
      TEST_RESULT=$?
      echo "TEST_RESULT=${TEST_RESULT}"
    fi

    if [[ "${TEST_RESULT}" == "0" ]] && [[ ${ACS_VERSION} == "latest" ]]; then
      # For checking if persistence failover is correctly working with our deployments
      # in the next phase we delete the acs and postgresql pods,
      # wait for k8s to recreate them, then check if the data created in the first test run is still there
      kubectl delete pod -l app="${release_name}"-alfresco-cs-repository,component=repository -n "${namespace}"
      kubectl delete pod -l app=postgresql-acs,release="${release_name}" -n "${namespace}"
      helm upgrade "${release_name}" helm/"${PROJECT_NAME}" \
        --wait \
        --timeout 10m0s \
        --reuse-values \
        --namespace="${namespace}"

      # check pods
      pods_ready || exit 1

      # run checks after pod deletion
      wait_for_connection
      newman run "helm/acs-validate-volume-collection.json" --global-var "protocol=https" --global-var "url=${HOST}"
      TEST_RESULT=$?
      echo "TEST_RESULT=${TEST_RESULT}"
    fi
  fi
fi

if [[ "${TEST_RESULT}" == "1" ]]; then
  echo "Tests failed, exiting"
  exit 1
fi
