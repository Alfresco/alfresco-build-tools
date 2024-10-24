#!/bin/bash -e

COMPOSE_BIN="docker compose"

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

docker run -a STDOUT --volume ${POSTMAN_PATH}:/etc/newman --network host postman/newman:5.3 run ${POSTMAN_JSON} --global-var "protocol=http" --global-var "url=localhost:8080"

retVal=$?

[ "${retVal}" -eq 0 ] && echo "Postman tests were successful" || echo "Postman tests failed"
