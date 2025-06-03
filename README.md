# BLS Local 

This repository contains the configuration and setup for running the BLS AVS (Actively Validated Service) infrastructure using Docker Compose.
Relies on [BLS-middleware](https://github.com/BreadchainCoop/bls-middleware)
## Prerequisites

- Docker
- Docker Compose

## Setup

2. Create a `.env` file in the root directory and add the following environment variables:
   ```
   cp example.env .env
   ```
   Make sure you have filled in all the required variables. The environment variables are organized into several sections:

   ### Mainnet/Testnet Configuration
   Choose one set of addresses based on your target network:
   ```
   DELEGATION_MANAGER_ADDRESS=  # Address of the delegation manager contract
   STRATEGY_MANAGER_ADDRESS=    # Address of the strategy manager contract
   LST_CONTRACT_ADDRESS=        # Address of the LST contract
   LST_STRATEGY_ADDRESS=        # Address of the LST strategy contract
   BLS_SIGNATURE_CHECKER_ADDRESS= # Address of the BLS signature checker
   OPERATOR_STATE_RETRIEVER_ADDRESS= # Address of the operator state retriever
   ALLOCATION_MANAGER_ADDRESS=  # Address of the allocation manager
   ```

   ### Network Configuration
   ```
   FORK_URL=                    # URL of the RPC to fork from (Ethereum/Holesky)
   RPC_URL=http://ethereum:8545 # Local RPC endpoint, change to a live endpoint when running on testnet
   ENVIRONMENT=LOCAL            # Environment mode (LOCAL, MAINNET or TESTNET)
   ```

   ### Operator Configuration
   ```
   PRIVATE_KEY=                 # Private key for signing operations
   FUNDED_KEY=                  # Private key used for funding test accounts (required for TESTNET)
   TEST_ACCOUNTS=3              # Number of test accounts to create
   ```

   ### Service Configuration
   ```
   CERBERUS_GRPC_PORT=50051     # Port for Cerberus gRPC service
   CERBERUS_METRICS_PORT=9081   # Port for Cerberus metrics
   SIGNER_ENDPOINT=http://signer:50051 # Endpoint for the signer service
   ```

   ### Optional Debug Configuration
   ```
   RUST_BACKTRACE=full          # Enable full backtrace for Rust errors
   RUST_LOG=debug              # Set Rust logging level
   ```

3. Build and start the services:
   ```
   # First, build the services with no cache
   docker-compose build --no-cache
   
   # Then start the services
   docker-compose up
   ```
Note that the nodes and node selector only start up after the eigenlayer setup container has exited  

## Running in TESTNET Mode

To run the service in TESTNET mode (Holesky), follow these steps:

1. Update your `.env` file with the following changes:

   a. Change the environment to TESTNET:
   ```
   ENVIRONMENT=TESTNET
   ```

   b. Set up your RPC URLs:
   ```
   # It's reccomended to get a paid RPC URL for non-flakey behavior
   FORK_URL=https://holesky.rpc # Not a real RPC
   RPC_URL=https://holesky.rpc # Not a real RPC
   ```

   c. Uncomment and use the Holesky configuration addresses:
   ```
   DELEGATION_MANAGER_ADDRESS=0xA44151489861Fe9e3055d95adC98FbD462B948e7
   STRATEGY_MANAGER_ADDRESS=0xdfB5f6CE42aAA7830E94ECFCcAd411beF4d4D5b6
   LST_CONTRACT_ADDRESS=0x3F1c547b21f65e10480dE3ad8E19fAAC46C95034
   LST_STRATEGY_ADDRESS=0x7D704507b76571a51d9caE8AdDAbBFd0ba0e63d3
   BLS_SIGNATURE_CHECKER_ADDRESS=0xca249215e082e17c12bb3c4881839a3f883e5c6b
   OPERATOR_STATE_RETRIEVER_ADDRESS=0xB4baAfee917fb4449f5ec64804217bccE9f46C67
   ALLOCATION_MANAGER_ADDRESS=0x78469728304326CBc65f8f95FA756B0B73164462
   ```

   d. Set up your testnet keys:
   ```
   # Generate a new private key or use an existing one with testnet ETH
   PRIVATE_KEY=your_private_key_here
   FUNDED_KEY=your_funded_private_key_here
   ```

2. Get Testnet ETH:
   - Visit the [Holesky Faucet](https://holesky-faucet.pk910.de/) to get testnet ETH
   - Send some ETH to both your `PRIVATE_KEY` and `FUNDED_KEY` addresses
   - You can check your balance using [Holesky Etherscan](https://holesky.etherscan.io/)

3. Build and start the services:
   ```
   # First, build the services with no cache
   docker-compose build --no-cache
   
   # Then start the services
   docker-compose up
   ```

4. Monitor the deployment:
   - The setup process will take longer in TESTNET mode due to real network conditions
   - Check the logs for any errors or issues
   - You can monitor transactions on [Holesky Etherscan](https://holesky.etherscan.io/)

Note: Make sure you have enough testnet ETH in both your `PRIVATE_KEY` and `FUNDED_KEY` accounts before starting the deployment. The deployment process requires multiple transactions and will fail if there's insufficient balance.

## Services

The Docker Compose setup includes the following services:

1. `ethereum`: An Ethereum node for local development and testing.
2. `eigenlayer`: Sets up EigenLayer and registers operators.

## Configuration

- The `docker/eigenlayer/register.sh` script creates test accounts and registers them as operators.
- Node configurations are stored in `.nodes/configs/`.
- Operator keys are stored in `.nodes/operator_keys/`.

### BLS AVS Configuration File (config.json)

The BLS AVS configuration is defined in `docker/eigenlayer/config.json` and controls the key parameters for the AVS:

```json
{
    "quorum": {
        "minimumStake": "1",
        "maxOperatorCount": 32,
        "kickBIPsOfOperatorStake": 10000,
        "kickBIPsOfTotalStake": 100
    },
    "metadata": {
        "uri": "metadataURI"
    },
    "operators": {
        "testacc1": {
            "socketAddress": "127.0.0.1:3000"
        },
        "testacc2": {
            "socketAddress": "127.0.0.1:3000"
        },
        "testacc3": {
            "socketAddress": "127.0.0.1:3000"
        }
    }
}
```

#### Configuration Options

##### Quorum Settings
- `minimumStake`: The minimum amount of stake (in wei) required for an operator to participate in the AVS. This is the minimum amount of tokens an operator must stake to be considered active.
- `maxOperatorCount`: The maximum number of operators allowed in the AVS. Default is 32. This limits the total number of operators that can participate in the service.
- `kickBIPsOfOperatorStake`: The percentage of an operator's stake that can be slashed (in basis points). 10000 basis points = 100%. This determines how much of an operator's stake can be slashed if they misbehave.
- `kickBIPsOfTotalStake`: The percentage of total stake that can be slashed (in basis points). 100 basis points = 1%. This sets the maximum amount of total stake that can be slashed across all operators.

##### Metadata
- `uri`: The URI pointing to the AVS metadata. This should contain information about the AVS service, its purpose, and any relevant documentation.

##### Operators
- Each operator entry contains:
  - `socketAddress`: The network address where the operator's node can be reached. Format should be `IP:PORT`.
  - Multiple operators can be configured, each with their own unique identifier (e.g., "testacc1", "testacc2", etc.)

#### Recommended Settings

For a production environment:
- `minimumStake`: Set based on your security requirements. Higher values ensure more committed operators.
- `maxOperatorCount`: Adjust based on your network's capacity and decentralization goals.
- `kickBIPsOfOperatorStake`: Typically set to 10000 (100%) to allow full slashing of misbehaving operators.
- `kickBIPsOfTotalStake`: Set based on your risk tolerance. Lower values (e.g., 100 = 1%) provide more protection against mass slashing events.

For a test environment:
- You can use lower values for `minimumStake` to make testing easier
- Keep `maxOperatorCount` small (e.g., 3-5) for testing purposes
- Use test operator addresses with appropriate test network configurations

## Accessing the Services

- Ethereum RPC: http://localhost:8545
- Node Selector: http://localhost:8080

## Notes

- The `.gitignore` file is set up to exclude sensitive information like operator keys and test account configs.
- Make sure to keep your `.env` file secure and do not commit it to version control.

For more detailed information about each component, refer to the individual Dockerfile and configuration files in the `docker/` directory.
