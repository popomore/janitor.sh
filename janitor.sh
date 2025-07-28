#!/bin/bash

# Linux Temporary Files Cleanup Script
# Function: Automatically clean temporary files based on disk usage and configuration parameters

set -euo pipefail

# Default configuration file path
CONFIG_FILE="${CONFIG_FILE:-/etc/janitor.conf}"

# Default log level
LOG_LEVEL="${LOG_LEVEL:-INFO}"

# Logging functions
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Convert log level string to number
get_log_level_number() {
    case "${1:-INFO}" in
        DEBUG|0) echo "0" ;;
        INFO|1)  echo "1" ;;
        WARN|2)  echo "2" ;;
        ERROR|3) echo "3" ;;
        *)       echo "1" ;; # Default to INFO
    esac
}

log_debug() {
    local current_level=$(get_log_level_number "$LOG_LEVEL")
    if [[ $current_level -le 0 ]]; then
        log "DEBUG: $1"
    fi
}

log_info() {
    local current_level=$(get_log_level_number "$LOG_LEVEL")
    if [[ $current_level -le 1 ]]; then
        log "INFO: $1"
    fi
}

log_warn() {
    local current_level=$(get_log_level_number "$LOG_LEVEL")
    if [[ $current_level -le 2 ]]; then
        log "WARN: $1"
    fi
}

log_error() {
    # Error messages are always shown regardless of log level
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
    LOG_LEVEL=INFO              # Log level: DEBUG, INFO, WARN, ERROR (default: INFO)

Examples:
    $0                          # Use default configuration
    $0 -c /path/to/config       # Use specified configuration file
    $0 -d -v                    # Dry run mode with verbose output
    $0 --debug                  # Enable debug logging
    $0 -d --debug               # Dry run with debug logging
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
            --debug)
                LOG_LEVEL="DEBUG"
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
    LOG_LEVEL="INFO"

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
                LOG_LEVEL) LOG_LEVEL="$value" ;;
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
    log_info "  Log level: $LOG_LEVEL"
}

# Get disk usage
get_disk_usage() {
    local path="$1"

    log_debug "Getting disk usage for path: $path" >&2

    # Check if path exists
    if [[ ! -e "$path" ]]; then
        log_error "Path does not exist: $path"
        echo "0"
        return 1
    fi

    # Get disk usage, handle potential errors
    local usage
    usage=$(df "$path" 2>/dev/null | awk 'NR==2 {print $5}' | sed 's/%//')

    log_debug "Raw disk usage output: $(df "$path" 2>/dev/null | head -2 | tail -1)" >&2

    # Validate the result is a number
    if [[ ! "$usage" =~ ^[0-9]+$ ]]; then
        log_error "Failed to get disk usage for path: $path"
        echo "0"
        return 1
    fi

    log_debug "Disk usage for $path: ${usage}%" >&2
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

    log_debug "Starting cleanup_directory function for: $dir" >&2

    if [[ ! -d "$dir" ]]; then
        log_warn "Directory does not exist: $dir" >&2
        printf "%d" 0
        return 0
    fi

    log_info "Starting cleanup of directory: $dir" >&2

    # Find files that meet the criteria (modification time exceeds retention period)
    local temp_file
    temp_file=$(mktemp)

    log_debug "Using retention period: ${RETENTION_HOURS} hours (${RETENTION_HOURS} * 60 = $((RETENTION_HOURS * 60)) minutes)" >&2
    log_debug "Batch size: $BATCH_SIZE files" >&2
    log_debug "Temporary file for file list: $temp_file" >&2

    # Use find to search files, sorted by modification time (oldest to newest)
    # Compatible with different systems' find commands
    if find "$dir" -type f -mmin +$((RETENTION_HOURS * 60)) -printf '%T@ %p\n' 2>/dev/null | head -1 >/dev/null 2>&1; then
        # GNU find (supports -printf)
        log_debug "Using GNU find with -printf support" >&2
        find "$dir" -type f -mmin +$((RETENTION_HOURS * 60)) -printf '%T@ %p\n' 2>/dev/null 2>&1 | \
            sort -n 2>&1 | \
            head -n "$BATCH_SIZE" 2>&1 | \
            cut -d' ' -f2- > "$temp_file" 2>&1
    else
        # BSD find or other systems that don't support -printf
        log_debug "Using BSD find or fallback method" >&2
        find "$dir" -type f -mmin +$((RETENTION_HOURS * 60)) 2>/dev/null 2>&1 | \
            while IFS= read -r file; do
                if [[ -f "$file" ]]; then
                    # Get file modification timestamp
                    mtime=$(stat -c %Y "$file" 2>/dev/null || stat -f %m "$file" 2>/dev/null || echo "0")
                    echo "$mtime $file"
                fi
            done 2>&1 | \
            sort -n 2>&1 | \
            head -n "$BATCH_SIZE" 2>&1 | \
            cut -d' ' -f2- > "$temp_file" 2>&1
    fi

    local file_count
    file_count=$(wc -l < "$temp_file")

    log_debug "Found $file_count files in temporary file list" >&2

    if [[ $file_count -eq 0 ]]; then
        log_info "No files found in directory $dir that meet deletion criteria" >&2
        rm -f "$temp_file"
        printf "%d" 0
        return 0
    fi

    log_info "Found $file_count files that meet deletion criteria" >&2

    # Show file list in debug mode
    if [[ "${LOG_LEVEL:-INFO}" == "DEBUG" ]]; then
        log_debug "Files to be processed:" >&2
        while IFS= read -r file; do
            if [[ -f "$file" ]]; then
                local file_size
                file_size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo "0")
                local file_mtime
                file_mtime=$(stat -f%m "$file" 2>/dev/null || stat -c%Y "$file" 2>/dev/null || echo "0")
                local file_date
                file_date=$(date -d "@$file_mtime" 2>/dev/null || date -r "$file_mtime" 2>/dev/null || echo "unknown")
                log_debug "  - $file (size: ${file_size} bytes, mtime: $file_date)" >&2
            fi
        done < "$temp_file"
    fi

        # Delete files
    local total_size_deleted=0
    log_debug "Starting file deletion process" >&2

    while IFS= read -r file; do
        if [[ -f "$file" ]]; then
            local file_size
            file_size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo "0")

            log_debug "Processing file: $file (size: ${file_size} bytes)" >&2

            if [[ "$DRY_RUN" == "true" ]]; then
                log_info "[DRY RUN] Will delete file: $file (size: ${file_size} bytes)" >&2
            else
                log_debug "Attempting to delete file: $file" >&2
                if rm -f "$file" 2>/dev/null; then
                    ((files_deleted++))
                    ((total_size_deleted += file_size))
                    log_debug "Successfully deleted file: $file" >&2
                    if [[ "$VERBOSE" == "true" ]]; then
                        log_info "Deleted file: $file (size: ${file_size} bytes)" >&2
                    fi
                else
                    log_warn "Failed to delete file: $file" >&2
                    log_debug "Delete operation failed for file: $file" >&2
                fi
            fi
        else
            log_debug "File no longer exists: $file" >&2
        fi
    done < "$temp_file"

    rm -f "$temp_file"
    log_debug "Cleaned up temporary file: $temp_file" >&2

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Directory $dir will delete $file_count files" >&2
        log_debug "Dry run mode - no actual files deleted" >&2
        printf "%d" "$file_count"  # Return number of files to be deleted
    else
        # Convert bytes to human readable format
        local size_mb=$((total_size_deleted / 1024 / 1024))
        local size_kb=$(((total_size_deleted % (1024 * 1024)) / 1024))
        local size_str=""
        if [[ $size_mb -gt 0 ]]; then
            size_str="${size_mb}MB"
            if [[ $size_kb -gt 0 ]]; then
                size_str="${size_str} ${size_kb}KB"
            fi
        else
            size_str="${size_kb}KB"
        fi

        log_debug "Deletion summary: $files_deleted files deleted, total size: $total_size_deleted bytes ($size_str)" >&2
        log_info "Directory $dir successfully deleted $files_deleted files (total size: $size_str)" >&2
        printf "%d" "$files_deleted"  # Return number of actually deleted files
    fi
}

# Main cleanup function
main_cleanup() {
    total_deleted=0

    log_debug "Starting main cleanup function"
    log_debug "TEMP_DIRS configuration: '$TEMP_DIRS'"

    # Convert directory list to array
    IFS=',' read -ra DIR_ARRAY <<< "$TEMP_DIRS"

    log_debug "Parsed directories: ${#DIR_ARRAY[@]} directories"
    for i in "${!DIR_ARRAY[@]}"; do
        log_debug "  Directory $((i+1)): '${DIR_ARRAY[i]}'"
    done

    for dir in "${DIR_ARRAY[@]}"; do
        # Remove leading and trailing spaces
        dir=$(echo "$dir" | xargs)
        log_debug "Processing directory: '$dir'"

        # Process directory until target threshold is reached or no more files
        while true; do
            # Check if target threshold is reached
            log_debug "Checking if target threshold is reached"
            if reached_target; then
                log_debug "Target threshold reached, stopping cleanup"
                break 2  # Break out of both while and for loops
            fi

            # Clean directory
            local deleted
            log_debug "About to call cleanup_directory for: '$dir'"
            deleted=$(cleanup_directory "$dir")
            log_debug "cleanup_directory returned: '$deleted'"
            log_debug "DEBUG: deleted=[$deleted] (length: ${#deleted})"

            # Validate that deleted is a number
            if ! [[ "$deleted" =~ ^[0-9]+$ ]]; then
                log_error "Non-numeric deleted value: '$deleted'"
                break  # Break out of while loop, move to next directory
            fi

            log_debug "Directory '$dir' cleanup result: $deleted files"
            log_debug "About to add $deleted to total_deleted (currently $total_deleted)"
            # Ensure deleted is a valid number (robust conversion)
            log_debug "Before conversion: deleted='$deleted'"
            deleted=$((10#$deleted))
            log_debug "After conversion: deleted=$deleted"
            log_debug "Before arithmetic: total_deleted=$total_deleted, deleted=$deleted"
            total_deleted=$((total_deleted + deleted))
            log_debug "After arithmetic: total_deleted=$total_deleted"
            log_debug "Total deleted so far: $total_deleted"

            # If in dry run mode, continue processing all directories
            if [[ "$DRY_RUN" == "true" ]]; then
                log_debug "Dry run mode - continuing to next directory"
                break  # Break out of while loop, move to next directory
            fi

            # If no files were deleted, move to next directory
            if [[ $deleted -eq 0 ]]; then
                log_debug "No files deleted from '$dir', moving to next directory"
                break  # Break out of while loop, move to next directory
            fi

            log_debug "Files were deleted from '$dir', will wait before next batch"

            # Brief wait to let system update disk usage
            log_debug "Waiting 1 second for system to update disk usage"
            sleep 1

            # Check if target threshold is reached after deletion
            log_debug "Checking if target threshold is reached after deletion"
            if reached_target; then
                log_debug "Target threshold reached after deletion, stopping cleanup"
                break 2  # Break out of both while and for loops
            fi

            log_debug "Target threshold not reached, will continue processing '$dir'"
        done
    done

    log_debug "Finished processing all directories"

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

            # Get detailed disk information for better monitoring
            local disk_info
            disk_info=$(df -h "/" 2>/dev/null | awk 'NR==2 {print "Used: " $3 ", Available: " $4 ", Total: " $2}')
            if [[ -n "$disk_info" ]]; then
                log_info "Disk details: $disk_info"
            fi
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
