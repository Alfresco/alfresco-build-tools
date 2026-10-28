setup() {
  export NEXUS_URL="https://nexus.example.test"
  export STAGING_REPOSITORY_ID="activiti-staging"
  export JAVA_VERSION="25"
  export CLOUDSMITH_NAMESPACE=""
  export MAVEN_DEPLOY_PLUGIN_MAJOR_VERSION="2"
  export CALLS="$BATS_TEST_TMPDIR/calls"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/mvn" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CALLS"
if [[ "$*" == *"https://maven.cloudsmith.io/"* ]]; then exit "${FAIL_CLOUDSMITH:-0}"; fi
exit "${FAIL_NEXUS:-0}"
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/mvn"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  SCRIPT="$BATS_TEST_DIRNAME/../deploy.sh"
}

@test "preserves Nexus-only Deploy Plugin 2 syntax without a trailing space" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$CALLS")" -eq 1 ]
  grep -q -- 'nexus-releases-staging-fixed::default::https://nexus.example.test/content/repositories/activiti-staging -Dhttp' "$CALLS"
}

@test "deploys both lifecycles with Deploy Plugin 3 and retains release signing" {
  export MAVEN_DEPLOY_PLUGIN_MAJOR_VERSION=3 CLOUDSMITH_NAMESPACE=hyland
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$CALLS")" -eq 2 ]
  grep -q -- 'nexus-releases-staging-fixed::https://nexus.example.test/content/repositories/activiti-staging' "$CALLS"
  grep -q '^deploy --batch-mode -DperformRelease.*cloudsmith::https://maven.cloudsmith.io/hyland/activiti-staging/.*upstreamThreads.cloudsmith=10' "$CALLS"
}

@test "fails before uploading when Cloudsmith is enabled for Deploy Plugin 2" {
  export CLOUDSMITH_NAMESPACE=hyland
  run bash "$SCRIPT"
  [ "$status" -ne 0 ]
  [ ! -f "$CALLS" ]
}

@test "does not upload to Cloudsmith when Nexus fails" {
  export MAVEN_DEPLOY_PLUGIN_MAJOR_VERSION=3 CLOUDSMITH_NAMESPACE=hyland FAIL_NEXUS=1
  run bash "$SCRIPT"
  [ "$status" -ne 0 ]
  [ "$(wc -l < "$CALLS")" -eq 1 ]
}

@test "propagates a Cloudsmith failure so the release cannot be tagged" {
  export MAVEN_DEPLOY_PLUGIN_MAJOR_VERSION=3 CLOUDSMITH_NAMESPACE=hyland FAIL_CLOUDSMITH=1
  run bash "$SCRIPT"
  [ "$status" -ne 0 ]
  [ "$(wc -l < "$CALLS")" -eq 2 ]
}

@test "Nexus step does not upload to Cloudsmith before OIDC authentication" {
  export MAVEN_DEPLOY_PLUGIN_MAJOR_VERSION=3 CLOUDSMITH_NAMESPACE=hyland
  run bash "$SCRIPT" nexus
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$CALLS")" -eq 1 ]
  ! grep -q 'maven.cloudsmith.io' "$CALLS"
}

@test "Cloudsmith step reuses the built reactor without repeating Nexus deployment" {
  export MAVEN_DEPLOY_PLUGIN_MAJOR_VERSION=3 CLOUDSMITH_NAMESPACE=hyland
  run bash "$SCRIPT" cloudsmith
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$CALLS")" -eq 1 ]
  grep -q '^deploy .*cloudsmith::https://maven.cloudsmith.io/hyland/activiti-staging/' "$CALLS"
}
