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
        cast s $ADDRESS --value 500000000000000000 --private-key "$FUNDED_KEY" -r "$RPC_URL" > /dev/null 2>&1
        if [ $? -ne 0 ]; then
            echo "Error: Failed to give operator $index balance"
            exit 1
        fi
    else
        cast rpc anvil_setBalance $ADDRESS 0x10000000000000000000 --rpc-url $RPC_URL > /dev/null 2>&1
        if [ $? -ne 0 ]; then
            echo "Error: Failed to set balance for $ADDRESS"
            exit 1
        fi
    fi


MINT_FUNCTION="submit(address)"
cast send $LST_CONTRACT_ADDRESS "$MINT_FUNCTION" "0x0000000000000000000000000000000000000000" --private-key $PRIVATE_KEY --value 10000000000000000 --rpc-url $RPC_URL > /dev/null 2>&1
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
echo "[register] ECDSA key imported successfully"

echo "[register] Creating BLS key for $new_account using crypto-libs..."
# Generate BLS key using our custom tool
bls_keystore_tmp_path="${HOME}/.nodes/operator_keys/${new_account}.bls.key.json"
echo "[register] Generating BN254 BLS key pair..."
bls_output=$(blskeygen "$bls_keystore_tmp_path" "$password")
if [ $? -ne 0 ]; then
    echo "[register] ERROR: Failed to generate BLS key for $new_account"
    echo "[register] blskeygen output: $bls_output"
    exit 1
fi
echo "[register] BLS key pair generated successfully"

# Parse the JSON output
echo "[register] Parsing BLS key from output..."
private_bls_key=$(echo "$bls_output" | jq -r '.privateKey')

if [ -z "$private_bls_key" ] || [ "$private_bls_key" = "null" ]; then
    echo "[register] ERROR: Failed to extract BLS private key from blskeygen output"
    echo "[register] Output was: $bls_output"
    exit 1
fi
echo "[register] BLS private key extracted successfully"

# Validate BLS key (should be a decimal uint256, typically 77-78 digits)
key_length=${#private_bls_key}
echo "[register] Validating BLS key..."
echo "[register] Key length: ${key_length} characters (decimal uint256)"
echo "[register] Key value: ${private_bls_key}"
# BN254 field order is ~254 bits, which is ~77 decimal digits
if [ $key_length -lt 70 ]; then
    echo "[register] ERROR: BLS private key is too short (${key_length} characters). Expected ~77 digits for uint256."
    exit 1
fi
echo "[register] ✓ BLS key validation passed (${key_length} digit uint256)"

echo "[register] Importing BLS key to signer service..."
result=$(grpcurl -plaintext -d '{"privateKey": "'"$private_bls_key"'", "password": "'"$password"'"}' signer:50051  keymanager.v1.KeyManager/ImportKey | jq -r '.publicKey' | tr -d '\n')
if [ $? -ne 0 ]; then
    echo "[register] ERROR: Failed to import BLS key to signer for $new_account"
    echo "[register] Signer response: $result"
    exit 1
fi
echo "[register] BLS key imported to signer successfully"
echo "[register] BLS public key: $result"

echo "[register] Writing key files..."
echo -n "$result" > $HOME/.nodes/operator_keys/${new_account}.bls.identifier
printf '{"privateKey":"%s"}' "$private_bls_key" > $HOME/.nodes/operator_keys/${new_account}.private.bls.key.json
printf '{"privateKey":"%s","publicKey":"%s"}' "$PRIVATE_KEY" "$ADDRESS" > $HOME/.nodes/operator_keys/${new_account}.private.ecdsa.key.json
# BLS keystore already generated at $HOME/.nodes/operator_keys/${new_account}.bls.key.json
echo "[register] ✓ Key files written successfully for $new_account"
