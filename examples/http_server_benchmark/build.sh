#!/bin/bash

# HTTP Server Benchmark Docker Build Script
# This script builds the Docker image for running HTTP server benchmarks

set -e

# Configuration
IMAGE_NAME="http-benchmark"
IMAGE_TAG="latest"
FULL_IMAGE_NAME="${IMAGE_NAME}:${IMAGE_TAG}"
ROOT_PATH="$(cd "$(dirname "$0")/../../" && pwd)"
DOCKERFILE="${ROOT_PATH}/examples/http_server_benchmark/Dockerfile"

# Proxy configuration (disabled by default)
USE_PROXY=false
USE_HOST_NETWORK=false
PROXY_HTTP=""
PROXY_HTTPS=""
PROXY_NO="localhost,127.0.0.1"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Detect OS and set default proxy address
detect_os_and_set_proxy() {
    local os_type=$(uname -s)
    local default_proxy=""
    
    case "$os_type" in
        Linux*)
            default_proxy="http://172.17.0.1:7890"
            log_info "Detected Linux - using default proxy: $default_proxy"
            ;;
        Darwin*)
            default_proxy="http://host.docker.internal:7890"
            log_info "Detected macOS - using default proxy: $default_proxy"
            ;;
        *)
            log_warn "Unknown OS: $os_type - using Linux defaults"
            default_proxy="http://172.17.0.1:7890"
            ;;
    esac
    
    # Use environment variables if set, otherwise use defaults
    if [ -z "$PROXY_HTTP" ]; then
        PROXY_HTTP="${HTTP_PROXY:-$default_proxy}"
    fi
    
    if [ -z "$PROXY_HTTPS" ]; then
        PROXY_HTTPS="${HTTPS_PROXY:-$default_proxy}"
    fi
    
    if [ -n "$NO_PROXY" ]; then
        PROXY_NO="$NO_PROXY"
    fi
}

# Check if Docker is available
check_docker() {
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed or not in PATH"
        exit 1
    fi

    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running or you don't have permission to use it"
        exit 1
    fi

    log_info "Docker is available and running"
}

# Build the Docker image
build_image() {
    log_info "Building Docker image: ${FULL_IMAGE_NAME} using ${DOCKERFILE}"

    # Navigate to the benchmark directory
    cd "${ROOT_PATH}"

    # Check if Dockerfile exists
    if [ ! -f "${DOCKERFILE}" ]; then
        log_error "Dockerfile ${DOCKERFILE} not found"
        exit 1
    fi

    # Prepare build command arguments
    local build_args=()
    
    # Add network mode if enabled
    if [ "$USE_HOST_NETWORK" = true ]; then
        log_info "Using host network mode for build"
        build_args+=(--network=host)
    fi
    
    # Add proxy arguments if enabled
    if [ "$USE_PROXY" = true ]; then
        log_info "Proxy configuration enabled:"
        log_info "  HTTP_PROXY: $PROXY_HTTP"
        log_info "  HTTPS_PROXY: $PROXY_HTTPS"
        log_info "  NO_PROXY: $PROXY_NO"
        
        build_args+=(--build-arg "HTTP_PROXY=$PROXY_HTTP")
        build_args+=(--build-arg "HTTPS_PROXY=$PROXY_HTTPS")
        build_args+=(--build-arg "NO_PROXY=$PROXY_NO")
        build_args+=(--build-arg "http_proxy=$PROXY_HTTP")
        build_args+=(--build-arg "https_proxy=$PROXY_HTTPS")
        build_args+=(--build-arg "no_proxy=$PROXY_NO")
    fi
    
    build_args+=(-f "${DOCKERFILE}")
    build_args+=(-t "${FULL_IMAGE_NAME}")
    build_args+=(.)

    echo "Running docker build with arguments: ${build_args[*]}"

    # Build the image
    docker build "${build_args[@]}"

    if [ $? -eq 0 ]; then
        log_info "Successfully built Docker image: ${FULL_IMAGE_NAME}"
    else
        log_error "Failed to build Docker image"
        exit 1
    fi
}

# Run quick verification
verify_build() {
    log_info "Verifying the built image..."

    # Check if the image exists
    if docker images --format "table {{.Repository}}:{{.Tag}}" | grep -q "${FULL_IMAGE_NAME}"; then
        log_info "Image verification successful"

        # Show image size
        local image_size=$(docker images --format "{{.Size}}" "${FULL_IMAGE_NAME}")
        log_info "Image size: ${image_size}"
    else
        log_error "Image verification failed - image not found"
        exit 1
    fi
}

# Show usage information
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -t, --tag TAG              Set image tag (default: latest)"
    echo "  -n, --name NAME            Set image name (default: http-benchmark)"
    echo "  -f, --file FILE            Set Dockerfile to use (default: Dockerfile)"
    echo ""
    echo "Proxy Options:"
    echo "  -p, --proxy                Enable proxy configuration (auto-detect OS and use defaults)"
    echo "      --host-network         Use host network mode for build (recommended with proxy)"
    echo "      --http-proxy URL       Set HTTP proxy URL (overrides default)"
    echo "      --https-proxy URL      Set HTTPS proxy URL (overrides default)"
    echo "      --no-proxy HOSTS       Set no proxy hosts (default: localhost,127.0.0.1)"
    echo ""
    echo "  -h, --help                 Show this help message"
    echo ""
    echo "Proxy Defaults:"
    echo "  Linux:  http://172.17.0.1:7890"
    echo "  macOS:  http://host.docker.internal:7890"
    echo "  Also reads from HTTP_PROXY, HTTPS_PROXY, NO_PROXY environment variables"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Build with default settings"
    echo "  $0 -t v1.0                            # Build with custom tag"
    echo "  $0 -p                                 # Build with proxy (auto-detect OS)"
    echo "  $0 -p --host-network                  # Build with proxy and host network"
    echo "  $0 -p --http-proxy http://proxy:8080  # Build with custom proxy"
    echo ""
    echo "Environment Variables (used when -p is enabled):"
    echo "  HTTP_PROXY, HTTPS_PROXY, NO_PROXY"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--tag)
            IMAGE_TAG="$2"
            FULL_IMAGE_NAME="${IMAGE_NAME}:${IMAGE_TAG}"
            shift 2
            ;;
        -n|--name)
            IMAGE_NAME="$2"
            FULL_IMAGE_NAME="${IMAGE_NAME}:${IMAGE_TAG}"
            shift 2
            ;;
        -f|--file)
            DOCKERFILE="$2"
            shift 2
            ;;
        -p|--proxy)
            USE_PROXY=true
            shift
            ;;
        --host-network)
            USE_HOST_NETWORK=true
            shift
            ;;
        --http-proxy)
            PROXY_HTTP="$2"
            shift 2
            ;;
        --https-proxy)
            PROXY_HTTPS="$2"
            shift 2
            ;;
        --no-proxy)
            PROXY_NO="$2"
            shift 2
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Main execution
main() {
    log_info "Starting HTTP Server Benchmark Docker build process..."

    check_docker
    
    # Setup proxy configuration if enabled
    if [ "$USE_PROXY" = true ]; then
        detect_os_and_set_proxy
    fi
    
    build_image
    verify_build

    log_info "Build process completed successfully!"
    log_info "You can now run the benchmark with:"
    log_info "  docker run --rm -it ${FULL_IMAGE_NAME}"
    log_info "Or run individual language benchmarks:"
    log_info "  docker run --rm -it ${FULL_IMAGE_NAME} sh -c 'bash /app/examples/http_server_benchmark/bench.sh --moonbit-only'"
}

# Run main function
main