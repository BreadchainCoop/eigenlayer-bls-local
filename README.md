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
   Make sure you have filled in all the variables 
   ```
    DELEGATION_MANAGER_ADDRESS= # Depends on the desired ENV 
    STRATEGY_MANAGER_ADDRESS=
    REGISTRY_COORDINATOR_ADDRESS=
    LST_CONTRACT_ADDRESS=
    LST_STRATEGY_ADDRESS=
    FORK_URL=
    RPC_URL=http://ethereum:8545
    WEBSOCKET_RPC_URL=ws://ethereum:8545
    ENVIRONMENT= # Depends on the desired ENV 
    MAX_OPERATOR_RETRY_ATTEMPTS=10
    SERVER_PRIVATE_KEY= 
   ```

3. Build and start the services:
   ```
   docker-compose up --build
   ```
Note that the nodes and node selector only start up after the eigenlayer setup container has exited  

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
    }
}
```

Configuration options:

- **Quorum Settings**:
  - `minimumStake`: The minimum amount of stake (in wei) required for an operator to participate
  - `maxOperatorCount`: The maximum number of operators allowed in the AVS (32 by default)
  - `kickBIPsOfOperatorStake`: Percentage of an operator's stake that can be slashed (in basis points, 10000 = 100%)
  - `kickBIPsOfTotalStake`: Percentage of total stake that can be slashed (in basis points, 100 = 1%)

- **Metadata**:
  - `uri`: The URI pointing to the AVS metadata

## Accessing the Services

- Ethereum RPC: http://localhost:8545
- Node Selector: http://localhost:8080

## Notes

- The `.gitignore` file is set up to exclude sensitive information like operator keys and test account configs.
- Make sure to keep your `.env` file secure and do not commit it to version control.

For more detailed information about each component, refer to the individual Dockerfile and configuration files in the `docker/` directory.
