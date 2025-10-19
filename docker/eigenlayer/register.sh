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

echo "[register] Creating new ECDSA account..."
ACCOUNT_INFO=$(cast wallet new --json)
PRIVATE_KEY=$(echo "$ACCOUNT_INFO" | jq -r '.[0].private_key')
ADDRESS=$(echo "$ACCOUNT_INFO" | jq -r '.[0].address')
echo "[register] New account: $ADDRESS"
if [ "$ENVIRONMENT" = "TESTNET" ]; then
        echo "[register] Funding $ADDRESS on TESTNET..."
        cast s $ADDRESS --value 500000000000000000 --private-key "$FUNDED_KEY" -r "$RPC_URL" > /dev/null 2>&1
        if [ $? -ne 0 ]; then   
            echo "Error: Failed to give operator $index balance"
            exit 1
        fi
    else
        echo "[register] Setting local balance for $ADDRESS..."
        cast rpc anvil_setBalance $ADDRESS 0x10000000000000000000 --rpc-url $RPC_URL > /dev/null 2>&1
        if [ $? -ne 0 ]; then
            echo "Error: Failed to set balance for $ADDRESS"
            exit 1
        fi
    fi


MINT_FUNCTION="submit(address)"
echo "[register] Minting LST via $LST_CONTRACT_ADDRESS..."
mint_output=$(cast send $LST_CONTRACT_ADDRESS "$MINT_FUNCTION" "0x0000000000000000000000000000000000000000" --private-key $PRIVATE_KEY --value 10000000000000000 --rpc-url $RPC_URL 2>&1)
mint_result=$?
if [ $mint_result -ne 0 ]; then
    echo "Error: Failed to mint LST for $ADDRESS"
    echo "Output: $mint_output"
    exit 1
fi
echo "[register] Approving LST for strategy manager $STRATEGY_MANAGER_ADDRESS..."
cast send $LST_CONTRACT_ADDRESS "approve(address,uint256)" $STRATEGY_MANAGER_ADDRESS 1000000000000000000000000 --private-key $PRIVATE_KEY --rpc-url $RPC_URL > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "Error: Failed to approve LST for $STRATEGY_MANAGER_ADDRESS"
    exit 1
fi
echo "[register] Depositing into strategy $LST_STRATEGY_ADDRESS via $STRATEGY_MANAGER_ADDRESS..."
cast send $STRATEGY_MANAGER_ADDRESS "depositIntoStrategy(address,address,uint256)" $LST_STRATEGY_ADDRESS $LST_CONTRACT_ADDRESS 10000000000000000 --private-key $PRIVATE_KEY --rpc-url $RPC_URL  > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "Error: Failed to deposit into strategy for $LST_STRATEGY_ADDRESS"
    exit 1
fi
echo "[register] Registering as operator at $DELEGATION_MANAGER_ADDRESS..."
cast send $DELEGATION_MANAGER_ADDRESS "registerAsOperator(address,uint32,string)" "$ADDRESS"  "1" "foo.bar" --private-key $PRIVATE_KEY --rpc-url $RPC_URL > /dev/null 2>&1
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
password="Testacc1Testacc1"

echo "[register] Importing ECDSA key for $new_account..."
echo $password | eigenlayer keys import --insecure --key-type ecdsa $new_account $PRIVATE_KEY

cp $HOME/.eigenlayer/operator_keys/${new_account}.ecdsa.key.json $HOME/.nodes/operator_keys/${new_account}.ecdsa.key.json

echo "[register] Creating BLS key for $new_account using crypto-libs..."
# Generate BLS key using our custom tool
bls_keystore_tmp_path="${HOME}/.nodes/operator_keys/${new_account}.bls.key.json"
bls_output=$(blskeygen "$bls_keystore_tmp_path" "$password")
if [ $? -ne 0 ]; then
    echo "Error: Failed to generate BLS key for $new_account"
    echo "$bls_output"
    exit 1
fi

# Parse the JSON output
private_bls_key=$(echo "$bls_output" | jq -r '.privateKey')

if [ -z "$private_bls_key" ] || [ "$private_bls_key" = "null" ]; then
    echo "Error: Failed to extract BLS private key from blskeygen output"
    exit 1
fi

# Validate BLS key length (must be > 30 characters for hex, typically 64)
key_length=${#private_bls_key}
if [ $key_length -le 30 ]; then
    echo "Error: BLS private key is too short (${key_length} characters). Expected > 30 characters."
    echo "Invalid key: $private_bls_key"
    exit 1
fi
echo "[register] BLS key validation passed (${key_length} characters)"

result=$(grpcurl -plaintext -d '{"privateKey": "'"$private_bls_key"'", "password": "'"$password"'"}' signer:50051  keymanager.v1.KeyManager/ImportKey | jq -r '.publicKey' | tr -d '\n')
if [ $? -ne 0 ]; then
    echo "Error: Failed to import bls key for $new_account"
    echo "$result"
    exit 1
fi

echo -n $result > $HOME/.nodes/operator_keys/${new_account}.bls.identifier
echo -n "{\"privateKey\":\"$private_bls_key\"}" > $HOME/.nodes/operator_keys/${new_account}.private.bls.key.json
echo -n "{\"privateKey\":\"$PRIVATE_KEY\",\"publicKey\":\"$ADDRESS\"}" > $HOME/.nodes/operator_keys/${new_account}.private.ecdsa.key.json
# BLS keystore already generated at $HOME/.nodes/operator_keys/${new_account}.bls.key.json
