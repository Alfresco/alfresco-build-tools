#!/bin/bash -e

COMPOSE_BIN="docker compose"

echo "Starting Alfresco in docker compose"
$COMPOSE_BIN -f "${COMPOSE_FILE_PATH}" ps
if [ "$COMPOSE_PULL" = "true" ]; then
  $COMPOSE_BIN -f "${COMPOSE_FILE_PATH}" pull --quiet
fi
export COMPOSE_HTTP_TIMEOUT=120
$COMPOSE_BIN -f "${COMPOSE_FILE_PATH}" up -d --quiet-pull --wait

echo "All services are up and running... starting postman tests"

docker run -a STDOUT --volume "$(realpath "${POSTMAN_PATH}"):/etc/newman" --network host postman/newman:5.3 run "${POSTMAN_JSON}" --global-var "protocol=http" --global-var "url=localhost:8080"
