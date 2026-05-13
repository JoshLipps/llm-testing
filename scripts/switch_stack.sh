#!/bin/bash

# Script to switch between vLLM (Gemma), Llama (Gemma), and Llama (Qwen) stacks.
# Usage: ./switch_stack.sh [vllm-gemma | llama-gemma | llama-qwen]

TARGET=$1

if [[ -z "$TARGET" ]]; then
    echo "Usage: $0 {vllm-gemma | llama-gemma | llama-qwen}"
    exit 1
fi

declare -A STACKS
STACKS=(
    ["vllm-gemma"]="docker-compose.vllm.yaml"
    ["llama-gemma"]="docker-compose.gemma.yaml"
    ["llama-qwen"]="docker-compose.yaml"
)

if [[ -z "${STACKS[$TARGET]}" ]]; then
    echo "Error: Invalid stack '$TARGET'"
    echo "Available stacks: ${!STACKS[@]}"
    exit 1
fi

TARGET_FILE=${STACKS[$TARGET]}

echo ">>> Switching to stack: $TARGET (using $TARGET_FILE)"

# 1. Stop all other stacks
for NAME in "${!STACKS[@]}"; do
    if [[ "$NAME" != "$TARGET" ]]; then
        FILE=${STACKS[$NAME]}
        if [[ -f "$FILE" ]]; then
            echo ">>> Stopping stack: $NAME ($FILE)..."
            docker compose -f "$FILE" down
        else
            echo ">>> Warning: $FILE not found, skipping stop."
        fi
    fi
done

# 2. Start the target stack
if [[ -f "$TARGET_FILE" ]]; then
    echo ">>> Starting stack: $TARGET ($TARGET_FILE)..."
    # We use 'up -d' to start in detached mode.
    docker compose -f "$TARGET_FILE" up -d
    
    if [[ $? -eq 0 ]]; then
        echo ">>> Success! Stack '$TARGET' is running."
        echo ">>> Use 'docker compose -f $TARGET_FILE logs -f' to follow logs."
    else
        echo ">>> Error: Failed to start '$TARGET'."
        exit 1
    fi
else
    echo ">>> Error: Target file '$TARGET_FILE' not found."
    exit 1
fi
