#!/bin/bash +e
#

out_of_ns_ingress_cleanup() {
  echo "Something went wrong uninstalling ingress release... Need to do some cleanup"
  for i in clusterrole clusterrolebindings; do kubectl delete "$i" "ing-${RELEASE_PREFIX}-${GITHUB_RUN_NUMBER}-ingress-nginx"
  done
}

echo "cleaning up releases"
helm delete "ing-${GITHUB_RUN_NUMBER}" -n "${K8SNS}" || out_of_ns_ingress_cleanup
helm delete "acs-${RELEASE_PREFIX}-${GITHUB_RUN_NUMBER}" -n "${K8SNS}"
kubectl delete secret quay-registry-secret -n "${K8SNS}"
kubectl delete namespace "${K8SNS}" --grace-period=1
