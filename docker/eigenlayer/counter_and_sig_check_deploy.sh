#!/usr/bin/env bash
set -Eeuo pipefail

###############################################################################
# Prerequisites (export these before running or put them in a `.env` file)
#   RPC_URL                      – JSON-RPC endpoint of the target chain
#   PRIVATE_KEY / FOUNDRY_PRIVATE_KEY – deployer key
#   REGISTRY_COORDINATOR_ADDRESS – address used by CounterScript
###############################################################################

if [ -z "$RPC_URL" ]; then
  echo "Error: RPC_URL is not set in the environment variables."
  exit 1
fi

if [ -z "$PRIVATE_KEY" ] && [ -z "$FOUNDRY_PRIVATE_KEY" ]; then
  echo "Error: Neither PRIVATE_KEY nor FOUNDRY_PRIVATE_KEY is set in the environment variables."
  exit 1
fi

if [ -z "$REGISTRY_COORDINATOR_ADDRESS" ]; then
  echo "Error: REGISTRY_COORDINATOR_ADDRESS is not set in the environment variables."
  exit 1
fi

# Use FOUNDRY_PRIVATE_KEY if PRIVATE_KEY is not set
if [ -z "$PRIVATE_KEY" ]; then
  PRIVATE_KEY="$FOUNDRY_PRIVATE_KEY"
fi

###############################################################################
# 1. Build + deploy BLSSigCheckOperatorStateRetriever
###############################################################################
cd bls-middleware/contracts/lib/avs-commonware-counter

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

###############################################################################
# 3. Merge deployment JSONs
###############################################################################
chain_id=$(cast chain-id --rpc-url $RPC_URL)
if [ -f "script/deployments/bls-sig-check/$chain_id.json" ] && [ -f "script/deployments/counter/$chain_id.json" ]; then
    # Read the deployment JSONs
    bls_sig_check_json=$(cat "script/deployments/bls-sig-check/$chain_id.json")
    counter_json=$(cat "script/deployments/counter/$chain_id.json")
    
    # Create temporary files in the current directory
    echo "$bls_sig_check_json" > bls_sig_check.json
    echo "$counter_json" > counter.json
    
    # Merge the JSONs with the existing avs_deploy.json
    merged_json=$(jq -s '.[0] * .[1] * .[2]' ~/.nodes/avs_deploy.json bls_sig_check.json counter.json)
    
    # Save to both locations
    echo "$merged_json" > ~/.nodes/avs_deploy.json
    echo "$merged_json" > ../../avs_deploy.json
    rm bls_sig_check.json counter.json
else
    echo "Error: Could not find deployment JSONs for BLS sig checker or Counter"
    exit 1
fi

echo "-----------------------------------------------------------------"
echo "Counter deploy and run complete"
