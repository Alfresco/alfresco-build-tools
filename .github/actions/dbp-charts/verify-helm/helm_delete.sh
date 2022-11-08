#!/bin/bash +e
echo "cleaning up releases"
helm delete "ing-${GITHUB_RUN_NUMBER}" "acs-${GITHUB_RUN_NUMBER}" -n "${K8SNS}"
kubectl delete secret quay-registry-secret -n "${K8SNS}"
kubectl delete namespace "${K8SNS}" --grace-period=1
