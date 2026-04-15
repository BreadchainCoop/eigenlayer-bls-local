#!/bin/sh

# Check if the environment variables are set
if [ -z "$ALLOCATION_MANAGER_ADDRESS" ]; then
  echo "Error: ALLOCATION_MANAGER_ADDRESS is not set in the environment variables (required for ENVIRONMENT=LOCAL)."
  exit 1
fi
if [ -z "$DELEGATION_MANAGER_ADDRESS" ]; then
  echo "Error: DELEGATION_MANAGER_ADDRESS is not set in the environment variables."
  exit 1
fi
if [ -z "$LST_CONTRACT_ADDRESS" ]; then
  echo "Error: LST_CONTRACT_ADDRESS is not set in the environment variables."
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
if [ "$ENVIRONMENT" = "TESTNET" ] && [ -z "$FUNDED_KEY" ]; then
  echo "Error: FUNDED_KEY is not set in the environment variables. This is required for testnet."
  exit 1
fi

# Use FOUNDRY_PRIVATE_KEY if PRIVATE_KEY is not set
if [ -z "$PRIVATE_KEY" ]; then
  PRIVATE_KEY="$FOUNDRY_PRIVATE_KEY"
fi

# Remove any existing operator keys
rm -rf $HOME/.nodes/operator_keys/*

# Check if the RPC endpoint is live, and wait until it becomes responsive (with retry limit)
MAX_RETRIES=60
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if cast block-number --rpc-url "$RPC_URL" > /dev/null 2>&1; then
        break
    else
        echo "Waiting for RPC at $RPC_URL to become live... (Attempt $((RETRY_COUNT+1))/$MAX_RETRIES)"
        sleep 1
        RETRY_COUNT=$((RETRY_COUNT+1))
    fi
done
if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo "Error: RPC at $RPC_URL not responsive after $MAX_RETRIES attempts."
    exit 1
fi

# Create the number of test accounts specified in the environment variables
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

# Check if the RPC URL is an Anvil node
if cast rpc anvil_nodeInfo --rpc-url $RPC_URL > /dev/null 2>&1; then
    echo "Anvil node detected. Proceeding with local node operations..."
    export IS_ANVIL_RPC=1
else
    echo "Non-Anvil node detected. Running in testnet/mainnet mode..."
    unset IS_ANVIL_RPC
fi


# Create deployer account and fund it
DEPLOYER_INFO=$(cast wallet new --json)
DEPLOYER_KEY=$(echo "$DEPLOYER_INFO" | jq -r '.[0].private_key')
DEPLOYER_ADDRESS=$(echo "$DEPLOYER_INFO" | jq -r '.[0].address')
if [ "$ENVIRONMENT" = "TESTNET" ]; then
    DEPLOYER_KEY=$FUNDED_KEY
    DEPLOYER_ADDRESS=$(cast wallet address --private-key $FUNDED_KEY)
fi
export PRIVATE_KEY=$DEPLOYER_KEY
echo "Using deployer address: $DEPLOYER_ADDRESS"

# Top up deployer balance if running against an Anvil node
if [ -n "$IS_ANVIL_RPC" ]; then
    echo "Topping up deployer balance in Anvil node..."
    cast rpc anvil_setBalance $DEPLOYER_ADDRESS 0x10000000000000000000 --rpc-url $RPC_URL > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "Error: Failed to set balance for deployer account"
        exit 1
    fi
fi

# Deploy AVS contracts
chain_id=$(cast chain-id --rpc-url $RPC_URL)
echo "Deploying service manager (IncredibleSquaringServiceManager) contracts..."
cd bls-middleware/contracts && forge script script/IncredibleSquaringDeployer.s.sol \
       --rpc-url $RPC_URL               \
       --private-key $PRIVATE_KEY       \
       --skip src/libraries/BN256G2.sol \
       --optimize                       \
       --broadcast                      \
       > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "Error: Failed to run middleware deployment script"
    exit 1
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

# Deploy AvsServiceManagerWrapper
echo "Deploying service manager wrapper..."
SERVICE_MANAGER_ADDRESS=$(cat ~/.nodes/avs_deploy.json | jq -r '.addresses.IncredibleSquaringServiceManager')
if [ -z "$SERVICE_MANAGER_ADDRESS" ] || [ "$SERVICE_MANAGER_ADDRESS" = "null" ]; then
    echo "Error: Failed to get IncredibleSquaringServiceManager address from avs_deploy.json"
    exit 1
fi
export SERVICE_MANAGER_ADDRESS

cd /commonware-restaking-contracts
forge script script/DeployAvsServiceManagerWrapper.s.sol:DeployAvsServiceManagerWrapper \
    --rpc-url "$RPC_URL"         \
    --private-key "$PRIVATE_KEY" \
    --broadcast                  \
    > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "Error: Failed to deploy AvsServiceManagerWrapper"; exit 1
fi

AVS_SERVICE_MANAGER_WRAPPER_ADDRESS=$(cat "script/deployments/avs-service-manager-wrapper/$chain_id.json" | jq -r '.addresses.avsServiceManagerWrapper')
if [ -z "$AVS_SERVICE_MANAGER_WRAPPER_ADDRESS" ] || [ "$AVS_SERVICE_MANAGER_WRAPPER_ADDRESS" = "null" ]; then
    echo "Error: Failed to read avsServiceManagerWrapper address from deployment JSON"
    exit 1
fi
export AVS_SERVICE_MANAGER_WRAPPER_ADDRESS

# Verify required directories are present before proceeding
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
if [ ! -d "/commonware-restaking-contracts" ]; then
  echo "Error: /commonware-restaking-contracts directory not found"
  ls -la /
  exit 1
fi

cd /commonware-restaking-contracts
echo "Successfully changed to commonware-restaking-contracts directory"

# Deploy BLS Signature Check
echo "Deploying BLSSigCheckOperatorStateRetriever..."

forge script script/DeployBLSSigCheck.s.sol:DeployBLSSigCheckScript \
    --rpc-url "$RPC_URL"         \
    --private-key "$PRIVATE_KEY" \
    --broadcast                  \
    > /dev/null 2>&1
if [ $? -ne 0 ]; then
  echo "Error: Failed to deploy BLSSigCheckOperatorStateRetriever"; exit 1
fi

# Deploy Counter
echo "Deploying Counter..."

forge script script/DeployCounter.s.sol:DeployCounterScript \
    --rpc-url "$RPC_URL"         \
    --private-key "$PRIVATE_KEY" \
    --broadcast                  \
    > /dev/null 2>&1
if [ $? -ne 0 ]; then
  echo "Error: Failed to deploy Counter"; exit 1
fi

echo "Contract deployment and run complete"

# Merge deployment JSONs
echo "Merging deployment JSONs..."

chain_id=$(cast chain-id --rpc-url $RPC_URL)
if [ -f "script/deployments/bls-sig-check/$chain_id.json" ] && \
   [ -f "script/deployments/counter/$chain_id.json" ] && \
   [ -f "script/deployments/avs-service-manager-wrapper/$chain_id.json" ]; then

    echo "$( cat "script/deployments/bls-sig-check/$chain_id.json" )" > bls_sig_check.json
    echo "$( cat "script/deployments/counter/$chain_id.json" )" > counter.json
    echo "$( cat "script/deployments/avs-service-manager-wrapper/$chain_id.json" )" > wrapper.json

    merged_json=$(jq -s '.[0] * .[1] * .[2] * .[3]' ~/.nodes/avs_deploy.json counter.json bls_sig_check.json wrapper.json)

    echo "$merged_json" > ~/.nodes/avs_deploy.json
    echo "$merged_json" > /bls-middleware/contracts/avs_deploy.json
    rm bls_sig_check.json counter.json wrapper.json
else
    echo "Error: Could not find deployment JSONs for BLS sig checker, Counter, or AvsServiceManagerWrapper"
    exit 1
fi

# Setup middleware
echo "Setting up middleware..."

cd /bls-middleware/contracts
forge script script/UAMPermissions.s.sol \
    --rpc-url $RPC_URL         \
    --private-key $PRIVATE_KEY \
    --broadcast                \
    > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "Error: Failed to run UAMPermissions script"
    exit 1
fi

forge script script/SetupMiddleware.s.sol \
    --rpc-url $RPC_URL         \
    --private-key $PRIVATE_KEY \
    --broadcast                \
    > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "Error: Failed to run SetupMiddleware script"
    exit 1
fi

# On real networks (i.e. not anvil), EigenLayer enforces an ALLOCATION_CONFIGURATION_DELAY
# (75 blocks on Sepolia, ~15 minutes). SetupMiddleware.s.sol calls modifyAllocations which creates
# a *pending* allocation; registerForOperatorSets will revert with BelowMinimumStakeRequirement
# until those blocks have elapsed. Poll each operator until their minimum slashable stake is
# non-zero before proceeding to RegisterOperator.
if [ "$ENVIRONMENT" = "TESTNET" ] && [ -z "$IS_ANVIL_RPC" ]; then
    echo "Waiting for operator allocations to become effective on testnet (ALLOCATION_CONFIGURATION_DELAY)..."
    AVS_ADDRESS=$(cat ~/.nodes/avs_deploy.json | jq -r '.addresses.IncredibleSquaringServiceManager')
    if [ -z "$AVS_ADDRESS" ] || [ "$AVS_ADDRESS" = "null" ]; then
        echo "Error: Failed to get IncredibleSquaringServiceManager address for allocation polling"
        exit 1
    fi
    MAX_WAIT=1800
    for i in $(seq 1 $num_accounts); do
        OP_KEY=$(cat ~/.nodes/operator_keys/testacc${i}.private.ecdsa.key.json | jq -r .privateKey)
        OP_ADDR=$(cast wallet address --private-key $OP_KEY)
        echo "Polling for operator $i ($OP_ADDR) allocation to become effective..."
        ELAPSED=0
        while [ $ELAPSED -lt $MAX_WAIT ]; do
            STAKE=$(cast call $ALLOCATION_MANAGER_ADDRESS \
                "getMinimumSlashableStake((address,uint32),address[],address[],uint32)" \
                "($AVS_ADDRESS,0)" \
                "[$OP_ADDR]" \
                "[$LST_STRATEGY_ADDRESS]" \
                "$(cast block-number --rpc-url $RPC_URL)" \
                --rpc-url $RPC_URL 2>/dev/null || true)
            # getMinimumSlashableStake returns a uint96[][] — non-zero looks like [[N]]
            # Zero allocation returns [[0]] or an error; either way grep for a non-zero hex/decimal
            if echo "$STAKE" | grep -qE '[1-9][0-9a-fA-F]*'; then
                echo "Operator $i allocation is now effective (stake: $STAKE)"
                break
            fi
            echo "Allocation not yet effective for operator $i, waiting... (${ELAPSED}s elapsed)"
            sleep 15
            ELAPSED=$((ELAPSED + 15))
        done
        if [ $ELAPSED -ge $MAX_WAIT ]; then
            echo "Error: Timed out waiting for operator $i allocation to become effective after ${MAX_WAIT}s"
            exit 1
        fi
    done
    echo "All operator allocations are effective. Proceeding with registration."
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
    
    if [ -n "$IS_ANVIL_RPC" ]; then
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
        cast send $ALLOCATION_MANAGER_ADDRESS "setAllocationDelay(address,uint32)" $OPERATOR_ADDRESS 0 \
            --from $DELEGATION_MANAGER_ADDRESS \
            --rpc-url $RPC_URL                 \
            --unlocked                         \
            > /dev/null 2>&1
        if [ $? -ne 0 ]; then
            echo "Error: Failed to override allocation delay"
            exit 1
        fi
    fi

    # Set the operator ID for registration
    export OPERATOR_ID="testacc${i}"

    forge script script/RegisterOperator.s.sol \
        --rpc-url "$RPC_URL"                \
        --private-key $OPERATOR_PRIVATE_KEY \
        --isolate                           \
        --slow                              \
        --skip-simulation                   \
        --broadcast                         \
        > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "Error: Failed to register operator $OPERATOR_ADDRESS"
        exit 1
    fi
    
    WEIGHT=$(cast call $STAKE_REGISTRY "weightOfOperatorForQuorum(uint8,address)(uint96)" 0 $OPERATOR_ADDRESS --rpc-url $RPC_URL)
    if [ $? -ne 0 ]; then
        echo "Error: Failed to get operator weight for quorum for operator $i"
        exit 1
    fi
    echo "Operator $i weight in quorum 0: $WEIGHT"
done

echo "Script execution finished. Container will now exit."
