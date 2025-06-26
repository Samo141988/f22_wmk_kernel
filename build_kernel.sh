#!/bin/bash

# Parse command line arguments
QUIET_MODE=false
while [[ $# -gt 0 ]]; do
    case $1 in
        -q|--quiet)
            QUIET_MODE=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [-q|--quiet]"
            echo "  -q, --quiet    Only show errors during make operations"
            exit 1
            ;;
    esac
done
# Create logs directory
LOG_DIR="${PWD}/logs"
mkdir -p "$LOG_DIR"

# Timestamp for the log filename
BUILD_LOG="${LOG_DIR}/build_$(date +%Y%m%d_%H%M%S).log"

# Color definitions for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to print colored status messages
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_section() {
    echo -e "\n${PURPLE}=== $1 ===${NC}"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to verify toolchain functionality
verify_toolchain() {
    local toolchain_path="$1"

    # Check if path is provided and not empty
    if [ -z "$toolchain_path" ]; then
        return 1
    fi

    local bin_path="$toolchain_path/bin"

    # Check if toolchain directory exists
    if [ ! -d "$toolchain_path" ]; then
        return 1
    fi

    # Check if bin directory exists
    if [ ! -d "$bin_path" ]; then
        return 1
    fi

    # Temporarily add to PATH for testing
    local old_path="$PATH"
    export PATH="$bin_path:$PATH"

    # Test essential tools
    local required_tools=("clang" "llvm-ar" "llvm-nm" "ld.lld" "llvm-objcopy" "llvm-objdump" "llvm-strip")
    local missing_tools=()

    for tool in "${required_tools[@]}"; do
        if ! command_exists "$tool"; then
            missing_tools+=("$tool")
        fi
    done

    # Restore PATH
    export PATH="$old_path"

    if [ ${#missing_tools[@]} -gt 0 ]; then
        return 1
    fi

    # Test clang version
    if [ -x "$bin_path/clang" ]; then
        local clang_version=$("$bin_path/clang" --version 2>/dev/null | head -n1)
        if [ -n "$clang_version" ]; then
            print_success "Clang version: $clang_version"
        else
            return 1
        fi
    else
        return 1
    fi

    return 0
}

# Function to prompt for toolchain path
prompt_for_toolchain() {
    echo

    local user_path
    local attempts=0
    local max_attempts=3

    while [ $attempts -lt $max_attempts ]; do
        read -p "Enter toolchain path, e.g /clang/ NOT /clang/bin (or 'quit' to exit): " user_path

        if [ "$user_path" = "quit" ] || [ "$user_path" = "q" ]; then
            print_status "Build cancelled by user"
            exit 0
        fi

        if [ -z "$user_path" ]; then
            print_error "Please enter a valid path"
            ((attempts++))
            continue
        fi

        # Expand tilde if present
        user_path="${user_path/#\~/$HOME}"

        # Check if directory exists
        if [ ! -d "$user_path" ]; then
            print_error "Directory does not exist: $user_path"
            ((attempts++))
            continue
        fi

        
    done

    print_error "Maximum attempts reached. Unable to find a valid toolchain."
    exit 1
}

# Function to display build summary
show_build_info() {
    local start_time=$1
    local end_time=$2
    local duration=$((end_time - start_time))
    local minutes=$((duration / 60))
    local seconds=$((duration % 60))

    print_section "BUILD SUMMARY"
    echo -e "  ${CYAN}Build Time:${NC} ${minutes}m ${seconds}s"
    echo -e "  ${CYAN}Git Commit:${NC} $(git rev-parse --short HEAD 2>/dev/null || echo 'N/A')"
    echo -e "  ${CYAN}Git Branch:${NC} $(git symbolic-ref --short HEAD 2>/dev/null || echo 'N/A')"
    echo -e "  ${CYAN}Kernel Image:${NC} $(ls -lh out/arch/arm64/boot/Image 2>/dev/null | awk '{print $5}' || echo 'Not found')"
    echo -e "  ${CYAN}Log Saved To:${NC} $BUILD_LOG"
}



# Start timing
BUILD_START_TIME=$(date +%s)

print_section "ANDROID KERNEL BUILD SCRIPT"
print_status "Starting build process for Android Kernel $(make kernelversion 2>/dev/null || echo 'Unknown')"

# Define paths and toolchain
PREFIX="$(pwd)"
print_status "Working directory: $PREFIX"

# Check if custom LLVM toolchain exists, otherwise use default
print_section "TOOLCHAIN DETECTION"

# Check predefined locations
CLANG_DIR="${PREFIX}/toolchain/clang-wmk"
print_success "Found default toolchain: $CLANG_DIR"

# Set up environment
print_section "ENVIRONMENT SETUP"
export PATH="$CLANG_DIR/bin:$PATH"
export ARCH=arm64

# Display clang version
CLANG_VERSION=$("$CLANG_DIR/bin/clang" --version | head -n1)
print_status "Using: $CLANG_VERSION"

# Build configuration
print_section "BUILD CONFIGURATION"
export KCFLAGS=-w
export CONFIG_SECTION_MISMATCH_WARN_ONLY=y

print_status "Architecture: arm64"
print_status "Compiler: $CC_CMD"
print_status "Suppressing warnings: enabled"
print_status "Section mismatch warnings only: enabled"

# Configure kernel
print_section "KERNEL CONFIGURATION"
print_status "Configuring kernel with f22_defconfig..."

if make -C "$PREFIX" O="$PREFIX/out" ARCH=arm64 f22_defconfig; then
    print_success "Kernel configuration completed"
else
    print_error "Kernel configuration failed"
    exit 1
fi

# Build kernel
print_section "KERNEL COMPILATION"
print_status "Starting compilation with 16 parallel jobs..."
print_status "This may take several minutes depending on your hardware..."

# Store build command for reference
BUILD_CMD="make -j16 ARCH=arm64 SUBARCH=arm64 O=out \
CC=\"$CC_CMD\" \
AR=\"llvm-ar\" \
NM=\"llvm-nm\" \
LD=\"ld.lld\" \
OBJCOPY=\"llvm-objcopy\" \
OBJDUMP=\"llvm-objdump\" \
STRIP=\"llvm-strip\" \
CLANG_TRIPLE=\"aarch64-linux-gnu-\" \
CROSS_COMPILE=\"aarch64-linux-gnu-\" \
CROSS_COMPILE_ARM32=\"arm-linux-gnueabi-\" \
CROSS_COMPILE_COMPAT=\"arm-linux-gnueabi-\" \
LLVM=1 \
LLVM_IAS=1 \
INSTALL_MOD_STRIP=1 \
KCFLAGS=-w \
CONFIG_SECTION_MISMATCH_WARN_ONLY=y \
KBUILD_BUILD_USER=\"samo" \
KBUILD_BUILD_HOST=\"samo141988 \""

if [ "$QUIET_MODE" = true ]; then
    BUILD_CMD="$BUILD_CMD > \"$BUILD_LOG\" 2>&1"
else
    BUILD_CMD="$BUILD_CMD 2>&1 | tee \"$BUILD_LOG\""
fi

if eval $BUILD_CMD; then
    print_success "Kernel compilation completed successfully"
else
    print_error "Kernel compilation failed"
    exit 1
fi

# Copy the built kernel image
print_section "POST-BUILD OPERATIONS"
print_status "Copying kernel image..."


# Build completion
BUILD_END_TIME=$(date +%s)
show_build_info $BUILD_START_TIME $BUILD_END_TIME
IMAGE="$PREFIX/out/arch/arm64/boot/Image"
AK3="$PREFIX/AnyKernel3"
cp $IMAGE $AK3
cd $AK3
zip -r9 ../$BUILD_END_TIME.zip *

print_section "BUILD COMPLETED"
print_success "Android kernel build finished successfully!"
