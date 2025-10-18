#!/bin/bash

set -e

echo "=== Integration Test: Full EigenLayer BLS Setup ==="
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test configuration
EXPECTED_ACCOUNTS=${TEST_ACCOUNTS:-3}
BLS_KEY_MIN_LENGTH=30

echo "Configuration:"
echo "  Expected accounts: $EXPECTED_ACCOUNTS"
echo "  BLS key minimum length: $BLS_KEY_MIN_LENGTH characters"
echo ""

# Function to print success message
success() {
    echo -e "${GREEN}✓ $1${NC}"
}

# Function to print error message
error() {
    echo -e "${RED}✗ $1${NC}"
    exit 1
}

# Function to print info message
info() {
    echo -e "${YELLOW}→ $1${NC}"
}

# Step 1: Start services
info "Step 1: Starting Docker services..."
docker-compose up -d
if [ $? -ne 0 ]; then
    error "Failed to start Docker services"
fi
success "Docker services started"
echo ""

# Step 2: Wait for Ethereum node
info "Step 2: Waiting for Ethereum node to be ready..."
max_wait=60
waited=0
while ! docker-compose exec -T ethereum cast client --rpc-url http://localhost:8545 > /dev/null 2>&1; do
    if [ $waited -ge $max_wait ]; then
        error "Ethereum node failed to start within ${max_wait}s"
    fi
    sleep 2
    waited=$((waited + 2))
    echo "  Waiting... (${waited}s/${max_wait}s)"
done
success "Ethereum node is ready"
echo ""

# Step 3: Wait for EigenLayer setup to complete
info "Step 3: Waiting for EigenLayer setup to complete..."
max_wait=300
waited=0
while docker-compose ps | grep eigenlayer | grep -q "Up"; do
    if [ $waited -ge $max_wait ]; then
        error "EigenLayer setup did not complete within ${max_wait}s"
    fi
    sleep 5
    waited=$((waited + 5))
    echo "  Setup running... (${waited}s/${max_wait}s)"
done
success "EigenLayer setup completed"
echo ""

# Step 4: Validate BLS keys were created
info "Step 4: Validating BLS keys..."
if [ ! -d "./.nodes/operator_keys" ]; then
    error "Operator keys directory not found at ./.nodes/operator_keys"
fi

# Count BLS key files
bls_key_count=$(ls -1 ./.nodes/operator_keys/*.private.bls.key.json 2>/dev/null | wc -l | tr -d ' ')
if [ "$bls_key_count" -ne "$EXPECTED_ACCOUNTS" ]; then
    error "Expected $EXPECTED_ACCOUNTS BLS keys, found $bls_key_count"
fi
success "Found $bls_key_count BLS key files"

# Validate each BLS key
for keyfile in ./.nodes/operator_keys/*.private.bls.key.json; do
    if [ ! -f "$keyfile" ]; then
        continue
    fi

    account_name=$(basename "$keyfile" .private.bls.key.json)
    info "  Validating $account_name..."

    # Extract private key
    private_key=$(cat "$keyfile" | jq -r '.privateKey')
    if [ -z "$private_key" ] || [ "$private_key" = "null" ]; then
        error "Failed to extract privateKey from $keyfile"
    fi

    # Check key length
    key_length=${#private_key}
    if [ $key_length -le $BLS_KEY_MIN_LENGTH ]; then
        error "$account_name BLS key is too short: $key_length characters (expected > $BLS_KEY_MIN_LENGTH)"
    fi

    success "  $account_name: valid ($key_length characters)"
done
echo ""

# Step 5: Validate ECDSA keys were created
info "Step 5: Validating ECDSA keys..."
ecdsa_key_count=$(ls -1 ./.nodes/operator_keys/*.private.ecdsa.key.json 2>/dev/null | wc -l | tr -d ' ')
if [ "$ecdsa_key_count" -ne "$EXPECTED_ACCOUNTS" ]; then
    error "Expected $EXPECTED_ACCOUNTS ECDSA keys, found $ecdsa_key_count"
fi
success "Found $ecdsa_key_count ECDSA key files"

# Validate each ECDSA key
for keyfile in ./.nodes/operator_keys/*.private.ecdsa.key.json; do
    if [ ! -f "$keyfile" ]; then
        continue
    fi

    account_name=$(basename "$keyfile" .private.ecdsa.key.json)

    # Extract keys
    private_key=$(cat "$keyfile" | jq -r '.privateKey')
    public_key=$(cat "$keyfile" | jq -r '.publicKey')

    if [ -z "$private_key" ] || [ "$private_key" = "null" ]; then
        error "Failed to extract privateKey from $keyfile"
    fi

    if [ -z "$public_key" ] || [ "$public_key" = "null" ]; then
        error "Failed to extract publicKey from $keyfile"
    fi

    success "  $account_name: valid"
done
echo ""

# Step 6: Validate deployment files
info "Step 6: Validating deployment files..."
if [ ! -f "./.nodes/avs_deploy.json" ]; then
    error "AVS deployment file not found at ./.nodes/avs_deploy.json"
fi
success "AVS deployment file exists"

# Check for required addresses in deployment
registry_coordinator=$(cat ./.nodes/avs_deploy.json | jq -r '.addresses.registryCoordinator')
if [ -z "$registry_coordinator" ] || [ "$registry_coordinator" = "null" ]; then
    error "Registry coordinator address not found in deployment file"
fi
success "  Registry coordinator: $registry_coordinator"

stake_registry=$(cat ./.nodes/avs_deploy.json | jq -r '.addresses.stakeRegistry')
if [ -z "$stake_registry" ] || [ "$stake_registry" = "null" ]; then
    error "Stake registry address not found in deployment file"
fi
success "  Stake registry: $stake_registry"
echo ""

# Step 7: Verify BLS identifiers
info "Step 7: Validating BLS identifiers..."
identifier_count=$(ls -1 ./.nodes/operator_keys/*.bls.identifier 2>/dev/null | wc -l | tr -d ' ')
if [ "$identifier_count" -ne "$EXPECTED_ACCOUNTS" ]; then
    error "Expected $EXPECTED_ACCOUNTS BLS identifiers, found $identifier_count"
fi
success "Found $identifier_count BLS identifier files"
echo ""

# Final summary
echo "================================"
echo -e "${GREEN}Integration Test: PASSED${NC}"
echo "================================"
echo "Summary:"
echo "  ✓ Docker services started successfully"
echo "  ✓ Ethereum node ready"
echo "  ✓ EigenLayer setup completed"
echo "  ✓ $bls_key_count BLS keys created and validated (all > $BLS_KEY_MIN_LENGTH chars)"
echo "  ✓ $ecdsa_key_count ECDSA keys created and validated"
echo "  ✓ Deployment files created"
echo "  ✓ BLS identifiers created"
echo ""
echo "All tests passed successfully!"
