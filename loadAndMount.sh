#!/bin/bash

# Configuration - you can customize these filters
POOL_FILTER=""           # Set to pool name to limit to specific pool (e.g., "jax_data")
EXCLUDE_PATTERNS=(       # Patterns to exclude from processing
    # "backup"           # Exclude datasets with "backup" in the name
    # "temp"             # Exclude datasets with "temp" in the name
)

# Function to check if a dataset is mounted
is_mounted() {
    zfs get -H -o value mounted "$1" 2>/dev/null | grep -q "yes"
}

# Function to check if a dataset needs key loading
needs_key() {
    local keystatus
    keystatus=$(zfs get -H -o value keystatus "$1" 2>/dev/null)
    [[ "$keystatus" == "unavailable" ]]
}

# Function to check if dataset should be excluded
should_exclude() {
    local dataset="$1"
    for pattern in "${EXCLUDE_PATTERNS[@]}"; do
        if [[ "$dataset" == *"$pattern"* ]]; then
            return 0  # Should exclude
        fi
    done
    return 1  # Should not exclude
}

# Function to get all ZFS datasets
get_all_datasets() {
    local filter_args=""
    
    # Add pool filter if specified
    if [[ -n "$POOL_FILTER" ]]; then
        filter_args="$POOL_FILTER"
    fi
    
    # Get all datasets, excluding snapshots and bookmarks
    zfs list -H -o name -t filesystem,volume $filter_args 2>/dev/null | while IFS= read -r dataset; do
        # Skip if should be excluded
        if ! should_exclude "$dataset"; then
            echo "$dataset"
        fi
    done
}

echo "Starting dynamic ZFS key loading and mounting process..."

# Discover all ZFS datasets
echo "Discovering ZFS datasets..."
mapfile -t DATASETS < <(get_all_datasets)

if [[ ${#DATASETS[@]} -eq 0 ]]; then
    echo "No ZFS datasets found to process"
    exit 0
fi

echo "Found ${#DATASETS[@]} datasets to process:"
printf '  %s\n' "${DATASETS[@]}"
echo

# Load keys for encrypted datasets
echo "Checking and loading encryption keys..."
for dataset in "${DATASETS[@]}"; do
    if needs_key "$dataset"; then
        echo "Loading key for $dataset..."
        if zfs load-key "$dataset"; then
            echo "✓ Key loaded successfully for $dataset"
        else
            echo "✗ Failed to load key for $dataset"
        fi
    else
        echo "• Dataset $dataset doesn't need key loading"
    fi
done

echo

# Mount datasets
echo "Checking and mounting datasets..."
for dataset in "${DATASETS[@]}"; do
    if is_mounted "$dataset"; then
        echo "• Dataset $dataset is already mounted"
    else
        echo "Mounting dataset $dataset..."
        if zfs mount "$dataset"; then
            echo "✓ Successfully mounted $dataset"
        else
            echo "✗ Failed to mount $dataset"
        fi
    fi
done

echo
echo "ZFS key loading and mounting process completed"