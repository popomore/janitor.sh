#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_CONFIG_FILE="$SCRIPT_DIR/test_janitor.conf"

# Check if we're in Docker environment (both scripts in same directory)
if [[ -f "$SCRIPT_DIR/janitor.sh" ]]; then
    CLEAN_SCRIPT="$SCRIPT_DIR/janitor.sh"
else
    CLEAN_SCRIPT="$SCRIPT_DIR/../janitor.sh"
fi

# Logging functions
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log_info() {
    log "INFO: $1"
}

log_warn() {
    log "WARN: $1"
}

log_error() {
    log "ERROR: $1"
}

# Show help information
show_help() {
    cat << EOF
Temporary Files Cleanup Script Test Tool

Usage: $0 [options]

Options:
    -s, --setup          Create test environment and test files
    -c, --cleanup        Run cleanup script
    -d, --dry-run        Dry run mode test
    -v, --verify         Verify cleanup results
    -a, --all            Execute complete test flow (setup + cleanup + verify)
    -r, --reset          Reset test environment
    -h, --help           Show this help information

Examples:
    $0 -s                # Only create test environment
    $0 -a                # Execute complete test
    $0 -d                # Dry run mode test
EOF
}

# Create test configuration file
create_test_config() {
    if [[ -f "$TEST_CONFIG_FILE" ]]; then
        log_info "Test configuration file already exists: $TEST_CONFIG_FILE"
        return 0
    fi

    log_info "Creating test configuration file: $TEST_CONFIG_FILE"

    cat > "$TEST_CONFIG_FILE" << EOF
# Test configuration file
TRIGGER_THRESHOLD=80
TARGET_THRESHOLD=30
RETENTION_HOURS=1
BATCH_SIZE=50
TEMP_DIRS="/tmp/test_cleanup,/var/tmp/test_cleanup"
EOF

    log_info "Test configuration file created successfully"
}

# Get disk usage
get_disk_usage() {
    local path="${1:-/}"

    # Check if path exists
    if [[ ! -e "$path" ]]; then
        log_error "Path does not exist: $path"
        echo "0"
        return 1
    fi

    # Get disk usage, handle potential errors
    local usage
    usage=$(df "$path" 2>/dev/null | awk 'NR==2 {print $5}' | sed 's/%//')

    # Validate the result is a number
    if [[ ! "$usage" =~ ^[0-9]+$ ]]; then
        log_error "Failed to get disk usage for path: $path"
        echo "0"
        return 1
    fi

    echo "$usage"
}

# Create test directories and files
setup_test_environment() {
    log_info "Starting to create test environment..."

    # Create test directories
    local test_dirs=("/tmp/test_cleanup" "/var/tmp/test_cleanup")

    for dir in "${test_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            log_info "Created test directory: $dir"
        fi
    done

    # Record initial disk usage
    local initial_usage
    initial_usage=$(get_disk_usage)
    log_info "Initial disk usage: ${initial_usage}%"

    # Create test files with different timestamps
    log_info "Creating test files..."

    # Create old files (exceeding retention time)
    for i in {1..30}; do
        local file="/tmp/test_cleanup/old_file_${i}.txt"
        echo "This is an old test file $i" > "$file"
        # Set file time to 2 hours ago
        touch -d "2 hours ago" "$file"
    done

    for i in {1..20}; do
        local file="/var/tmp/test_cleanup/old_file_${i}.txt"
        echo "This is an old test file $i" > "$file"
        # Set file time to 3 hours ago
        touch -d "3 hours ago" "$file"
    done

    # Create new files (within retention time)
    for i in {1..10}; do
        local file="/tmp/test_cleanup/new_file_${i}.txt"
        echo "This is a new test file $i" > "$file"
        # Keep current time
    done

    for i in {1..5}; do
        local file="/var/tmp/test_cleanup/new_file_${i}.txt"
        echo "This is a new test file $i" > "$file"
        # Keep current time
    done

    # Create large files to increase disk usage (if needed)
    local current_usage
    current_usage=$(get_disk_usage)

    if [[ $current_usage -lt 80 ]]; then
        log_info "Current disk usage is low (${current_usage}%), creating large files to simulate high usage..."

        # Calculate needed file size (MB)
        local available_space
        available_space=$(df / | awk 'NR==2 {print $4}')  # KB
        local target_usage=85
        local needed_space=$(( (available_space * (target_usage - current_usage)) / (100 - target_usage) ))

        if [[ $needed_space -gt 0 ]]; then
            local file_size_mb=$((needed_space / 1024))
            if [[ $file_size_mb -gt 100 ]]; then
                file_size_mb=100  # Limit maximum file size
            fi

            log_info "Creating ${file_size_mb}MB large file to increase disk usage..."
            dd if=/dev/zero of="/tmp/test_cleanup/large_file.dat" bs=1M count=$file_size_mb 2>/dev/null || true
            touch -d "2 hours ago" "/tmp/test_cleanup/large_file.dat"
        fi
    fi

    # Display test environment information
    log_info "Test environment created successfully!"
    log_info "File statistics:"

    for dir in "${test_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            local file_count
            file_count=$(find "$dir" -type f | wc -l)
            local total_size
            total_size=$(du -sh "$dir" 2>/dev/null | cut -f1 || echo "0")
            log_info "  $dir: $file_count files, total size: $total_size"
        fi
    done

    local final_usage
    final_usage=$(get_disk_usage)
    log_info "Current disk usage: ${final_usage}%"
}

# Run cleanup script
run_cleanup() {
    local dry_run_flag=""
    if [[ "${1:-}" == "dry-run" ]]; then
        dry_run_flag="--dry-run"
        log_info "Running cleanup script (dry run mode)..."
    else
        log_info "Running cleanup script..."
    fi

    if [[ ! -f "$CLEAN_SCRIPT" ]]; then
        log_error "Cleanup script not found: $CLEAN_SCRIPT"
        return 1
    fi

    # Record state before cleanup
    local before_usage
    before_usage=$(get_disk_usage)
    log_info "Disk usage before cleanup: ${before_usage}%"

    # Run cleanup script
    bash "$CLEAN_SCRIPT" --config "$TEST_CONFIG_FILE" --verbose $dry_run_flag

    # Record state after cleanup
    if [[ -z "$dry_run_flag" ]]; then
        local after_usage
        after_usage=$(get_disk_usage)
        log_info "Disk usage after cleanup: ${after_usage}%"
        log_info "Disk usage change: $((before_usage - after_usage))%"
    fi
}

# Verify cleanup results
verify_cleanup() {
    log_info "Verifying cleanup results..."

    local test_dirs=("/tmp/test_cleanup" "/var/tmp/test_cleanup")

    for dir in "${test_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            log_info "Checking directory: $dir"

            # Count remaining files
            local total_files
            total_files=$(find "$dir" -type f | wc -l)

            local old_files
            old_files=$(find "$dir" -type f -mmin +60 | wc -l)

            local new_files
            new_files=$(find "$dir" -type f -mmin -60 | wc -l)

            log_info "  Total files: $total_files"
            log_info "  Old files (>1 hour): $old_files"
            log_info "  New files (<1 hour): $new_files"

            # List remaining old files (if any)
            if [[ $old_files -gt 0 ]]; then
                log_warn "  Remaining old files:"
                find "$dir" -type f -mmin +60 -exec ls -la {} \; | while read -r line; do
                    log_warn "    $line"
                done
            fi
        fi
    done

    local final_usage
    final_usage=$(get_disk_usage)
    log_info "Final disk usage: ${final_usage}%"
}

# Reset test environment
reset_test_environment() {
    log_info "Resetting test environment..."

    local test_dirs=("/tmp/test_cleanup" "/var/tmp/test_cleanup")

    for dir in "${test_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            rm -rf "$dir"
            log_info "Deleted test directory: $dir"
        fi
    done

    if [[ -f "$TEST_CONFIG_FILE" ]]; then
        rm -f "$TEST_CONFIG_FILE"
        log_info "Deleted test configuration file: $TEST_CONFIG_FILE"
    fi

    log_info "Test environment reset completed"
}

# Execute complete test
run_full_test() {
    log_info "Starting complete test flow..."

    # Create test configuration
    create_test_config

    # Setup test environment
    setup_test_environment

    # Wait a moment to ensure file timestamps are correct
    log_info "Waiting 2 seconds to ensure file timestamps..."
    sleep 2

    # Run cleanup script
    run_cleanup

    # Verify results
    verify_cleanup

    log_info "Complete test flow executed successfully!"
}

# Parse command line arguments
parse_args() {
    if [[ $# -eq 0 ]]; then
        show_help
        exit 0
    fi

    while [[ $# -gt 0 ]]; do
        case $1 in
            -s|--setup)
                create_test_config
                setup_test_environment
                exit 0
                ;;
            -c|--cleanup)
                run_cleanup
                exit 0
                ;;
            -d|--dry-run)
                create_test_config
                setup_test_environment
                run_cleanup "dry-run"
                exit 0
                ;;
            -v|--verify)
                verify_cleanup
                exit 0
                ;;
            -a|--all)
                run_full_test
                exit 0
                ;;
            -r|--reset)
                reset_test_environment
                exit 0
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown parameter: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Main function
main() {
    log_info "Temporary files cleanup script test tool started"
    parse_args "$@"
}

# Execute main function
main "$@"
