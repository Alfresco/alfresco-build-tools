#!/bin/bash -e

COMPOSE_FILE=$(basename $COMPOSE_FILE_PATH)
COMPOSE_PATH=$(dirname $COMPOSE_FILE_PATH)
COMPOSE_BIN="docker compose"

cd "$COMPOSE_PATH" || {
  echo "Error: docker compose dir not found"
  exit 1
}
docker info
$COMPOSE_BIN version
$COMPOSE_BIN -f "${COMPOSE_FILE}" config
echo "Starting Alfresco in docker compose"
$COMPOSE_BIN -f "${COMPOSE_FILE}" ps
if [ "$COMPOSE_PULL" = "true" ]; then
  $COMPOSE_BIN -f "${COMPOSE_FILE}" pull --quiet
fi
export COMPOSE_HTTP_TIMEOUT=120
$COMPOSE_BIN -f "${COMPOSE_FILE}" up -d --quiet-pull --wait

echo "All services are up and running... starting postman tests"

cd ..
docker run -a STDOUT --volume "${PWD}"/test/postman/docker-compose:/etc/newman --network host postman/newman:5.3 run "acs-test-docker-compose-collection.json" --global-var "protocol=http" --global-var "url=localhost:8080"

retVal=$?

[ "${retVal}" -eq 0 ] && echo "Postman tests were successful" || echo "Postman tests failed"
