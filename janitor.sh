#!/bin/bash

# Linux Temporary Files Cleanup Script
# Function: Automatically clean temporary files based on disk usage and configuration parameters

set -euo pipefail

# Default configuration file path
CONFIG_FILE="${CONFIG_FILE:-/etc/janitor.conf}"

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
Linux Temporary Files Cleanup Script

Usage: $0 [options]

Options:
    -c, --config FILE    Specify configuration file path (default: $CONFIG_FILE)
    -d, --dry-run        Dry run mode, do not actually delete files
    -v, --verbose        Verbose output mode
    -h, --help           Show this help information

Configuration file format:
    TRIGGER_THRESHOLD=90        # Trigger threshold (disk usage percentage)
    TARGET_THRESHOLD=50         # Target threshold (disk usage percentage)
    RETENTION_HOURS=24          # File retention time (hours)
    BATCH_SIZE=100              # Number of files to delete per batch
    TEMP_DIRS="/tmp,/var/tmp"   # Temporary directories list, comma separated

Examples:
    $0                          # Use default configuration
    $0 -c /path/to/config       # Use specified configuration file
    $0 -d -v                    # Dry run mode with verbose output
EOF
}

# Parse command line arguments
parse_args() {
    DRY_RUN=false
    VERBOSE=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
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

# Load configuration file
load_config() {
    # Set default values
    TRIGGER_THRESHOLD=90
    TARGET_THRESHOLD=50
    RETENTION_HOURS=24
    BATCH_SIZE=100
    TEMP_DIRS="/tmp"

    # Load configuration
    if [[ -f "$CONFIG_FILE" ]]; then
        log_info "Loading configuration file: $CONFIG_FILE"

        # Only load configuration lines starting with letters, ignore comments
        while IFS='=' read -r key value; do
            # Skip comments and empty lines
            [[ $key =~ ^[[:space:]]*# ]] && continue
            [[ -z "$key" ]] && continue

            # Remove leading and trailing spaces
            key=$(echo "$key" | xargs)
            value=$(echo "$value" | xargs)

            # Remove quotes from value if present
            value=$(echo "$value" | sed 's/^["'\'']\|["'\'']$//g')

            case "$key" in
                TRIGGER_THRESHOLD) TRIGGER_THRESHOLD="$value" ;;
                TARGET_THRESHOLD) TARGET_THRESHOLD="$value" ;;
                RETENTION_HOURS) RETENTION_HOURS="$value" ;;
                BATCH_SIZE) BATCH_SIZE="$value" ;;
                TEMP_DIRS) TEMP_DIRS="$value" ;;
            esac
        done < "$CONFIG_FILE"
    fi

    # Validate configuration
    if [[ $TRIGGER_THRESHOLD -le $TARGET_THRESHOLD ]]; then
        log_error "Trigger threshold ($TRIGGER_THRESHOLD) must be greater than target threshold ($TARGET_THRESHOLD)"
        exit 1
    fi

    log_info "Configuration loaded successfully:"
    log_info "  Trigger threshold: ${TRIGGER_THRESHOLD}%"
    log_info "  Target threshold: ${TARGET_THRESHOLD}%"
    log_info "  Retention hours: ${RETENTION_HOURS} hours"
    log_info "  Batch size: ${BATCH_SIZE} files"
    log_info "  Temp directories: $TEMP_DIRS"
}

# Get disk usage
get_disk_usage() {
    local path="$1"

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

# Check if cleanup is needed
should_cleanup() {
    local current_usage
    current_usage=$(get_disk_usage "/")

    # Check if get_disk_usage failed
    if [[ $? -ne 0 ]]; then
        log_error "Failed to get disk usage, cannot determine if cleanup is needed"
        return 1
    fi

    log_info "Current disk usage: ${current_usage}%"

    if [[ $current_usage -ge $TRIGGER_THRESHOLD ]]; then
        log_info "Disk usage (${current_usage}%) exceeds trigger threshold (${TRIGGER_THRESHOLD}%), starting cleanup"
        return 0
    else
        log_info "Disk usage (${current_usage}%) does not exceed trigger threshold (${TRIGGER_THRESHOLD}%), no cleanup needed"
        return 1
    fi
}

# Check if target threshold is reached
reached_target() {
    local current_usage
    current_usage=$(get_disk_usage "/")

    # Check if get_disk_usage failed
    if [[ $? -ne 0 ]]; then
        log_error "Failed to get disk usage, cannot determine if target is reached"
        return 1
    fi

    if [[ $current_usage -le $TARGET_THRESHOLD ]]; then
        log_info "Disk usage (${current_usage}%) has reached target threshold (${TARGET_THRESHOLD}%), stopping cleanup"
        return 0
    else
        return 1
    fi
}

# Clean specified directory
cleanup_directory() {
    local dir="$1"
    local files_deleted=0

    if [[ ! -d "$dir" ]]; then
        log_warn "Directory does not exist: $dir" >&2
        echo 0
        return 0
    fi

    log_info "Starting cleanup of directory: $dir" >&2

    # Find files that meet the criteria (modification time exceeds retention period)
    local temp_file
    temp_file=$(mktemp)

    # Use find to search files, sorted by modification time (oldest to newest)
    # Compatible with different systems' find commands
    if find "$dir" -type f -mmin +$((RETENTION_HOURS * 60)) -printf '%T@ %p\n' 2>/dev/null | head -1 >/dev/null 2>&1; then
        # GNU find (supports -printf)
        find "$dir" -type f -mmin +$((RETENTION_HOURS * 60)) -printf '%T@ %p\n' 2>/dev/null | \
            sort -n | \
            head -n "$BATCH_SIZE" | \
            cut -d' ' -f2- > "$temp_file"
    else
        # BSD find or other systems that don't support -printf
        find "$dir" -type f -mmin +$((RETENTION_HOURS * 60)) 2>/dev/null | \
            while IFS= read -r file; do
                if [[ -f "$file" ]]; then
                    # Get file modification timestamp
                    mtime=$(stat -c %Y "$file" 2>/dev/null || stat -f %m "$file" 2>/dev/null || echo "0")
                    echo "$mtime $file"
                fi
            done | \
            sort -n | \
            head -n "$BATCH_SIZE" | \
            cut -d' ' -f2- > "$temp_file"
    fi

    local file_count
    file_count=$(wc -l < "$temp_file")

    if [[ $file_count -eq 0 ]]; then
        log_info "No files found in directory $dir that meet deletion criteria" >&2
        rm -f "$temp_file"
        echo 0
        return 0
    fi

    log_info "Found $file_count files that meet deletion criteria" >&2

    # Delete files
    while IFS= read -r file; do
        if [[ -f "$file" ]]; then
            local file_size
            file_size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo "0")

            if [[ "$DRY_RUN" == "true" ]]; then
                log_info "[DRY RUN] Will delete file: $file (size: ${file_size} bytes)" >&2
            else
                if rm -f "$file" 2>/dev/null; then
                    ((files_deleted++))
                    if [[ "$VERBOSE" == "true" ]]; then
                        log_info "Deleted file: $file (size: ${file_size} bytes)" >&2
                    fi
                else
                    log_warn "Failed to delete file: $file" >&2
                fi
            fi
        fi
    done < "$temp_file"

    rm -f "$temp_file"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Directory $dir will delete $file_count files" >&2
        echo $file_count  # Return number of files to be deleted
    else
        log_info "Directory $dir successfully deleted $files_deleted files" >&2
        echo $files_deleted  # Return number of actually deleted files
    fi
}

# Main cleanup function
main_cleanup() {
    local total_deleted=0

    # Convert directory list to array
    IFS=',' read -ra DIR_ARRAY <<< "$TEMP_DIRS"

    for dir in "${DIR_ARRAY[@]}"; do
        # Remove leading and trailing spaces
        dir=$(echo "$dir" | xargs)

        # Check if target threshold is reached
        if reached_target; then
            break
        fi

        # Clean directory
        local deleted
        deleted=$(cleanup_directory "$dir")
        ((total_deleted += deleted))

        # If in dry run mode, continue processing all directories
        if [[ "$DRY_RUN" == "true" ]]; then
            continue
        fi

        # If no files were deleted, skip to next directory
        if [[ $deleted -eq 0 ]]; then
            continue
        fi

        # Brief wait to let system update disk usage
        sleep 1
    done

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Total files to be deleted: $total_deleted"
    else
        log_info "Cleanup completed, total files deleted: $total_deleted"
        local final_usage
        final_usage=$(get_disk_usage "/")

        # Check if get_disk_usage failed
        if [[ $? -ne 0 ]]; then
            log_warn "Failed to get final disk usage"
        else
            log_info "Final disk usage: ${final_usage}%"
        fi
    fi
}

# Main function
main() {
    log_info "Starting temporary files cleanup script"

    # Parse command line arguments
    parse_args "$@"

    # Load configuration
    load_config

    # Check if cleanup is needed
    if should_cleanup; then
        main_cleanup
    fi

    log_info "Script execution completed"
}

# Execute main function
main "$@"
