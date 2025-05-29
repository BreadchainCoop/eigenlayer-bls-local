#!/usr/bin/env bash
set -Eeuo pipefail

###############################################################################
# Prerequisites (export these before running or put them in a `.env` file)
#   RPC_URL                      – JSON-RPC endpoint of the target chain
#   PRIVATE_KEY / FOUNDRY_PRIVATE_KEY – deployer key
#   REGISTRY_COORDINATOR_ADDRESS – address used by CounterScript
###############################################################################
: "${RPC_URL:?RPC_URL is not set}"
: "${PRIVATE_KEY:=${FOUNDRY_PRIVATE_KEY:-}}"
: "${PRIVATE_KEY:?PRIVATE_KEY (or FOUNDRY_PRIVATE_KEY) is not set}"
: "${REGISTRY_COORDINATOR_ADDRESS:?REGISTRY_COORDINATOR_ADDRESS is not set}"

###############################################################################
# 1. Build + deploy BLSSigCheckOperatorStateRetriever
###############################################################################
cd bls-middleware/contracts/lib/avs-commonware-counter \
  && forge build > /dev/null 2>&1
if [ $? -ne 0 ]; then
  echo "Error: forge build failed"; exit 1
fi

forge script script/DeployBLSSigCheck.s.sol:DeployBLSSigCheckScript \
       --rpc-url "$RPC_URL"         \
       --private-key "$PRIVATE_KEY" \
       --broadcast                  \
       > /dev/null 2>&1
if [ $? -ne 0 ]; then
  echo "Error: Failed to deploy BLSSigCheckOperatorStateRetriever"; exit 1
fi
echo "BLSSigCheckOperatorStateRetriever deployed"

###############################################################################
# 2. Deploy Counter (needs REGISTRY_COORDINATOR_ADDRESS env var)
###############################################################################
forge script script/Counter.s.sol:CounterScript \
       --rpc-url "$RPC_URL"         \
       --private-key "$PRIVATE_KEY" \
       --broadcast                  \
       > /dev/null 2>&1
if [ $? -ne 0 ]; then
  echo "Error: Failed to deploy Counter"; exit 1
fi
echo "Counter deployed"

echo "-----------------------------------------------------------------"
echo "Counter deploy and run complete"
