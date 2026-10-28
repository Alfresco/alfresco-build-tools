#!/usr/bin/env bash
set -euo pipefail

major="${MAVEN_DEPLOY_PLUGIN_MAJOR_VERSION:-2}"
target="${1:-both}"
case "$target" in
  nexus|cloudsmith|both) ;;
  *) echo "Unknown deployment target: $target" >&2; exit 1 ;;
esac
case "$major" in
  2) nexus_repository="nexus-releases-staging-fixed::default::${NEXUS_URL}/content/repositories/${STAGING_REPOSITORY_ID}" ;;
  3) nexus_repository="nexus-releases-staging-fixed::${NEXUS_URL}/content/repositories/${STAGING_REPOSITORY_ID}" ;;
  *) echo "Unsupported Maven Deploy Plugin major version: $major" >&2; exit 1 ;;
esac

if [[ -n "${CLOUDSMITH_NAMESPACE:-}" && "$major" != 3 ]]; then
  echo "Cloudsmith dual publishing requires Maven Deploy Plugin 3.x." >&2
  exit 1
fi

args=(--batch-mode -DperformRelease -DskipTests "-Dmaven.compiler.release=${JAVA_VERSION}" -Dmaven.artifact.threads=30)
if [[ "$target" != cloudsmith ]]; then
  echo "Deploying release to Nexus ${STAGING_REPOSITORY_ID}"
  mvn clean deploy "${args[@]}" \
    "-DaltReleaseDeploymentRepository=${nexus_repository}" \
    -Dhttp.keepAlive=false -Dmaven.wagon.http.pool=false -Dmaven.wagon.httpconnectionManager.ttlSeconds=120
fi

if [[ "$target" != nexus && -n "${CLOUDSMITH_NAMESPACE:-}" ]]; then
  echo "Deploying release to Cloudsmith ${STAGING_REPOSITORY_ID}"
  # Run the lifecycle again to retain attached sources, signatures and other artifacts.
  # Both deployments must succeed before the calling action commits or tags the release.
  mvn deploy "${args[@]}" \
    "-DaltReleaseDeploymentRepository=cloudsmith::https://maven.cloudsmith.io/${CLOUDSMITH_NAMESPACE}/${STAGING_REPOSITORY_ID}/" \
    -Daether.connector.basic.upstreamThreads.cloudsmith=10
fi
