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
    if [[ "${COMMIT_MESSAGE}" != *"[keep env]"* ]]; then
      helm delete "${release_name_ingress}" "${release_name_aps}" -n "${namespace}"
      kubectl delete namespace "${namespace}" --grace-period=1
    fi
    return 1
  fi
}

newman() {
  # shellcheck disable=SC2048
  # shellcheck disable=SC2086
  for i in {1..5}; do
    docker run -t -v "${PWD}/test/postman:/etc/newman" postman/newman:5.3 $* && return 0
    echo "newman run failed, trying again ($i run)"
    sleep 10
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
