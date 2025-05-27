#!/bin/bash

# Docker Test Runner Script
# Used to build Docker image and run temporary file cleanup script tests

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE_NAME="janitor-test"
CONTAINER_NAME="janitor-test-container"

# Logging functions
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log_info() {
    log "INFO: $1"
}

log_error() {
    log "ERROR: $1"
}

# Show help information
show_help() {
    cat << EOF
Docker Test Runner Script

Usage: $0 [options]

Options:
    -b, --build          Build Docker image
    -t, --test           Run complete test
    -d, --dry-run        Run dry run mode test
    -i, --interactive    Start interactive container
    -e, --exec COMMAND   Execute specified command in container
    -c, --cleanup        Clean Docker resources
    -h, --help           Show this help information

Examples:
    $0 -b                                    # Build image
    $0 -t                                    # Run complete test
    $0 -d                                    # Run dry run test
    $0 -i                                    # Start interactive container for manual testing
    $0 -e "./janitor.sh --help"    # Execute specified command
    $0 -e "./test_janitor.sh -s"   # Create test environment
EOF
}

# Build Docker image
build_image() {
    log_info "Starting to build Docker image..."

    cd "$SCRIPT_DIR"

    if ! docker build -f test/Dockerfile.test -t "$IMAGE_NAME" .; then
        log_error "Docker image build failed"
        exit 1
    fi

    log_info "Docker image build completed: $IMAGE_NAME"
}

# Clean Docker resources
cleanup_docker() {
    log_info "Cleaning Docker resources..."

    # Stop and remove container
    if docker ps -a --format "table {{.Names}}" | grep -q "$CONTAINER_NAME"; then
        docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
        log_info "Removed container: $CONTAINER_NAME"
    fi

    # Remove image
    if docker images --format "table {{.Repository}}" | grep -q "$IMAGE_NAME"; then
        docker rmi "$IMAGE_NAME" 2>/dev/null || true
        log_info "Removed image: $IMAGE_NAME"
    fi

    log_info "Docker resources cleanup completed"
}

# Run test
run_test() {
    local test_mode="${1:-full}"

    log_info "Starting Docker test (mode: $test_mode)..."

    # Ensure image exists
    if ! docker images --format "table {{.Repository}}" | grep -q "$IMAGE_NAME"; then
        log_info "Image does not exist, starting build..."
        build_image
    fi

    # Remove existing container
    docker rm -f "$CONTAINER_NAME" 2>/dev/null || true

    # Run test
    local test_command
    case "$test_mode" in
        "full")
            test_command="/app/test_janitor.sh --all"
            ;;
        "dry-run")
            test_command="/app/test_janitor.sh --dry-run"
            ;;
        *)
            log_error "Unknown test mode: $test_mode"
            exit 1
            ;;
    esac

    log_info "Running test command: $test_command"

    if docker run --name "$CONTAINER_NAME" --rm "$IMAGE_NAME" bash -c "$test_command"; then
        log_info "Test execution successful!"
    else
        log_error "Test execution failed!"
        exit 1
    fi
}

# Start interactive container
run_interactive() {
    log_info "Starting interactive Docker container..."

    # Ensure image exists
    if ! docker images --format "table {{.Repository}}" | grep -q "$IMAGE_NAME"; then
        log_info "Image does not exist, starting build..."
        build_image
    fi

    # Remove existing container
    docker rm -f "$CONTAINER_NAME" 2>/dev/null || true

    log_info "Starting interactive container, you can manually run the following commands for testing:"
    log_info "  ./test_janitor.sh --help     # View test tool help"
    log_info "  ./test_janitor.sh --all      # Run complete test"
    log_info "  ./test_janitor.sh --dry-run  # Run dry run test"
    log_info "  ./janitor.sh --help          # View cleanup script help"

    docker run -it --name "$CONTAINER_NAME" --rm "$IMAGE_NAME" bash
}

# Execute specified command in container
run_exec() {
    local command="$1"

    log_info "Executing command in Docker container: $command"

    # Ensure image exists
    if ! docker images --format "table {{.Repository}}" | grep -q "$IMAGE_NAME"; then
        log_info "Image does not exist, starting build..."
        build_image
    fi

    # Remove existing container
    docker rm -f "$CONTAINER_NAME" 2>/dev/null || true

    if docker run --name "$CONTAINER_NAME" --rm "$IMAGE_NAME" bash -c "$command"; then
        log_info "Command execution successful!"
    else
        log_error "Command execution failed!"
        exit 1
    fi
}

# Parse command line arguments
parse_args() {
    if [[ $# -eq 0 ]]; then
        show_help
        exit 0
    fi

    while [[ $# -gt 0 ]]; do
        case $1 in
            -b|--build)
                build_image
                exit 0
                ;;
            -t|--test)
                run_test "full"
                exit 0
                ;;
            -d|--dry-run)
                run_test "dry-run"
                exit 0
                ;;
            -i|--interactive)
                run_interactive
                exit 0
                ;;
            -e|--exec)
                if [[ -z "${2:-}" ]]; then
                    log_error "-e/--exec option requires specifying the command to execute"
                    show_help
                    exit 1
                fi
                run_exec "$2"
                exit 0
                ;;
            -c|--cleanup)
                cleanup_docker
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

# Check if Docker is available
check_docker() {
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed or not in PATH"
        exit 1
    fi

    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running or no permission to access"
        exit 1
    fi
}

# Main function
main() {
    log_info "Docker test runner script started"

    # Check Docker environment
    check_docker

    # Parse arguments
    parse_args "$@"
}

# Execute main function
main "$@"
