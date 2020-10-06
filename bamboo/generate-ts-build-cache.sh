#!/bin/bash
set -ex

PWD=$(pwd)

if [[ $USE_CACHED_BOOTSTRAP == true ]]; then
  echo "*** Using cached bootstrap build dir"
  cd /cumulus/
  git fetch --all
  git checkout "$GIT_SHA"
else
  npm install
fi

# Bootstrap to generate the compiled files from TS
# npm run bootstrap-no-build

cd packages/checksum
npm run prepare

# Get a list of TS compiled files
npm run tsc:listEmittedFiles --silent | grep TSFILE | awk '{print $2}' | sed "s,$PWD/,,g" >> .ts-build-cache-files
cat .ts-build-cache-files

# Generate TS build cache artifact
tar cf ts-build-cache.tgz -T .ts-build-cache-files

ls -lah .
