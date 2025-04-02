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
    num_accounts=3
fi

for i in $(seq 1 $num_accounts); do
    echo "Creating test account $i of $num_accounts"
    ./register.sh
    if [ $? -ne 0 ]; then
        echo "Error: Failed to create test account $i"
        exit 1
    fi
done
# deploy script 
# Create deployer account and fund it
DEPLOYER_INFO=$(cast wallet new --json)
DEPLOYER_KEY=$(echo "$DEPLOYER_INFO" | jq -r '.[0].private_key')
DEPLOYER_ADDRESS=$(echo "$DEPLOYER_INFO" | jq -r '.[0].address')

if [ "$ENVIRONMENT" = "TESTNET" ]; then
    cast s $DEPLOYER_ADDRESS --value 10000000000000000 --private-key "$FUNDED_KEY" -r "$RPC_URL" > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "Error: Failed to fund deployer account"
        exit 1
    fi
else
    cast rpc anvil_setBalance $DEPLOYER_ADDRESS 0x10000000000000000000 --rpc-url $RPC_URL > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "Error: Failed to set balance for deployer account"
        exit 1
    fi
fi

export PRIVATE_KEY=$DEPLOYER_KEY

cd bls-middleware/contracts && forge script script/IncredibleSquaringDeployer.s.sol --rpc-url $RPC_URL --broadcast
if [ $? -ne 0 ]; then
    echo "Error: Failed to run middleware deployment script"
fi
cp script/deployments/incredible-squaring/1.json ~/.nodes/avs_deploy.json
# make sure to write deployment json out
#logic for registering operators to avs  
# Keep container open for debugging
echo "Script execution finished. Keeping container open..."
while true; do sleep 1; done
