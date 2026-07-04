# ----------------------------------------------------------------------------
# Multi-stage Docker build for EigenLayer BLS Local Setup
# ----------------------------------------------------------------------------

# Go Builder Stage - Install Go tools
FROM golang:1.23 AS go-builder

# Install EigenLayer CLI
RUN go install github.com/Layr-Labs/eigenlayer-cli/cmd/eigenlayer@v0.10.3

# Install gRPC tools
RUN go install github.com/fullstorydev/grpcurl/cmd/grpcurl@latest

# Build BLS key generation tool
WORKDIR /build
COPY docker/eigenlayer/blskeygen/ .
RUN go mod download && \
    go build -o /go/bin/blskeygen .

# Foundry Stage - Main application container
FROM ghcr.io/foundry-rs/foundry:stable

# Switch to root user for package installation
USER root

# Install system dependencies
RUN apt-get update && apt-get install -y \
    lsof \
    jq \
    bash \
    && rm -rf /var/lib/apt/lists/*

# Copy Go binaries from builder stage
COPY --from=go-builder /go/bin/eigenlayer /usr/local/bin/
COPY --from=go-builder /go/bin/grpcurl /usr/local/bin/
COPY --from=go-builder /go/bin/blskeygen /usr/local/bin/

# Clone and build BLS middleware contracts
# Pinned to a release tag for reproducible builds — bump the tag when upgrading bls-middleware.
RUN git clone --branch v0.1 --depth 1 --recurse-submodules \
    https://github.com/BreadchainCoop/bls-middleware.git

# Clone commonware-restaking-contracts directly with all submodules
RUN git clone --recurse-submodules https://github.com/BreadchainCoop/commonware-restaking-contracts.git

# Clone the Gas Killer service repo: contracts/ carries the ECDSA AVS stack
# (EigenLayer ECDSAStakeRegistry via the eigenlayer-middleware submodule, the
# GasKillerServiceManager, and the deploy/registration forge scripts main.sh runs).
# Pinned to a commit for reproducible builds — bump when upgrading the stack.
ARG GAS_KILLER_SERVICE_REF=1e3b7bed10a65b35b2a137e15c67f99ab83840b4
RUN git clone https://github.com/gas-killer/service.git /gas-killer-service && \
    git -C /gas-killer-service checkout "${GAS_KILLER_SERVICE_REF}" && \
    git -C /gas-killer-service submodule update --init --recursive contracts/lib/eigenlayer-middleware && \
    cd /gas-killer-service/contracts && forge build

# Set working directory to root (scripts handle navigation internally)
WORKDIR /

# Copy and setup application scripts
COPY docker/eigenlayer/main.sh /main.sh
RUN chmod +x /main.sh

COPY docker/eigenlayer/register.sh /register.sh
RUN chmod +x /register.sh

COPY docker/eigenlayer/get_bls_key.sh /get_bls_key.sh
RUN chmod +x /get_bls_key.sh

COPY docker/eigenlayer/eject.sh /eject.sh
RUN chmod +x /eject.sh

# Set entrypoint
ENTRYPOINT ["/main.sh"]
