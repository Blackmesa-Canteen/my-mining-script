#!/bin/bash
# Enhanced P2Pool Mini + XMRig Mining Script MacOS
# Make sure to set your wallet address below!

# Configuration
WALLET_ADDRESS="ABC"  # Replace with your actual wallet address
P2POOL_HOST="127.0.0.1"
P2POOL_STRATUM_PORT="3333"
XMRIG_API_PORT="44444"
XMRIG_ACCESS_TOKEN="mining_stats_token_$(date +%s)"
XMRIG_DIFFICULTY=""  # Optional: set custom difficulty like "x+10000"

# CPU Configuration Options
# Option 1: Number of threads to use (0 = auto-detect all cores)
CPU_THREADS="4"

# Option 2: Specific CPU cores to use (uncomment and modify as needed)
# Examples:
# CPU_CORES="[0,1,2,3]"                    # Use cores 0, 1, 2, 3
# CPU_CORES="[0,2,4,6]"                    # Use even cores only
# CPU_CORES="[1,3,5,7]"                    # Use odd cores only
# CPU_CORES="null"                         # Use all available cores (default)
CPU_CORES="null"

# Option 3: CPU affinity mask (alternative to specifying individual cores)
# CPU_AFFINITY="0x55"                      # Use cores 0,2,4,6 (binary: 01010101)
# CPU_AFFINITY="0xAA"                      # Use cores 1,3,5,7 (binary: 10101010)
CPU_AFFINITY=""

# Option 4: Leave some cores free for system (recommended for desktop use)
# Set to number of cores to reserve for system (e.g., 2 for dual-core reservation)
RESERVE_CORES="0"

# Status monitoring configuration
STATS_INTERVAL="30"  # Status check interval in seconds
LOG_FILE="mining_stats.log"
STATUS_API_ENABLED="true"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${BLUE}[INFO ${timestamp}]${NC} $1" | tee -a "$LOG_FILE"
}

print_success() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${GREEN}[SUCCESS ${timestamp}]${NC} $1" | tee -a "$LOG_FILE"
}

print_warning() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${YELLOW}[WARNING ${timestamp}]${NC} $1" | tee -a "$LOG_FILE"
}

print_error() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${RED}[ERROR ${timestamp}]${NC} $1" | tee -a "$LOG_FILE"
}

print_mining_stats() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${CYAN}[MINING ${timestamp}]${NC} $1" | tee -a "$LOG_FILE"
}

# Function to detect CPU cores
detect_cpu_info() {
    TOTAL_CORES=$(sysctl -n hw.ncpu)
    PHYSICAL_CORES=$(sysctl -n hw.physicalcpu)
    SOCKETS=$(sysctl -n hw.packages)
    
    if [ -z "$PHYSICAL_CORES" ] || [ -z "$SOCKETS" ]; then
        PHYSICAL_CORES=$TOTAL_CORES
        SOCKETS=1
    fi
    
    ACTUAL_PHYSICAL_CORES=$((PHYSICAL_CORES * SOCKETS))
    
    print_status "CPU Information:"
    print_status "  Total threads: $TOTAL_CORES"
    print_status "  Physical cores: $ACTUAL_PHYSICAL_CORES"
    print_status "  Sockets: $SOCKETS"
}

# Function to calculate optimal CPU configuration
calculate_cpu_config() {
    detect_cpu_info
    
    if [ "$RESERVE_CORES" -gt 0 ]; then
        RECOMMENDED_THREADS=$((TOTAL_CORES - RESERVE_CORES))
        if [ "$RECOMMENDED_THREADS" -lt 1 ]; then
            RECOMMENDED_THREADS=1
        fi
        print_status "Reserving $RESERVE_CORES cores for system, using $RECOMMENDED_THREADS threads for mining"
        CPU_THREADS=$RECOMMENDED_THREADS
    fi
}

# Function to build XMRig command with CPU configuration and API
build_xmrig_command() {
    local cmd="./xmrig -o $P2POOL_HOST:$P2POOL_STRATUM_PORT"
    
    # Enable HTTP API for monitoring
    if [ "$STATUS_API_ENABLED" = "true" ]; then
        cmd="$cmd --http-enabled --http-host=127.0.0.1 --http-port=$XMRIG_API_PORT --http-access-token=$XMRIG_ACCESS_TOKEN --http-no-restricted"
    fi
    
    # Add difficulty if specified
    if [ ! -z "$XMRIG_DIFFICULTY" ]; then
        cmd="$cmd -u $XMRIG_DIFFICULTY"
    fi
    
    # Add CPU threads configuration
    if [ "$CPU_THREADS" != "0" ] && [ ! -z "$CPU_THREADS" ]; then
        cmd="$cmd --threads=$CPU_THREADS"
    fi
    
    # Add CPU cores configuration
    if [ "$CPU_CORES" != "null" ] && [ ! -z "$CPU_CORES" ]; then
        cmd="$cmd --cpu-affinity=$CPU_CORES"
    fi
    
    # Add CPU affinity mask
    if [ ! -z "$CPU_AFFINITY" ]; then
        cmd="$cmd --cpu-affinity=$CPU_AFFINITY"
    fi
    
    # Additional CPU optimizations
    cmd="$cmd --cpu-priority=2"  # Set higher CPU priority (0-5, where 5 is highest)
    cmd="$cmd --donate-level=1"  # Set donation level (1% default)
    
    echo "$cmd"
}

# Function to show comprehensive mining status
show_mining_status() {
    print_status "=== MINING STATUS REPORT ==="
    
    # Check if processes are still running
    if kill -0 $P2POOL_PID 2>/dev/null; then
        print_success "P2Pool Mini is running (PID: $P2POOL_PID)"
    else
        print_error "P2Pool Mini has stopped!"
        return 1
    fi
    
    if kill -0 $XMRIG_PID 2>/dev/null; then
        print_success "XMRig is running (PID: $XMRIG_PID)"
    else
        print_error "XMRig has stopped!"
        return 1
    fi
    
    # Show network connection info
    local p2pool_connections=$(netstat -an | grep "LISTEN" | grep ":$P2POOL_STRATUM_PORT\|:37888" | wc -l)
    print_mining_stats "P2Pool Mini network connections: $p2pool_connections"
    
    print_status "=== END STATUS REPORT ==="
    return 0
}

# Function to check P2Pool Mini sync status
check_p2pool_sync() {
    print_status "Checking P2Pool Mini synchronization status..."
    local sync_check_timeout=60  # 1 minutes
    local sync_check_interval=10
    local elapsed=0
    
    while [ $elapsed -lt $sync_check_timeout ]; do
        if kill -0 $P2POOL_PID 2>/dev/null; then
            # Check if P2Pool is accepting connections (basic sync check)
            if nc -z 127.0.0.1 $P2POOL_STRATUM_PORT 2>/dev/null; then
                print_success "P2Pool Mini appears to be synchronized and accepting connections"
                return 0
            fi
        else
            print_error "P2Pool Mini process has died during sync check"
            return 1
        fi
        
        print_status "P2Pool Mini still synchronizing... ($elapsed/$sync_check_timeout seconds)"
        sleep $sync_check_interval
        elapsed=$((elapsed + sync_check_interval))
    done
    
    print_warning "P2Pool Mini sync check timeout reached, proceeding anyway"
    return 0
}

# Function to cleanup processes on exit
cleanup() {
    print_warning "Shutting down mining processes..."
    
    if [ ! -z "$STATS_MONITOR_PID" ]; then
        kill $STATS_MONITOR_PID 2>/dev/null
        print_status "Stats monitor stopped"
    fi
    
    if [ ! -z "$XMRIG_PID" ]; then
        kill $XMRIG_PID 2>/dev/null
        print_status "XMRig stopped (PID: $XMRIG_PID)"
    fi
    
    if [ ! -z "$P2POOL_PID" ]; then
        kill $P2POOL_PID 2>/dev/null
        print_status "P2Pool Mini stopped (PID: $P2POOL_PID)"
    fi
    
    print_success "Mining processes shutdown complete"
    exit 0
}

# Set up signal handlers
trap cleanup SIGINT SIGTERM

# Validation
if [ "$WALLET_ADDRESS" = "YOUR_WALLET_ADDRESS_HERE" ]; then
    print_error "Please set your wallet address in the script!"
    print_error "Edit the WALLET_ADDRESS variable at the top of this script."
    exit 1
fi

if [ ! -f "./p2pool" ]; then
    print_error "p2pool binary not found in current directory!"
    exit 1
fi

if [ ! -f "./xmrig" ]; then
    print_error "xmrig binary not found in current directory!"
    exit 1
fi

# Make binaries executable
chmod +x ./p2pool ./xmrig

# Initialize log file
echo "=== Mining Session Started: $(date) ===" > "$LOG_FILE"

print_success "Starting Enhanced P2Pool Mini + XMRig Mining Setup"
print_status "Wallet Address: $WALLET_ADDRESS"
print_status "P2Pool Mini Host: $P2POOL_HOST"
print_status "Statistics Logging: $LOG_FILE"

# Calculate optimal CPU configuration
calculate_cpu_config

# Start P2Pool Mini with enhanced options
print_status "Starting P2Pool Mini..."
print_status "Using P2Pool Mini sidechain (lower difficulty, more frequent payouts)"

# P2Pool Mini command with comprehensive options
P2POOL_CMD="./p2pool --mini --host $P2POOL_HOST --wallet $WALLET_ADDRESS --loglevel 2"

print_status "P2Pool Mini command: $P2POOL_CMD"
eval "$P2POOL_CMD &"
P2POOL_PID=$!

print_success "P2Pool Mini started (PID: $P2POOL_PID)"
print_status "P2Pool Mini is using the mini sidechain for faster payouts"

# Enhanced sync check
check_p2pool_sync

# Build XMRig command with CPU configuration and API
XMRIG_CMD=$(build_xmrig_command)

# Start XMRig
print_status "Starting XMRig with enhanced monitoring..."
print_status "XMRig command: $XMRIG_CMD"
eval "$XMRIG_CMD &"
XMRIG_PID=$!

print_success "XMRig started (PID: $XMRIG_PID)"
print_success "XMRig HTTP API available at http://127.0.0.1:$XMRIG_API_PORT (token: $XMRIG_ACCESS_TOKEN)"

# Wait for XMRig to initialize
sleep 10

print_success "Enhanced P2Pool Mini mining setup complete!"
print_status "=== Process Information ==="
print_status "P2Pool Mini PID: $P2POOL_PID"
print_status "XMRig PID: $XMRIG_PID"
print_status "Stats interval: ${STATS_INTERVAL}s"
print_warning "Press Ctrl+C to stop all processes"

# Show initial status
show_mining_status

# Start background stats monitoring if enabled
if [ "$STATUS_API_ENABLED" = "true" ]; then
    (
        while true; do
            sleep "$STATS_INTERVAL"
            if kill -0 $$ 2>/dev/null; then  # Check if parent script is still running
                show_mining_status
            else
                exit 0
            fi
        done
    ) &
    STATS_MONITOR_PID=$!
    print_status "Background stats monitor started (PID: $STATS_MONITOR_PID)"
fi

# Main monitoring loop
while true; do
    # Check if P2Pool Mini is still running
    if ! kill -0 $P2POOL_PID 2>/dev/null; then
        print_error "P2Pool Mini has stopped unexpectedly!"
        if [ ! -z "$XMRIG_PID" ]; then
            kill $XMRIG_PID 2>/dev/null
        fi
        exit 1
    fi
        
    # Check if XMRig is still running
    if ! kill -0 $XMRIG_PID 2>/dev/null; then
        print_error "XMRig has stopped unexpectedly!"
        exit 1
    fi
    
    # Sleep for a reasonable interval before next check
    sleep 60
done
