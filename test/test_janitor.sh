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

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

# Show help information
show_help() {
    cat << EOF
Temporary Files Cleanup Script Comprehensive Test Tool

Usage: $0 [options]

Basic Test Options:
    -s, --setup          Create test environment and test files
    -c, --cleanup        Run cleanup script
    -d, --dry-run        Dry run mode test
    -v, --verify         Verify cleanup results
    -a, --all            Execute complete test flow (setup + cleanup + verify)
    -r, --reset          Reset test environment

Advanced Test Options:
    --test-multiple-dirs     Test multiple directories functionality
    --test-multilevel-dirs   Test multi-level directory support
    --test-debug-logging     Test debug logging functionality
    --test-numeric-levels    Test numeric log levels
    --test-edge-cases        Test edge cases and error handling
    --test-disk-usage        Test disk usage analysis
    --test-docker            Run tests in Docker environment

Performance Tests:
    --test-performance       Run performance tests
    --test-benchmark         Run benchmark tests

Examples:
    $0 -s                    # Only create test environment
    $0 -a                    # Execute complete basic test
    $0 -d                    # Dry run mode test
    $0 --test-multiple-dirs  # Test multiple directories
    $0 --test-debug-logging  # Test debug logging
    $0 --test-all            # Run all tests
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
LOG_LEVEL=INFO
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

# Test multiple directories functionality
test_multiple_dirs() {
    log_info "Testing multiple directories functionality..."

    local test_root="/tmp/test_multiple_dirs"
    local config_file="/tmp/test_multiple_dirs.conf"

    # Clean up any existing test directory
    if [[ -d "$test_root" ]]; then
        rm -rf "$test_root"
    fi

    # Create test directories
    mkdir -p "$test_root/dir1"
    mkdir -p "$test_root/dir2"
    mkdir -p "$test_root/dir3"

    # Create test files
    for i in {1..5}; do
        echo "old file $i" > "$test_root/dir1/old_file$i.txt"
        echo "new file $i" > "$test_root/dir1/new_file$i.txt"
        echo "old file $i" > "$test_root/dir2/old_file$i.txt"
        echo "new file $i" > "$test_root/dir2/new_file$i.txt"
        echo "old file $i" > "$test_root/dir3/old_file$i.txt"
        echo "new file $i" > "$test_root/dir3/new_file$i.txt"
    done

    # Set old modification times
    local old_time=$(date -d "25 hours ago" +%Y%m%d%H%M.%S 2>/dev/null || date -v-25H +%Y%m%d%H%M.%S 2>/dev/null || echo "")
    if [[ -n "$old_time" ]]; then
        find "$test_root" -name "old_file*.txt" -exec touch -t "$old_time" {} \;
    fi

    # Create test config
    cat > "$config_file" << EOF
TRIGGER_THRESHOLD=50
TARGET_THRESHOLD=10
RETENTION_HOURS=24
BATCH_SIZE=100
TEMP_DIRS="$test_root/dir1,$test_root/dir2,$test_root/dir3"
LOG_LEVEL=INFO
EOF

    # Run test
    log_info "Running multiple directories test..."
    "$CLEAN_SCRIPT" -c "$config_file" -d -v

    # Verify results
    log_info "Verifying multiple directories test results..."
    for dir in "$test_root/dir1" "$test_root/dir2" "$test_root/dir3"; do
        local old_count=$(find "$dir" -name "old_file*.txt" | wc -l)
        local new_count=$(find "$dir" -name "new_file*.txt" | wc -l)
        log_info "  $dir: $old_count old files remaining, $new_count new files preserved"
    done

    # Cleanup
    rm -rf "$test_root"
    rm -f "$config_file"

    log_info "Multiple directories test completed"
}

# Test multi-level directory support
test_multilevel_dirs() {
    log_info "Testing multi-level directory support..."

    local test_root="/tmp/test_multilevel_dirs"
    local config_file="/tmp/test_multilevel_dirs.conf"

    # Clean up any existing test directory
    if [[ -d "$test_root" ]]; then
        rm -rf "$test_root"
    fi

    # Create multi-level structure
    mkdir -p "$test_root/level1/level2/level3/level4/level5"

    # Create files at different levels
    echo "old file at root" > "$test_root/old_file_root.txt"
    echo "old file at level1" > "$test_root/level1/old_file_level1.txt"
    echo "old file at level2" > "$test_root/level1/level2/old_file_level2.txt"
    echo "old file at level3" > "$test_root/level1/level2/level3/old_file_level3.txt"
    echo "old file at level4" > "$test_root/level1/level2/level3/level4/old_file_level4.txt"
    echo "old file at level5" > "$test_root/level1/level2/level3/level4/level5/old_file_level5.txt"

    # Create some new files
    echo "new file at root" > "$test_root/new_file_root.txt"
    echo "new file at level3" > "$test_root/level1/level2/level3/new_file_level3.txt"

    # Set old modification times
    local old_time=$(date -d "25 hours ago" +%Y%m%d%H%M.%S 2>/dev/null || date -v-25H +%Y%m%d%H%M.%S 2>/dev/null || echo "")
    if [[ -n "$old_time" ]]; then
        find "$test_root" -name "old_file*.txt" -exec touch -t "$old_time" {} \;
    fi

    # Create test config
    cat > "$config_file" << EOF
TRIGGER_THRESHOLD=50
TARGET_THRESHOLD=10
RETENTION_HOURS=24
BATCH_SIZE=100
TEMP_DIRS="$test_root"
LOG_LEVEL=INFO
EOF

    # Run test
    log_info "Running multi-level directory test..."
    "$CLEAN_SCRIPT" -c "$config_file" -d -v

    # Verify results
    log_info "Verifying multi-level directory test results..."
    local old_count=$(find "$test_root" -name "old_file*.txt" | wc -l)
    local new_count=$(find "$test_root" -name "new_file*.txt" | wc -l)
    log_info "  Old files remaining: $old_count"
    log_info "  New files preserved: $new_count"

    # Cleanup
    rm -rf "$test_root"
    rm -f "$config_file"

    log_info "Multi-level directory test completed"
}

# Test debug logging functionality
test_debug_logging() {
    log_info "Testing debug logging functionality..."

    local test_root="/tmp/test_debug_logging"
    local config_file="/tmp/test_debug_logging.conf"

    # Clean up any existing test directory
    if [[ -d "$test_root" ]]; then
        rm -rf "$test_root"
    fi

    # Create test files
    mkdir -p "$test_root"
    echo "old file 1" > "$test_root/old_file1.txt"
    echo "old file 2" > "$test_root/old_file2.txt"
    echo "new file 1" > "$test_root/new_file1.txt"
    echo "new file 2" > "$test_root/new_file2.txt"

    # Set old modification times
    local old_time=$(date -d "25 hours ago" +%Y%m%d%H%M.%S 2>/dev/null || date -v-25H +%Y%m%d%H%M.%S 2>/dev/null || echo "")
    if [[ -n "$old_time" ]]; then
        touch -t "$old_time" "$test_root/old_file1.txt"
        touch -t "$old_time" "$test_root/old_file2.txt"
    fi

    # Test different log levels
    for level in "DEBUG" "INFO" "WARN" "ERROR"; do
        log_info "Testing LOG_LEVEL=$level"

        # Create test config
        cat > "$config_file" << EOF
TRIGGER_THRESHOLD=50
TARGET_THRESHOLD=10
RETENTION_HOURS=24
BATCH_SIZE=100
TEMP_DIRS="$test_root"
LOG_LEVEL=$level
EOF

        # Run test
        local output_file="/tmp/test_debug_${level}.log"
        "$CLEAN_SCRIPT" -c "$config_file" -d -v > "$output_file" 2>&1

        # Show results
        local debug_lines=$(grep -c "DEBUG:" "$output_file" || echo "0")
        local info_lines=$(grep -c "INFO:" "$output_file" || echo "0")
        local warn_lines=$(grep -c "WARN:" "$output_file" || echo "0")
        local error_lines=$(grep -c "ERROR:" "$output_file" || echo "0")

        log_info "  LOG_LEVEL=$level: DEBUG=$debug_lines, INFO=$info_lines, WARN=$warn_lines, ERROR=$error_lines"
    done

    # Cleanup
    rm -rf "$test_root"
    rm -f "$config_file"
    rm -f /tmp/test_debug_*.log

    log_info "Debug logging test completed"
}

# Test numeric log levels
test_numeric_levels() {
    log_info "Testing numeric log levels..."

    local test_root="/tmp/test_numeric_levels"
    local config_file="/tmp/test_numeric_levels.conf"

    # Clean up any existing test directory
    if [[ -d "$test_root" ]]; then
        rm -rf "$test_root"
    fi

    # Create test files
    mkdir -p "$test_root"
    echo "old file 1" > "$test_root/old_file1.txt"
    echo "old file 2" > "$test_root/old_file2.txt"
    echo "new file 1" > "$test_root/new_file1.txt"
    echo "new file 2" > "$test_root/new_file2.txt"

    # Set old modification times
    local old_time=$(date -d "25 hours ago" +%Y%m%d%H%M.%S 2>/dev/null || date -v-25H +%Y%m%d%H%M.%S 2>/dev/null || echo "")
    if [[ -n "$old_time" ]]; then
        touch -t "$old_time" "$test_root/old_file1.txt"
        touch -t "$old_time" "$test_root/old_file2.txt"
    fi

    # Test numeric values
    for level in "0" "1" "2" "3"; do
        log_info "Testing LOG_LEVEL=$level"

        # Create test config
        cat > "$config_file" << EOF
TRIGGER_THRESHOLD=50
TARGET_THRESHOLD=10
RETENTION_HOURS=24
BATCH_SIZE=100
TEMP_DIRS="$test_root"
LOG_LEVEL=$level
EOF

        # Run test
        local output_file="/tmp/test_numeric_${level}.log"
        "$CLEAN_SCRIPT" -c "$config_file" -d -v > "$output_file" 2>&1

        # Show results
        local debug_lines=$(grep -c "DEBUG:" "$output_file" || echo "0")
        local info_lines=$(grep -c "INFO:" "$output_file" || echo "0")
        local warn_lines=$(grep -c "WARN:" "$output_file" || echo "0")
        local error_lines=$(grep -c "ERROR:" "$output_file" || echo "0")

        log_info "  LOG_LEVEL=$level: DEBUG=$debug_lines, INFO=$info_lines, WARN=$warn_lines, ERROR=$error_lines"
    done

    # Cleanup
    rm -rf "$test_root"
    rm -f "$config_file"
    rm -f /tmp/test_numeric_*.log

    log_info "Numeric log levels test completed"
}

# Test edge cases
test_edge_cases() {
    log_info "Testing edge cases..."

    local test_root="/tmp/test_edge_cases"
    local config_file="/tmp/test_edge_cases.conf"

    # Clean up any existing test directory
    if [[ -d "$test_root" ]]; then
        rm -rf "$test_root"
    fi

    # Create test config
    cat > "$config_file" << EOF
TRIGGER_THRESHOLD=50
TARGET_THRESHOLD=10
RETENTION_HOURS=24
BATCH_SIZE=100
TEMP_DIRS="$test_root"
LOG_LEVEL=INFO
EOF

    # Test 1: Empty directory
    log_info "Test 1: Empty directory"
    mkdir -p "$test_root/empty"
    "$CLEAN_SCRIPT" -c "$config_file" -d -v

    # Test 2: Directory with only new files
    log_info "Test 2: Directory with only new files"
    mkdir -p "$test_root/new_only"
    echo "new file" > "$test_root/new_only/new_file.txt"
    "$CLEAN_SCRIPT" -c "$config_file" -d -v

    # Test 3: Directory with only old files
    log_info "Test 3: Directory with only old files"
    mkdir -p "$test_root/old_only"
    echo "old file" > "$test_root/old_only/old_file.txt"
    local old_time=$(date -d "25 hours ago" +%Y%m%d%H%M.%S 2>/dev/null || date -v-25H +%Y%m%d%H%M.%S 2>/dev/null || echo "")
    if [[ -n "$old_time" ]]; then
        touch -t "$old_time" "$test_root/old_only/old_file.txt"
    fi
    "$CLEAN_SCRIPT" -c "$config_file" -d -v

    # Test 4: Non-existent directory
    log_info "Test 4: Non-existent directory"
    cat > "$config_file" << EOF
TRIGGER_THRESHOLD=50
TARGET_THRESHOLD=10
RETENTION_HOURS=24
BATCH_SIZE=100
TEMP_DIRS="/tmp/non_existent_dir"
LOG_LEVEL=INFO
EOF
    "$CLEAN_SCRIPT" -c "$config_file" -d -v

    # Cleanup
    rm -rf "$test_root"
    rm -f "$config_file"

    log_info "Edge cases test completed"
}

# Test disk usage analysis
test_disk_usage() {
    log_info "Testing disk usage analysis..."

    local test_root="/tmp/test_disk_usage"
    local config_file="/tmp/test_disk_usage.conf"

    # Clean up any existing test directory
    if [[ -d "$test_root" ]]; then
        rm -rf "$test_root"
    fi

    # Create test files with known sizes
    mkdir -p "$test_root"

    # Create files of different sizes
    for i in {1..10}; do
        dd if=/dev/zero of="$test_root/file_${i}MB.dat" bs=1M count=$i 2>/dev/null || true
    done

    # Set old modification times
    local old_time=$(date -d "25 hours ago" +%Y%m%d%H%M.%S 2>/dev/null || date -v-25H +%Y%m%d%H%M.%S 2>/dev/null || echo "")
    if [[ -n "$old_time" ]]; then
        find "$test_root" -type f -exec touch -t "$old_time" {} \;
    fi

    # Create test config
    cat > "$config_file" << EOF
TRIGGER_THRESHOLD=50
TARGET_THRESHOLD=10
RETENTION_HOURS=24
BATCH_SIZE=100
TEMP_DIRS="$test_root"
LOG_LEVEL=INFO
EOF

    # Get initial disk usage
    local initial_usage=$(get_disk_usage)
    log_info "Initial disk usage: ${initial_usage}%"

    # Run cleanup
    "$CLEAN_SCRIPT" -c "$config_file" -v

    # Get final disk usage
    local final_usage=$(get_disk_usage)
    log_info "Final disk usage: ${final_usage}%"
    log_info "Disk usage change: $((initial_usage - final_usage))%"

    # Cleanup
    rm -rf "$test_root"
    rm -f "$config_file"

    log_info "Disk usage analysis test completed"
}

# Test performance
test_performance() {
    log_info "Testing performance..."

    local test_root="/tmp/test_performance"
    local config_file="/tmp/test_performance.conf"

    # Clean up any existing test directory
    if [[ -d "$test_root" ]]; then
        rm -rf "$test_root"
    fi

    # Create test files
    mkdir -p "$test_root"
    for i in {1..1000}; do
        echo "test file $i" > "$test_root/file_$i.txt"
    done

    # Set old modification times
    local old_time=$(date -d "25 hours ago" +%Y%m%d%H%M.%S 2>/dev/null || date -v-25H +%Y%m%d%H%M.%S 2>/dev/null || echo "")
    if [[ -n "$old_time" ]]; then
        find "$test_root" -type f -exec touch -t "$old_time" {} \;
    fi

    # Create test config
    cat > "$config_file" << EOF
TRIGGER_THRESHOLD=50
TARGET_THRESHOLD=10
RETENTION_HOURS=24
BATCH_SIZE=100
TEMP_DIRS="$test_root"
LOG_LEVEL=INFO
EOF

    # Run performance test
    log_info "Running performance test with 1000 files..."
    time "$CLEAN_SCRIPT" -c "$config_file" -v

    # Cleanup
    rm -rf "$test_root"
    rm -f "$config_file"

    log_info "Performance test completed"
}

# Run all tests
run_all_tests() {
    log_info "Running all tests..."

    # Basic tests
    test_multiple_dirs
    test_multilevel_dirs
    test_debug_logging
    test_numeric_levels
    test_edge_cases
    test_disk_usage
    test_performance

    log_info "All tests completed successfully!"
}

# Reset test environment
reset_test_environment() {
    log_info "Resetting test environment..."

    local test_dirs=(
        "/tmp/test_cleanup"
        "/var/tmp/test_cleanup"
        "/tmp/test_multiple_dirs"
        "/tmp/test_multilevel_dirs"
        "/tmp/test_debug_logging"
        "/tmp/test_numeric_levels"
        "/tmp/test_edge_cases"
        "/tmp/test_disk_usage"
        "/tmp/test_performance"
    )

    for dir in "${test_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            rm -rf "$dir"
            log_info "Deleted test directory: $dir"
        fi
    done

    # Clean up test config files
    local config_files=(
        "$TEST_CONFIG_FILE"
        "/tmp/test_multiple_dirs.conf"
        "/tmp/test_multilevel_dirs.conf"
        "/tmp/test_debug_logging.conf"
        "/tmp/test_numeric_levels.conf"
        "/tmp/test_edge_cases.conf"
        "/tmp/test_disk_usage.conf"
        "/tmp/test_performance.conf"
    )

    for config in "${config_files[@]}"; do
        if [[ -f "$config" ]]; then
            rm -f "$config"
            log_info "Deleted test config file: $config"
        fi
    done

    # Clean up log files
    rm -f /tmp/test_debug_*.log
    rm -f /tmp/test_numeric_*.log

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
            --test-multiple-dirs)
                test_multiple_dirs
                exit 0
                ;;
            --test-multilevel-dirs)
                test_multilevel_dirs
                exit 0
                ;;
            --test-debug-logging)
                test_debug_logging
                exit 0
                ;;
            --test-numeric-levels)
                test_numeric_levels
                exit 0
                ;;
            --test-edge-cases)
                test_edge_cases
                exit 0
                ;;
            --test-disk-usage)
                test_disk_usage
                exit 0
                ;;
            --test-performance)
                test_performance
                exit 0
                ;;
            --test-all)
                run_all_tests
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
    log_info "Temporary files cleanup script comprehensive test tool started"
    parse_args "$@"
}

# Execute main function
main "$@"
