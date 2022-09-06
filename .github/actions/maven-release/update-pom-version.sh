#!/usr/bin/env bash

RELEASE_VERSION=${1:-$RELEASE_VERSION}
EXTRA_REPLACEMENTS=${2:-EXTRA_REPLACEMENTS}

POM_VERSION=$(yq -p=xml e '.project.version' pom.xml)
echo "Updating versions in pom.xml files: ${POM_VERSION} --> ${RELEASE_VERSION}"

SED_REPLACEMENTS="${SED_REPLACEMENTS} -e 's|<version>${POM_VERSION}</version>|<version>${RELEASE_VERSION}</version>|g'"
for PROPERTY in ${EXTRA_REPLACEMENTS//,/ }
do
  PROPERTY_NAME=${PROPERTY%=*}
  PROPERTY_VALUE=${PROPERTY#*=}
  echo "Property to be updated $PROPERTY_NAME: $PROPERTY_VALUE --> $RELEASE_VERSION"
  SED_REPLACEMENTS="${SED_REPLACEMENTS} -e 's|<$PROPERTY_NAME>${PROPERTY_VALUE}</$PROPERTY_NAME>|<$PROPERTY_NAME>${RELEASE_VERSION}</$PROPERTY_NAME>|g'"
done

if [[ "$OSTYPE" == "darwin"* ]]; then
  eval "find . -name pom.xml -exec sed -i.bak ${SED_REPLACEMENTS} {} \;"
  find . -name pom.xml.bak -delete
else
  eval "find . -name pom.xml -exec sed -i ${SED_REPLACEMENTS} {} \;"
fi

echo "Checking for occurrences of non final versions..."
grep -r '[0-9]*\.[0-9]*\.[0-9]*\-SNAPSHOT\|[0-9]*\.[0-9]*\.[0-9]*\-alpha\.[0-9]*' --include=pom.xml . \
  && echo "At least one occurrence of a non final version was found. Stopping the release..." && exit 1 \
  || echo "No occurrences of non final versions was found. Proceeding with the release..."
