#!/bin/bash -e

COMPOSE_FILE=$(basename $COMPOSE_FILE_PATH)
COMPOSE_PATH=$(dirname $COMPOSE_FILE_PATH)
COMPOSE_BIN="docker compose"
alf_port=8080

dump_all_compose_logs() {
  echo "Dumping logs for all containers"
  $COMPOSE_BIN -f "${COMPOSE_FILE}" logs --no-color
  exit 1
}

wait_result() {
  COMPONENT=$1
  if (("${COUNTER}" < "${TIMEOUT}")); then
    t1=$(date +%s)
    delta=$(((t1 - t0) / 60))
    echo "$COMPONENT Started in ${delta} minutes"
  else
    echo "Waited ${COUNTER} seconds"
    echo "$COMPONENT could not start in time."
    echo "The last response code was ${response}"
    dump_all_compose_logs
  fi
}

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
$COMPOSE_BIN -f "${COMPOSE_FILE}" up -d --quiet-pull

WAIT_INTERVAL=1
COUNTER=0
TIMEOUT=300
t0=$(date +%s)
echo "Waiting for alfresco to start"
response=$(curl --write-out '%{http_code}' --output /dev/null --silent http://localhost:"${alf_port}"/alfresco/ || true)
until [[ "200" -eq "${response}" ]] || [[ "${COUNTER}" -eq "${TIMEOUT}" ]]; do
  printf '.'
  sleep "${WAIT_INTERVAL}"
  COUNTER=$((COUNTER + WAIT_INTERVAL))
  response=$(curl --write-out '%{http_code}' --output /dev/null --silent http://localhost:"${alf_port}"/alfresco/ || true)
done
wait_result Alfresco

COUNTER=0
echo "Waiting for share to start"
response=$(curl --write-out '%{http_code}' --output /dev/null --silent http://localhost:8080/share/page || true)
until [[ "200" -eq "${response}" ]] || [[ "${COUNTER}" -eq "${TIMEOUT}" ]]; do
  printf '.'
  sleep "${WAIT_INTERVAL}"
  COUNTER=$((COUNTER + WAIT_INTERVAL))
  response=$(curl --write-out '%{http_code}' --output /dev/null --silent http://localhost:8080/share/page || true)
done
wait_result Share

if [ $($COMPOSE_BIN -f "${COMPOSE_FILE}" config | yq '.services.alfresco.environment.JAVA_OPTS | contains(" -Dindex.subsystem.name=solr6")') == "true" ]; then echo "Waiting more time for SOLR"
  COUNTER=0
  TIMEOUT=20

  response=$(curl --write-out '%{http_code}' --user admin:admin --output /dev/null --silent http://localhost:"${alf_port}"/alfresco/s/api/solrstats || true)
  until [[ "200" -eq "${response}" ]] || [[ "${COUNTER}" -eq "${TIMEOUT}" ]]; do
    printf '.'
    sleep "${WAIT_INTERVAL}"
    COUNTER=$((COUNTER + WAIT_INTERVAL))
    response=$(curl --write-out '%{http_code}' --user admin:admin --output /dev/null --silent http://localhost:"${alf_port}"/alfresco/s/api/solrstats || true)
  done
  wait_result Solr
fi

cd ..
docker run -a STDOUT --volume "${PWD}"/test/postman/docker-compose:/etc/newman --network host postman/newman:5.3 run "acs-test-docker-compose-collection.json" --global-var "protocol=http" --global-var "url=localhost:8080"

retVal=$?

[ "${retVal}" -eq 0 ] && echo "Postman tests were successful" || dump_all_compose_logs
