#!/bin/bash
if [ $# -ne 2 ]; then
    echo "Usage: $0 <password> <account>"
    exit 1
fi

PASSWORD="$1"
ACCOUNT="$2"

private_bls_key=""
attempt=1
max_attempts=5

while [ -z "$private_bls_key" ] || [ ${#private_bls_key} -le 66 ]; do
    if [ $attempt -gt $max_attempts ]; then
        break
    fi

    # Clean up any existing tmux session
    tmux has-session -t export_key 2>/dev/null && tmux kill-session -t export_key >/dev/null 2>&1

    # Create a new tmux session
    tmux new-session -d -s export_key

    # Send the export command
    tmux send-keys -t export_key "eigenlayer keys export --key-type bls $ACCOUNT" C-m

    # Wait a bit and send "y"
    sleep 1
    tmux send-keys -t export_key "y" C-m

    # Wait a bit and send password
    sleep 1
    tmux send-keys -t export_key "$PASSWORD" C-m

    # Capture the output and format it
    sleep 2
    private_bls_key=$(tmux capture-pane -t export_key -S - -E - -p | grep -A1 "Private key:" | tr -d 'Private key: \n')

    # Kill the session
    tmux kill-session -t export_key 2>/dev/null || true

    if [ -z "$private_bls_key" ] || [ ${#private_bls_key} -le 66 ]; then
        attempt=$((attempt + 1))
        sleep 2
    fi
done

echo "$private_bls_key"
