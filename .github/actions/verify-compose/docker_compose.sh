#!/bin/bash -e

if [ -z "${COMPOSE_FILE_PATH}" ]; then
  echo "COMPOSE_FILE_PATH variable is not set"
  exit 2
fi
if [ -z "${COMMIT_MESSAGE}" ]; then
  echo "COMMIT_MESSAGE variable is not set"
  exit 2
fi
if [ -z "${BRANCH_NAME}" ]; then
  echo "BRANCH_NAME variable is not set"
  exit 2
fi

GIT_DIFF=$(git diff origin/master --name-only .)
COMPOSE_FILE=$(basename $COMPOSE_FILE_PATH)
COMPOSE_PATH=$(dirname $COMPOSE_FILE_PATH)
alf_port=8080

if [[ "${BRANCH_NAME}" == "master" ]] ||
  [[ "${COMMIT_MESSAGE}" == *"[run all tests]"* ]] ||
  [[ "${COMMIT_MESSAGE}" == *"[release]"* ]] ||
  [[ "${GIT_DIFF}" == *$COMPOSE_FILE* ]] ||
  [[ "${GIT_DIFF}" == *test/postman/docker-compose* ]]; then
  echo "deploying..."
else
  exit 0
fi

cd "$COMPOSE_PATH" || {
  echo "Error: docker compose dir not found"
  exit 1
}
docker info
docker-compose --version
docker-compose -f "${COMPOSE_FILE}" config
echo "Starting Alfresco in docker compose"
docker-compose ps
docker-compose -f "${COMPOSE_FILE}" pull
export COMPOSE_HTTP_TIMEOUT=120
docker-compose -f "${COMPOSE_FILE}" up -d
# docker-compose up
WAIT_INTERVAL=1
COUNTER=0
TIMEOUT=300
t0=$(date +%s)
echo "Waiting for alfresco to start"
response=$(curl --write-out %{http_code} --output /dev/null --silent http://localhost:"${alf_port}"/alfresco/)
until [[ "200" -eq "${response}" ]] || [[ "${COUNTER}" -eq "${TIMEOUT}" ]]; do
  printf '.'
  sleep "${WAIT_INTERVAL}"
  COUNTER=$((COUNTER + WAIT_INTERVAL))
  response=$(curl --write-out %{http_code} --output /dev/null --silent http://localhost:"${alf_port}"/alfresco/)
done
if (("${COUNTER}" < "${TIMEOUT}")); then
  t1=$(date +%s)
  delta=$(((t1 - t0) / 60))
  echo "Alfresco Started in ${delta} minutes"
else
  echo "Waited ${COUNTER} seconds"
  echo "Alfresco could not start in time."
  echo "The last response code from /alfresco/ was ${response}"
  exit 1
fi
COUNTER=0
echo "Waiting for share to start"
response=$(curl --write-out %{http_code} --output /dev/null --silent http://localhost:8080/share/page)
until [[ "200" -eq "${response}" ]] || [[ "${COUNTER}" -eq "${TIMEOUT}" ]]; do
  printf '.'
  sleep "${WAIT_INTERVAL}"
  COUNTER=$((COUNTER + WAIT_INTERVAL))
  response=$(curl --write-out %{http_code} --output /dev/null --silent http://localhost:8080/share/page)
done
if (("${COUNTER}" < "${TIMEOUT}")); then
  t1=$(date +%s)
  delta=$(((t1 - t0) / 60))
  echo "Share Started in ${delta} minutes"
else
  echo "Waited ${COUNTER} seconds"
  echo "Share could not start in time."
  echo "The last response code from /share/ was ${response}"
  exit 1
fi
COUNTER=0
TIMEOUT=20
echo "Waiting more time for SOLR"
response=$(curl --write-out %{http_code} --user admin:admin --output /dev/null --silent http://localhost:"${alf_port}"/alfresco/s/api/solrstats)
until [[ "200" -eq "${response}" ]] || [[ "${COUNTER}" -eq "${TIMEOUT}" ]]; do
  printf '.'
  sleep "${WAIT_INTERVAL}"
  COUNTER=$((COUNTER + WAIT_INTERVAL))
  response=$(curl --write-out %{http_code} --user admin:admin --output /dev/null --silent http://localhost:"${alf_port}"/alfresco/s/api/solrstats)
done

cd ..
docker run -a STDOUT --volume "${PWD}"/test/postman/docker-compose:/etc/newman --network host postman/newman:5.3 run "acs-test-docker-compose-collection.json" --global-var "protocol=http" --global-var "url=localhost:8080"
retVal=$?
if [ "${retVal}" -ne 0 ]; then
  # show logs
  docker-compose logs --no-color
  exit 1
fi
