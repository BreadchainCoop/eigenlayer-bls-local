#!/bin/sh
if [ -z "$LST_CONTRACT_ADDRESS" ]; then
  echo "Error: LST_CONTRACT_ADDRESS is not set in the environment variables."
  exit 1
fi
if [ -z "$LST_STRATEGY_ADDRESS" ]; then
  echo "Error: LST_CONTRACT_ADDRESS is not set in the environment variables."
  exit 1
fi
if [ -z "$DELEGATION_MANAGER_ADDRESS" ]; then
  echo "Error: DELEGATION_MANAGER_ADDRESS is not set in the environment variables."
  exit 1
fi
if [ -z "$RPC_URL" ]; then
  echo "Error: RPC_URL is not set in the environment variables."
  exit 1
fi

ACCOUNT_INFO=$(cast wallet new --json)
PRIVATE_KEY=$(echo "$ACCOUNT_INFO" | jq -r '.[0].private_key')
ADDRESS=$(echo "$ACCOUNT_INFO" | jq -r '.[0].address')
if [ "$ENVIRONMENT" = "TESTNET" ]; then
        cast s $ADDRESS --value 50000000000000000 --private-key "$FUNDED_KEY" -r "$RPC_URL" > /dev/null 2>&1
        if [ $? -ne 0 ]; then   
            echo "Error: Failed to give operator $index balance"
            exit 1
        fi
    else
        cast rpc anvil_setBalance $ADDRESS 0x10000000000000000000 --rpc-url $RPC_URL  
        if [ $? -ne 0 ]; then
            echo "Error: Failed to set balance for $ADDRESS"
            exit 1
        fi
    fi


MINT_FUNCTION="submit(address _referral)"
cast send $LST_CONTRACT_ADDRESS "$MINT_FUNCTION" $ADDRESS "0x0000000000000000000000000000000000000000" --private-key $PRIVATE_KEY --value 10000000000000000 --rpc-url $RPC_URL > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "Error: Failed to mint LST for $ADDRESS"
    exit 1
fi
cast send $LST_CONTRACT_ADDRESS "approve(address,uint256)" $STRATEGY_MANAGER_ADDRESS 1000000000000000000000000 --private-key $PRIVATE_KEY --rpc-url $RPC_URL > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "Error: Failed to approve LST for $STRATEGY_MANAGER_ADDRESS"
    exit 1
fi
cast send $STRATEGY_MANAGER_ADDRESS "depositIntoStrategy(address,address,uint256)" $LST_STRATEGY_ADDRESS $LST_CONTRACT_ADDRESS 10000000000000000 --private-key $PRIVATE_KEY --rpc-url $RPC_URL  > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "Error: Failed to deposit into strategy for $LST_STRATEGY_ADDRESS"
    exit 1
fi
cast send $DELEGATION_MANAGER_ADDRESS "registerAsOperator(address,uint32,string)" `cast az` 0 "foo.bar" --private-key $PRIVATE_KEY --rpc-url $RPC_URL > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "Error: Failed to register as operator for $DELEGATION_MANAGER_ADDRESS"
    exit 1
fi

# Find the highest numbered test account
highest_num=$(ls $HOME/.nodes/operator_keys/testacc*.ecdsa.key.json 2>/dev/null | grep -oE 'testacc[0-9]+' | sed 's/testacc//' | sort -n | tail -1)

if [ -z "$highest_num" ]; then
    new_num=1
else
    new_num=$((highest_num + 1))
fi

new_account="testacc${new_num}"
ecdsa_keystore_path="${HOME}/.nodes/operator_keys/${new_account}.ecdsa.key.json"
bls_keystore_path="${HOME}/.nodes/operator_keys/${new_account}.bls.key.json"
password="Testacc1Testacc1"

echo $password | eigenlayer keys import --insecure --key-type ecdsa $new_account $PRIVATE_KEY  >  /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "Error: Failed to import ecdsa key for $new_account"
    exit 1
fi
cp $HOME/.eigenlayer/operator_keys/${new_account}.ecdsa.key.json $HOME/.nodes/operator_keys/${new_account}.ecdsa.key.json
echo $password |  eigenlayer keys create --key-type bls --insecure $new_account >  /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "Error: Failed to create bls key for $new_account"
    exit 1
fi
private_bls_key=$(./get_bls_key.sh $password $new_account)
if [ $? -ne 0 ]; then
    echo "Error: Failed to get bls key for $new_account"
    exit 1
fi
result=$(grpcurl -plaintext -d '{"privateKey": "'"$private_bls_key"'", "password": "'"$password"'"}' signer:50051  keymanager.v1.KeyManager/ImportKey | jq -r '.publicKey' | tr -d '\n')
if [ $? -ne 0 ]; then
    echo "Error: Failed to import bls key for $new_account"
    echo $result
    exit 1
fi
echo -n $result > $HOME/.nodes/operator_keys/${new_account}.bls.identifier
cp $HOME/.eigenlayer/operator_keys/${new_account}.bls.key.json $HOME/.nodes/operator_keys/${new_account}.bls.key.json

# Create the config file for the new account
config_file="${HOME}/.nodes/configs/${new_account}.config.yaml"

# Set the node public IP based on the account number
node_public_ip="http://node${new_num}"

# Create the config file with the correct values
cat << EOF > "$config_file"
production: false
opacity_node_selector_address: 0x8a2c56230E89C4636e5b7878541e66aBA2091FcD
registry_coordinator_address: "0x3e43AA225b5cB026C5E8a53f62572b10D526a50B"
opacity_avs_address: "0xbfc5d26C6eEb46475eB3960F5373edC5341eE535"
avs_directory_address: "0x055733000064333CaDDbC92763c58BF0192fFeBf"
eigenlayer_delegation_manager: "0xA44151489861Fe9e3055d95adC98FbD462B948e7"
chain_id: 17000
eth_rpc_url: '${RPC_URL}'
operator_address: '${ADDRESS}'
node_public_ip: ${node_public_ip}
operator_bls_keystore_path: /opacity-avs-node/config/opacity.bls.key.json
operator_id: "0x00"
EOF

