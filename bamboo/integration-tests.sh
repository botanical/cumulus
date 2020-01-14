#!/bin/bash
set -ex
. ./bamboo/abort-if-not-pr-or-redeployment.sh
. ./bamboo/set-bamboo-env-variables.sh
. ./bamboo/abort-if-skip-integration-tests.sh

if [[ $USE_CACHED_BOOTSTRAP == true ]]; then ## Change into cached cumulus dir
  echo "*** Using cached bootstrap build dir"
  cd /cumulus/
fi

### confirmLock will fail if another stack has lock, *redeploy* if no lock, and continue if a lock is in place already
node ./scripts/lock-stack.js confirmLock $GIT_SHA "$DEPLOYMENT"
CHECK_STATUS = $?

if [[ $CHECK_STATUS -eq 101 ]]; then
echo "*** Stack is unlocked, reprovisioning"
./deploy-dev-integration-test-stack.sh
./bootstrap-integration-tests.sh
fi

node ./scripts/lock-stack.js confirmLock $GIT_SHA "$DEPLOYMENT" && cd example && npm test