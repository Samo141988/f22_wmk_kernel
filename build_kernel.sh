#!/bin/bash
[ -z $DEFAULT_KSU_REPO ] && DEFAULT_KSU_REPO="https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/next/kernel/setup.sh"
[ -z $DEFAULT_KSU_BRANCH ] && DEFAULT_KSU_BRANCH="next"
[ -z $IS_CI ] && IS_CI=false
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



# Function to prompt for toolchain path


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
CC_CMD="$CLANG_DIR/bin/clang"
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
print_section "KERNEL SU Adding"
curl -LSs $DEFAULT_KSU_REPO | bash -s next
# Store build command for reference
BUILD_CMD="make -j16 ARCH=arm64 SUBARCH=arm64 O=out \
CC=\"$CLANG_DIR/bin/clang\" \
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
IS_CI=false \
KERNELSU=true \
CONFIG_SECTION_MISMATCH_WARN_ONLY=y \
KBUILD_BUILD_USER=\"$(git rev-parse --short HEAD | cut -c1-7)\" \
KBUILD_BUILD_HOST=\"$(git symbolic-ref --short HEAD)\""


if eval $BUILD_CMD; then
    print_success "Kernel compilation completed successfully"
else
    print_error "Kernel compilation failed"
    exit 1
fi

# Copy the built kernel image
# تصحيح جزء نسخ الصورة وإنشاء ZIP
print_section "POST-BUILD OPERATIONS"
print_status "Copying kernel image..."

IMAGE="$PREFIX/out/arch/arm64/boot/Image"
AK3_DIR="$PREFIX/AnyKernel"

# التحقق من وجود صورة Kernel
if [ ! -f "$IMAGE" ]; then
    print_error "Kernel image not found at $IMAGE"
    exit 1
fi

# التحقق من وجود مجلد AnyKernel3
if [ ! -d "$AK3_DIR" ]; then
    print_error "AnyKernel directory not found at $AK3_DIR"
    exit 1
fi

# نسخ الصورة
cp "$IMAGE" "$AK3_DIR/"

# إنشاء ملف ZIP في مجلد أعلى (لتجنب تضمينه في نفسه)
cd "$AK3_DIR" || exit 1
ZIP_FILE="../f22_wmk_kernel_$(date +%Y%m%d_%H%M).zip"
zip -r9 "$ZIP_FILE" *

print_status "Kernel zip created at: $ZIP_FILE"
