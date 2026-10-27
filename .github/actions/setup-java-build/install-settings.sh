#!/bin/bash
set -e

if [ -f "$MAVEN_SETTINGS" ]; then
  echo "Installing Maven settings file found in the repository: $MAVEN_SETTINGS"
  mkdir -p ~/.m2
  cp "$MAVEN_SETTINGS" ~/.m2/settings.xml
else
  echo "No Maven settings file found at $MAVEN_SETTINGS; using Maven defaults"
fi
