# -----------------------------------------------------------------------------
# Dockerfile for Ethereum Anvil Node
# -----------------------------------------------------------------------------

# Use the stable version of the official Foundry image
FROM ghcr.io/foundry-rs/foundry:stable

# Set the working directory inside the container
WORKDIR /ethereum

# Start Anvil with custom options:
# --fork-url: The upstream Ethereum node to fork from (set via environment variable)
# --host: Listen on all interfaces (for Docker networking)
# --port: Expose Anvil on port 8545
# --code-size-limit: Increase contract code size limit (useful for large contracts)
ENTRYPOINT anvil --fork-url $FORK_URL --host 0.0.0.0 --port 8545 --code-size-limit 65536