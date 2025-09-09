#!/bin/sh

if [ -z "$LST_CONTRACT_ADDRESS" ]; then
  echo "Error: LST_CONTRACT_ADDRESS is not set in the environment variables."
  exit 1
fi
if [ -z "$DELEGATION_MANAGER_ADDRESS" ]; then
  echo "Error: DELEGATION_MANAGER_ADDRESS is not set in the environment variables."
  exit 1
fi
if [ -z "$LST_STRATEGY_ADDRESS" ]; then
  echo "Error: LST_STRATEGY_ADDRESS is not set in the environment variables."
  exit 1
fi
if [ -z "$STRATEGY_MANAGER_ADDRESS" ]; then
  echo "Error: STRATEGY_MANAGER_ADDRESS is not set in the environment variables."
  exit 1
fi
if [ -z "$RPC_URL" ]; then
  echo "Error: RPC_URL is not set in the environment variables."
  exit 1
fi

if [ -z "$PRIVATE_KEY" ] && [ -z "$FOUNDRY_PRIVATE_KEY" ]; then
  echo "Error: Neither PRIVATE_KEY nor FOUNDRY_PRIVATE_KEY is set in the environment variables."
  exit 1
fi

# Use FOUNDRY_PRIVATE_KEY if PRIVATE_KEY is not set
if [ -z "$PRIVATE_KEY" ]; then
  PRIVATE_KEY="$FOUNDRY_PRIVATE_KEY"
fi

if [ "$ENVIRONMENT" = "TESTNET" ]; then
  if [ -z "$FUNDED_KEY" ]; then
    echo "Error: FUNDED_KEY is not set in the environment variables. This is required for testnet."
    exit 1
  fi
fi
sleep 10

rm -rf $HOME/.nodes/operator_keys/*

if [ -n "$TEST_ACCOUNTS" ]; then
    num_accounts=$TEST_ACCOUNTS
else
    num_accounts=1
fi

for i in $(seq 1 $num_accounts); do
    echo "Creating test account $i of $num_accounts"
    ./register.sh
    if [ $? -ne 0 ]; then
        echo "Error: Failed to create test account $i"
        exit 1
    fi
done

if [ "$ENVIRONMENT" = "TESTNET" ]; then
    echo "Sleeping for 5 minutes to allow allocation delay to be processed on testnet..."
    sleep 360
fi

# deploy script 
# Create deployer account and fund it
DEPLOYER_INFO=$(cast wallet new --json)
DEPLOYER_KEY=$(echo "$DEPLOYER_INFO" | jq -r '.[0].private_key')
DEPLOYER_ADDRESS=$(echo "$DEPLOYER_INFO" | jq -r '.[0].address')

if [ "$ENVIRONMENT" = "TESTNET" ]; then
    DEPLOYER_KEY=$FUNDED_KEY
else
    cast rpc anvil_setBalance $DEPLOYER_ADDRESS 0x10000000000000000000 --rpc-url $RPC_URL > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "Error: Failed to set balance for deployer account"
        exit 1
    fi
fi

export PRIVATE_KEY=$DEPLOYER_KEY
chain_id=$(cast chain-id --rpc-url $RPC_URL)
cd bls-middleware/contracts && forge script script/IncredibleSquaringDeployer.s.sol --rpc-url $RPC_URL --skip src/libraries/BN256G2.sol --optimize --broadcast --private-key $PRIVATE_KEY > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "Error: Failed to run middleware deployment script"
fi
cp script/deployments/incredible-squaring/$chain_id.json ~/.nodes/avs_deploy.json
cp script/deployments/incredible-squaring/$chain_id.json avs_deploy.json

# Get the latest registry coordinator from deployment JSON
REGISTRY_COORDINATOR_ADDRESS=$(cat ~/.nodes/avs_deploy.json | jq -r '.addresses.registryCoordinator')
if [ -z "$REGISTRY_COORDINATOR_ADDRESS" ] || [ "$REGISTRY_COORDINATOR_ADDRESS" = "null" ]; then
    echo "Error: Failed to get registry coordinator address from deployment JSON"
    exit 1
fi
export REGISTRY_COORDINATOR_ADDRESS

###############################################################################
# Deploy BLS Signature Check
###############################################################################
echo "Deploying BLSSigCheckOperatorStateRetriever..."

# Debug: Check if the directory exists and what's in it
echo "Checking bls-middleware directory structure..."
if [ ! -d "/bls-middleware" ]; then
  echo "Error: /bls-middleware directory not found"
  exit 1
fi

if [ ! -d "/bls-middleware/contracts" ]; then
  echo "Error: /bls-middleware/contracts directory not found"
  ls -la /bls-middleware/
  exit 1
fi

if [ ! -d "/bls-middleware/contracts/lib" ]; then
  echo "Error: /bls-middleware/contracts/lib directory not found"
  ls -la /bls-middleware/contracts/
  exit 1
fi

if [ ! -d "/bls-middleware/contracts/lib/avs-commonware-counter" ]; then
  echo "Error: /bls-middleware/contracts/lib/avs-commonware-counter directory not found"
  ls -la /bls-middleware/contracts/lib/
  exit 1
fi

cd /bls-middleware/contracts/lib/avs-commonware-counter
echo "Successfully changed to avs-commonware-counter directory"

forge script script/DeployBLSSigCheck.s.sol:DeployBLSSigCheckScript \
       --rpc-url "$RPC_URL"         \
       --private-key "$PRIVATE_KEY" \
       --broadcast                  \
       > /dev/null 2>&1
if [ $? -ne 0 ]; then
  echo "Error: Failed to deploy BLSSigCheckOperatorStateRetriever"; exit 1
fi
echo "BLSSigCheckOperatorStateRetriever deployed"

# Deploy Counter
echo "Deploying Counter..."

forge script script/Counter.s.sol:CounterScript \
       --rpc-url "$RPC_URL"         \
       --private-key "$PRIVATE_KEY" \
       --broadcast                  \
       > /dev/null 2>&1
if [ $? -ne 0 ]; then
  echo "Error: Failed to deploy Counter"; exit 1
fi
echo "Counter deployed"
echo "Contract deployment and run complete"

# Merge deployment JSONs
chain_id=$(cast chain-id --rpc-url $RPC_URL)
if [ -f "script/deployments/bls-sig-check/$chain_id.json" ] && [ -f "script/deployments/counter/$chain_id.json" ]; then
    # Read the deployment JSONs
    bls_sig_check_json=$(cat "script/deployments/bls-sig-check/$chain_id.json")
    counter_json=$(cat "script/deployments/counter/$chain_id.json")

    # Create temporary files in the current directory
    echo "$bls_sig_check_json" > bls_sig_check.json
    echo "$counter_json" > counter.json

    # Merge the JSONs with the existing avs_deploy.json
    merged_json=$(jq -s '.[0] * .[1] * .[2]' ~/.nodes/avs_deploy.json counter.json bls_sig_check.json)

    # Save to both locations
    echo "$merged_json" > ~/.nodes/avs_deploy.json
    echo "$merged_json" > ../../avs_deploy.json
    rm bls_sig_check.json counter.json
else
    echo "Error: Could not find deployment JSONs for BLS sig checker or Counter"
    exit 1
fi

# Setup middleware
cd /bls-middleware/contracts

forge script script/UAMPermissions.s.sol --rpc-url $RPC_URL --broadcast --private-key $PRIVATE_KEY > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "Error: Failed to run UAMPermissions script"
fi

forge script script/SetupMiddleware.s.sol --rpc-url $RPC_URL --broadcast --private-key $PRIVATE_KEY > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "Error: Failed to run SetupMiddleware script"
fi

# Get stake registry address once
STAKE_REGISTRY=$(cat ~/.nodes/avs_deploy.json | jq -r '.addresses.stakeRegistry')
if [ -z "$STAKE_REGISTRY" ] || [ "$STAKE_REGISTRY" = "null" ]; then
    echo "Error: Failed to get stake registry address from deployment JSON"
    exit 1
fi

# Register operators
for i in $(seq 1 $num_accounts); do
    echo "Processing operator $i..."
    
    # Copy operator keys
    cp ~/.nodes/operator_keys/testacc${i}.private.ecdsa.key.json private.ecdsa.json
    cp ~/.nodes/operator_keys/testacc${i}.private.bls.key.json private.bls.json
    
    # Get operator private key and address
    export OPERATOR_PRIVATE_KEY=$(cat private.ecdsa.json | jq -r .privateKey)
    if [ -z "$OPERATOR_PRIVATE_KEY" ]; then
        echo "Error: Failed to extract private key from private.ecdsa.json for operator $i"
        exit 1
    fi
    
    OPERATOR_ADDRESS=$(cast wallet address --private-key $OPERATOR_PRIVATE_KEY)
    
    if [ "$ENVIRONMENT" = "local" ]; then
        echo "Getting delegation manager and overriding allocation delay..."
        
        # Set balance and impersonate the delegation manager
        cast rpc anvil_setBalance $DELEGATION_MANAGER_ADDRESS 0x10000000000000000 --rpc-url $RPC_URL > /dev/null 2>&1
        if [ $? -ne 0 ]; then
            echo "Error: Failed to set balance for delegation manager"
            exit 1
        fi
        
        cast rpc anvil_impersonateAccount $DELEGATION_MANAGER_ADDRESS --rpc-url $RPC_URL > /dev/null 2>&1
        if [ $? -ne 0 ]; then
            echo "Error: Failed to impersonate delegation manager"
            exit 1
        fi
        
        # Call the function to override allocation delay
        cast send $ALLOCATION_MANAGER_ADDRESS "setAllocationDelay(address,uint32)" $OPERATOR_ADDRESS 0 --from $DELEGATION_MANAGER_ADDRESS --unlocked --rpc-url $RPC_URL > /dev/null 2>&1
        if [ $? -ne 0 ]; then
            echo "Error: Failed to override allocation delay"
            exit 1
        fi
    fi
    # Set the operator ID for registration
    export OPERATOR_ID="testacc${i}"
    
    forge script script/RegisterOperator.s.sol --rpc-url $RPC_URL --broadcast --private-key $OPERATOR_PRIVATE_KEY --isolate --slow --skip-simulation #> /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "Error: Failed to register operator $OPERATOR_ADDRESS"
    fi
    
    WEIGHT=$(cast call $STAKE_REGISTRY "weightOfOperatorForQuorum(uint8,address)(uint96)" 0 $OPERATOR_ADDRESS --rpc-url $RPC_URL)
    if [ $? -ne 0 ]; then
        echo "Error: Failed to get operator weight for quorum for operator $i"
        exit 1
    fi
    echo "Operator $i weight in quorum 0: $WEIGHT"
done

# Keep container open for debugging
echo "Script execution finished. Keeping container open..."
while true; do sleep 1; done
