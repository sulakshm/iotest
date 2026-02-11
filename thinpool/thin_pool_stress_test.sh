#!/bin/bash
#
# LVM Thin Pool Stress Test Script
# 
# Purpose: Stress test LVM thin pools with parallel I/O, volume deletion, and recreation
#
# Usage: ./thin_pool_stress_test.sh [options]
#

set -euo pipefail

# Script version
VERSION="1.0.0"

# Default configuration
DRIVES=""
PARALLEL_DELETES=2
MAX_HOURS=0
MAX_ITERATIONS=0
METADATA_SIZE="15G"
POOL_CAPACITY_PERCENT=80
NUM_VOLUMES=16
IO_VOLUMES=8
CYCLE_VOLUMES=8
VOLUME_MODE="raw"  # raw or formatted
LOG_DIR="./thin_pool_stress_logs"
VG_NAME="stress_vg"
POOL_NAME="stress_pool"
THIN_POOL="${VG_NAME}/${POOL_NAME}"
SNAPSHOT_IO_DURATION=30  # Duration of I/O on volume after snapshot (seconds)

# Race condition stress mode settings
RACE_MODE="enabled"           # enabled or disabled - run I/O concurrent with discard
CONCURRENT_DISCARD_IO=1       # Run I/O while discard is in progress
AGGRESSIVE_DISCARD=1          # Issue multiple discards rapidly
METADATA_STRESS=0             # Use minimal metadata to stress tmeta
FSTRIM_MODE=0                 # Use fstrim instead of blkdiscard for mounted fs
DISCARD_DURING_SNAPSHOT=1     # Issue discards while snapshot exists

# Runtime statistics
START_TIME=0
ITERATION_COUNT=0
TOTAL_CREATES=0
TOTAL_DELETES=0
TOTAL_DISCARDS=0
TOTAL_METADATA_SNAPS=0

# Batch rotation tracking (alternates between 0 and 1)
# Batch 0 = volumes 1 to BATCH_SIZE
# Batch 1 = volumes (BATCH_SIZE+1) to NUM_VOLUMES
CURRENT_BATCH=0
BATCH_SIZE=8

# LVM operation serialization lock file
LVM_LOCK_FILE="/tmp/thin_pool_stress_lvm.lock"

#######################################
# LVM operation serialization helpers
# LVM metadata operations must be serialized - they cannot run in parallel
# These use a directory-based lock (mkdir is atomic)
#######################################
lvm_lock() {
    local max_wait=60
    local wait_time=0
    while ! mkdir "$LVM_LOCK_FILE" 2>/dev/null; do
        sleep 0.1
        wait_time=$((wait_time + 1))
        if [[ $wait_time -ge $((max_wait * 10)) ]]; then
            log_warning "LVM lock wait exceeded ${max_wait}s, forcing lock acquisition"
            rmdir "$LVM_LOCK_FILE" 2>/dev/null || true
            mkdir "$LVM_LOCK_FILE" 2>/dev/null || true
            break
        fi
    done
}

lvm_unlock() {
    rmdir "$LVM_LOCK_FILE" 2>/dev/null || true
}

# Cleanup LVM lock on script exit
cleanup_lvm_lock() {
    rmdir "$LVM_LOCK_FILE" 2>/dev/null || true
}

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

#######################################
# Print usage information
#######################################
usage() {
    cat << EOF
LVM Thin Pool Stress Test - Version ${VERSION}

Usage: $0 [OPTIONS]

Purpose: Stress test LVM thin pools to reproduce refcount corruption issues
         ("space map common: unable to decrement block")

Required Options:
  -d, --drives DRIVES          Comma-separated list of drives (e.g., /dev/sdb,/dev/sdc)

Optional Options:
  -p, --parallel-deletes NUM   Number of parallel volume deletes (default: 2, range: 1-8)
  -h, --max-hours HOURS        Maximum runtime in hours (0 = indefinite, default: 0)
  -i, --max-iterations NUM     Maximum iterations (0 = indefinite, default: 0)
  -m, --metadata-size SIZE     Metadata volume size (default: 15G)
  -c, --capacity-percent PCT   Pool capacity to use for volumes (default: 80)
  -n, --num-volumes NUM        Total number of thin volumes (default: 16)
  -v, --volume-mode MODE       Volume mode: raw or formatted (default: raw)
  -l, --log-dir DIR            Log directory (default: ./thin_pool_stress_logs)
      --vg-name NAME           Volume group name (default: stress_vg)
      --pool-name NAME         Thin pool name (default: stress_pool)
      --snapshot-io-duration S Duration of I/O after snapshot in seconds (default: 30)

Race Condition Stress Options (for reproducing refcount issues):
      --race-mode MODE         Race condition mode: enabled/disabled (default: enabled)
      --no-race-mode           Disable race condition stress (sequential operations)
      --metadata-stress        Use minimal metadata to stress tmeta exhaustion
      --fstrim-mode            Use fstrim instead of blkdiscard for mounted fs
      --help                   Show this help message

Examples:
  # Standard stress test with race conditions enabled
  $0 -d /dev/sdb,/dev/sdc -p 4

  # Maximum stress for reproducing refcount issues
  $0 -d /dev/sdb,/dev/sdc -p 8 --metadata-stress -c 95

  # Run for 24 hours with formatted volumes and fstrim
  $0 -d /dev/sdb,/dev/sdc,/dev/sdd -h 24 -v formatted --fstrim-mode

  # Safe mode (no race conditions) for baseline testing
  $0 -d /dev/sdb,/dev/sdc -p 4 --no-race-mode

EOF
    exit 0
}

#######################################
# Print colored message
#######################################
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

#######################################
# Parse command line arguments
#######################################
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--drives)
                DRIVES="$2"
                shift 2
                ;;
            -p|--parallel-deletes)
                PARALLEL_DELETES="$2"
                shift 2
                ;;
            -h|--max-hours)
                MAX_HOURS="$2"
                shift 2
                ;;
            -i|--max-iterations)
                MAX_ITERATIONS="$2"
                shift 2
                ;;
            -m|--metadata-size)
                METADATA_SIZE="$2"
                shift 2
                ;;
            -c|--capacity-percent)
                POOL_CAPACITY_PERCENT="$2"
                shift 2
                ;;
            -n|--num-volumes)
                NUM_VOLUMES="$2"
                shift 2
                ;;
            -v|--volume-mode)
                VOLUME_MODE="$2"
                shift 2
                ;;
            -l|--log-dir)
                LOG_DIR="$2"
                shift 2
                ;;
            --vg-name)
                VG_NAME="$2"
                THIN_POOL="${VG_NAME}/${POOL_NAME}"
                shift 2
                ;;
            --pool-name)
                POOL_NAME="$2"
                THIN_POOL="${VG_NAME}/${POOL_NAME}"
                shift 2
                ;;
            --snapshot-io-duration)
                SNAPSHOT_IO_DURATION="$2"
                shift 2
                ;;
            --race-mode)
                RACE_MODE="$2"
                shift 2
                ;;
            --no-race-mode)
                RACE_MODE="disabled"
                CONCURRENT_DISCARD_IO=0
                AGGRESSIVE_DISCARD=0
                DISCARD_DURING_SNAPSHOT=0
                shift
                ;;
            --metadata-stress)
                METADATA_STRESS=1
                METADATA_SIZE="512M"  # Minimal metadata to stress tmeta
                shift
                ;;
            --fstrim-mode)
                FSTRIM_MODE=1
                shift
                ;;
            --help)
                usage
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                ;;
        esac
    done
}

#######################################
# Validate input parameters
#######################################
validate_inputs() {
    log_info "Validating input parameters..."

    # Check required parameters
    if [[ -z "$DRIVES" ]]; then
        log_error "Drives parameter is required (-d/--drives)"
        usage
    fi

    # Validate parallel deletes range
    if [[ $PARALLEL_DELETES -lt 1 || $PARALLEL_DELETES -gt 8 ]]; then
        log_error "Parallel deletes must be between 1 and 8"
        exit 1
    fi

    # Validate volume mode
    if [[ "$VOLUME_MODE" != "raw" && "$VOLUME_MODE" != "formatted" ]]; then
        log_error "Volume mode must be 'raw' or 'formatted'"
        exit 1
    fi

    # Validate drives exist
    IFS=',' read -ra DRIVE_ARRAY <<< "$DRIVES"
    for drive in "${DRIVE_ARRAY[@]}"; do
        if [[ ! -b "$drive" ]]; then
            log_error "Drive $drive does not exist or is not a block device"
            exit 1
        fi
    done

    # Check if drives are in use
    for drive in "${DRIVE_ARRAY[@]}"; do
        if pvs "$drive" &>/dev/null; then
            log_warn "Drive $drive is already a physical volume"
        fi
        if mount | grep -q "$drive"; then
            log_error "Drive $drive is currently mounted"
            exit 1
        fi
    done

    # Validate number of volumes
    if [[ $NUM_VOLUMES -lt 2 ]]; then
        log_error "Number of volumes must be at least 2"
        exit 1
    fi

    # Calculate IO and cycle volumes
    IO_VOLUMES=$((NUM_VOLUMES / 2))
    CYCLE_VOLUMES=$((NUM_VOLUMES - IO_VOLUMES))

    if [[ $PARALLEL_DELETES -gt $CYCLE_VOLUMES ]]; then
        log_error "Parallel deletes ($PARALLEL_DELETES) cannot exceed cycle volumes ($CYCLE_VOLUMES)"
        exit 1
    fi

    log_success "Input validation passed"
}

#######################################
# Setup log directory
#######################################
setup_logging() {
    mkdir -p "$LOG_DIR"
    START_TIME=$(date +%s)
    local timestamp=$(date +%Y%m%d_%H%M%S)

    # Create log files
    MAIN_LOG="${LOG_DIR}/stress_test_${timestamp}.log"
    STATS_LOG="${LOG_DIR}/stats_${timestamp}.log"
    IOSTAT_LOG="${LOG_DIR}/iostat_${timestamp}.log"

    log_info "Logging to: $LOG_DIR"

    # Write header to stats log
    {
        echo "# LVM Thin Pool Stress Test Statistics"
        echo "# Started: $(date)"
        echo "# Drives: $DRIVES"
        echo "# Parallel Deletes: $PARALLEL_DELETES"
        echo "# Volume Mode: $VOLUME_MODE"
        echo "#"
        echo "# Iteration,Runtime(s),Creates,Deletes,Discards,Metadata_Snaps,Pool_Data_Used(%),Pool_Meta_Used(%)"
    } > "$STATS_LOG"

    # Write header to iostat log
    {
        echo "# I/O Statistics Log"
        echo "# Format: Iteration,Phase,Device,Read_Ops,Read_Bytes,Write_Ops,Write_Bytes,Discard_Ops,Discard_Bytes,Flush_Ops"
        echo "#"
    } > "$IOSTAT_LOG"
}

#######################################
# Cleanup on exit
#######################################
cleanup() {
    log_warn "Cleaning up..."

    # Remove LVM serialization lock
    cleanup_lvm_lock

    # Stop all I/O workloads using our PID tracking
    if [[ -f "${LOG_DIR}/io_pids.txt" ]]; then
        while read -r pid vol; do
            kill "$pid" 2>/dev/null || true
        done < "${LOG_DIR}/io_pids.txt"
        rm -f "${LOG_DIR}/io_pids.txt"
    fi

    # Stop all background I/O jobs (fallback)
    jobs -p | xargs -r kill 2>/dev/null || true

    # Unmount formatted volumes
    if [[ "$VOLUME_MODE" == "formatted" ]]; then
        for i in $(seq 1 $NUM_VOLUMES); do
            local mount_point="/mnt/thin_vol_${i}"
            if mountpoint -q "$mount_point" 2>/dev/null; then
                umount "$mount_point" 2>/dev/null || true
            fi
        done
    fi

    # Remove thin volumes
    log_info "Removing thin volumes..."
    for i in $(seq 1 $NUM_VOLUMES); do
        lvremove -f "${VG_NAME}/thin_vol_${i}" 2>/dev/null || true
    done

    # Remove thin pool
    log_info "Removing thin pool..."
    lvremove -f "${THIN_POOL}" 2>/dev/null || true

    # Remove volume group
    log_info "Removing volume group..."
    vgremove -f "$VG_NAME" 2>/dev/null || true

    # Remove physical volumes
    IFS=',' read -ra DRIVE_ARRAY <<< "$DRIVES"
    for drive in "${DRIVE_ARRAY[@]}"; do
        pvremove -f "$drive" 2>/dev/null || true
    done

    log_success "Cleanup complete"
}

trap cleanup EXIT INT TERM

#######################################
# Get device I/O statistics from /sys/block
#######################################
get_device_iostats() {
    local device=$(readlink -f $1)
    local dev_name=$(basename "$device")

    # Handle device mapper devices
    if [[ "$dev_name" == dm-* ]]; then
        local stat_file="/sys/block/${dev_name}/stat"
    else
        local stat_file="/sys/block/${dev_name}/stat"
    fi

    if [[ ! -f "$stat_file" ]]; then
        echo "0 0 0 0 0 0 0 0 0 0 0"
        return
    fi

    cat "$stat_file"
}

#######################################
# Parse iostat fields
#######################################
parse_iostat() {
    local stats=$1
    read -r read_ios read_merges read_sectors read_ticks \
            write_ios write_merges write_sectors write_ticks \
            in_flight io_ticks time_in_queue \
            discard_ios discard_merges discard_sectors discard_ticks \
            flush_ios flush_ticks <<< "$stats"

    # Convert sectors to bytes (512 bytes per sector)
    local read_bytes=$((read_sectors * 512))
    local write_bytes=$((write_sectors * 512))
    local discard_bytes=$((discard_sectors * 512))

    echo "$read_ios $read_bytes $write_ios $write_bytes ${discard_ios:-0} ${discard_bytes:-0} ${flush_ios:-0}"
}

#######################################
# Capture I/O statistics for all devices
#######################################
capture_iostats() {
    local phase=$1
    local iteration=$2

    IFS=',' read -ra DRIVE_ARRAY <<< "$DRIVES"
    for drive in "${DRIVE_ARRAY[@]}"; do
        local stats=$(get_device_iostats "$drive")
        local parsed=$(parse_iostat "$stats")
        echo "${iteration},${phase},${drive},${parsed}" >> "$IOSTAT_LOG"
    done

    # Also capture thin pool device stats
    if lvs "${THIN_POOL}" &>/dev/null; then
        local dm_device=$(lvs --noheadings -o lv_dm_path "${THIN_POOL}" | tr -d ' ')
        if [[ -n "$dm_device" ]]; then
            local stats=$(get_device_iostats "$dm_device")
            local parsed=$(parse_iostat "$stats")
            echo "${iteration},${phase},${dm_device},${parsed}" >> "$IOSTAT_LOG"
        fi
    fi
}

#######################################
# Calculate delta between two iostat captures
#######################################
calculate_iostat_delta() {
    local iteration=$1

    # Get before and after stats for this iteration
    local before_stats=$(grep "^${iteration},before," "$IOSTAT_LOG")
    local after_stats=$(grep "^${iteration},after," "$IOSTAT_LOG")

    # Calculate deltas for each device
    while IFS= read -r before_line; do
        local device=$(echo "$before_line" | cut -d',' -f3)
        local after_line=$(echo "$after_stats" | grep ",${device},")

        if [[ -n "$after_line" ]]; then
            # Parse before stats
            IFS=',' read -r _ _ _ b_rio b_rbytes b_wio b_wbytes b_dio b_dbytes b_fio <<< "$before_line"
            # Parse after stats
            IFS=',' read -r _ _ _ a_rio a_rbytes a_wio a_wbytes a_dio a_dbytes a_fio <<< "$after_line"

            # Calculate deltas
            local d_rio=$((a_rio - b_rio))
            local d_rbytes=$((a_rbytes - b_rbytes))
            local d_wio=$((a_wio - b_wio))
            local d_wbytes=$((a_wbytes - b_wbytes))
            local d_dio=$((a_dio - b_dio))
            local d_dbytes=$((a_dbytes - b_dbytes))
            local d_fio=$((a_fio - b_fio))

            echo "${iteration},delta,${device},${d_rio},${d_rbytes},${d_wio},${d_wbytes},${d_dio},${d_dbytes},${d_fio}" >> "$IOSTAT_LOG"
        fi
    done <<< "$before_stats"
}

#######################################
# Calculate aggregate I/O statistics since test start
#######################################
calculate_aggregate_stats() {
    local current_iteration=$1

    # Sum all delta stats across all iterations
    local total_rio=0 total_rbytes=0 total_wio=0 total_wbytes=0
    local total_dio=0 total_dbytes=0 total_fio=0

    while IFS=',' read -r iter phase device rio rbytes wio wbytes dio dbytes fio; do
        if [[ "$phase" == "delta" ]]; then
            total_rio=$((total_rio + rio))
            total_rbytes=$((total_rbytes + rbytes))
            total_wio=$((total_wio + wio))
            total_wbytes=$((total_wbytes + wbytes))
            total_dio=$((total_dio + dio))
            total_dbytes=$((total_dbytes + dbytes))
            total_fio=$((total_fio + fio))
        fi
    done < <(grep ",delta," "$IOSTAT_LOG")

    echo "${current_iteration},aggregate,ALL,${total_rio},${total_rbytes},${total_wio},${total_wbytes},${total_dio},${total_dbytes},${total_fio}" >> "$IOSTAT_LOG"
}

#######################################
# Setup LVM thin pool
#######################################
setup_thin_pool() {
    log_info "Setting up LVM thin pool..."

    IFS=',' read -ra DRIVE_ARRAY <<< "$DRIVES"

    # Create physical volumes
    log_info "Creating physical volumes..."
    for drive in "${DRIVE_ARRAY[@]}"; do
        pvcreate -f "$drive"
    done

    # Create volume group
    log_info "Creating volume group: $VG_NAME"
    vgcreate "$VG_NAME" "${DRIVE_ARRAY[@]}"

    # Get total VG size
    local vg_size=$(vgs --noheadings --units b -o vg_size "$VG_NAME" | tr -d ' B')
    log_info "Volume group size: $((vg_size / 1024 / 1024 / 1024)) GB"

    # Create thin pool with metadata and data LVs
    log_info "Creating thin pool with metadata size: $METADATA_SIZE"

    # Calculate data size (total - metadata)
    lvcreate -L "$METADATA_SIZE" -n "${POOL_NAME}_meta" "$VG_NAME"
    lvcreate -l 90%FREE -n "${POOL_NAME}_data" "$VG_NAME"

    # Convert to thin pool with discard passdown and no zeroing
    lvconvert -y --type thin-pool \
        --poolmetadata "${VG_NAME}/${POOL_NAME}_meta" \
        --discards passdown \
        --zero n \
        "${VG_NAME}/${POOL_NAME}_data"

    # Rename to final pool name
    lvrename "${VG_NAME}/${POOL_NAME}_data" "${VG_NAME}/${POOL_NAME}"

    log_success "Thin pool created: $THIN_POOL"

    # Display pool information
    lvs -o +discards,zero "${THIN_POOL}"
}

#######################################
# Create thin volumes
#######################################
create_thin_volumes() {
    log_info "Creating $NUM_VOLUMES thin volumes..."

    # Get pool data size
    local pool_size=$(lvs --noheadings --units b -o lv_size "${THIN_POOL}" | tr -d ' B')

    # Calculate volume size (pool_size * capacity_percent / num_volumes)
    local total_provisioned=$((pool_size * POOL_CAPACITY_PERCENT / 100))
    local volume_size=$((total_provisioned / NUM_VOLUMES))
    local volume_size_mb=$((volume_size / 1024 / 1024))

    log_info "Each volume size: ${volume_size_mb} MB (${POOL_CAPACITY_PERCENT}% of pool / $NUM_VOLUMES volumes)"

    for i in $(seq 1 $NUM_VOLUMES); do
        lvcreate -V "${volume_size_mb}M" -T "${THIN_POOL}" -n "thin_vol_${i}"
        TOTAL_CREATES=$((TOTAL_CREATES + 1))
    done

    # Format volumes if requested
    if [[ "$VOLUME_MODE" == "formatted" ]]; then
        log_info "Formatting volumes with ext4..."
        for i in $(seq 1 $NUM_VOLUMES); do
            mkfs.ext4 -F "/dev/${VG_NAME}/thin_vol_${i}" >/dev/null 2>&1
            local mount_point="/mnt/thin_vol_${i}"
            mkdir -p "$mount_point"
            mount "/dev/${VG_NAME}/thin_vol_${i}" "$mount_point"
        done
    fi

    log_success "Created $NUM_VOLUMES thin volumes"
}

#######################################
# Start I/O workload on a range of volumes
# Usage: start_io_workload_range <start_vol> <end_vol>
#######################################
start_io_workload_range() {
    local start_vol=$1
    local end_vol=$2

    log_info "Starting I/O workload on volumes ${start_vol}-${end_vol}..."

    for i in $(seq $start_vol $end_vol); do
        local device="/dev/${VG_NAME}/thin_vol_${i}"
        local target="$device"

        if [[ "$VOLUME_MODE" == "formatted" ]]; then
            target="/mnt/thin_vol_${i}/testfile"
        fi

        # Start fio workload in background
        fio --name="io_vol_${i}" \
            --filename="$target" \
            --size=90% \
            --rw=randrw \
            --rwmixread=70 \
            --bs=4k \
            --ioengine=libaio \
            --iodepth=16 \
            --direct=1 \
            --runtime=0 \
            --time_based \
            --group_reporting \
            --output="${LOG_DIR}/fio_vol_${i}_iter_${ITERATION_COUNT}.log" \
            >/dev/null 2>&1 &

        # Store PID with volume number for selective stopping
        echo "$! $i" >> "${LOG_DIR}/io_pids.txt"
    done

    log_success "I/O workload started on volumes ${start_vol}-${end_vol}"
}

#######################################
# Start I/O workload on ALL volumes (1 to NUM_VOLUMES)
#######################################
start_io_workload_all() {
    start_io_workload_range 1 $NUM_VOLUMES
}

#######################################
# Stop I/O workload on a range of volumes
# Usage: stop_io_workload_range <start_vol> <end_vol>
#######################################
stop_io_workload_range() {
    local start_vol=$1
    local end_vol=$2

    log_info "Stopping I/O workload on volumes ${start_vol}-${end_vol}..."

    if [[ -f "${LOG_DIR}/io_pids.txt" ]]; then
        local temp_file="${LOG_DIR}/io_pids_temp.txt"
        > "$temp_file"

        while read -r pid vol; do
            if [[ $vol -ge $start_vol && $vol -le $end_vol ]]; then
                kill "$pid" 2>/dev/null || true
            else
                # Keep PIDs for volumes outside the range
                echo "$pid $vol" >> "$temp_file"
            fi
        done < "${LOG_DIR}/io_pids.txt"

        mv "$temp_file" "${LOG_DIR}/io_pids.txt"
    fi

    # Wait for processes to terminate
    sleep 1

    log_success "I/O workload stopped on volumes ${start_vol}-${end_vol}"
}

#######################################
# Stop ALL I/O workload
#######################################
stop_io_workload_all() {
    log_info "Stopping all I/O workload..."

    if [[ -f "${LOG_DIR}/io_pids.txt" ]]; then
        while read -r pid vol; do
            kill "$pid" 2>/dev/null || true
        done < "${LOG_DIR}/io_pids.txt"
        rm -f "${LOG_DIR}/io_pids.txt"
    fi

    # Wait for processes to terminate
    sleep 2

    log_success "All I/O workload stopped"
}

# Legacy function for compatibility
start_io_workload() {
    start_io_workload_all
}

stop_io_workload() {
    stop_io_workload_all
}

#######################################
# Perform thin pool metadata snapshot operation
# This is what monitoring tools do to inspect pool metadata
# Must be serialized - these operations cannot run in parallel
#######################################
metadata_snapshot_operation() {
    local pool_dm_name="${VG_NAME}-${POOL_NAME}-tpool"
    local tmeta_device="/dev/mapper/${VG_NAME}-${POOL_NAME}_tmeta"

    log_info "Performing metadata snapshot operation..."

    # Reserve metadata snapshot (serialized with LVM lock)
    lvm_lock
    if dmsetup message "/dev/mapper/${pool_dm_name}" 0 reserve_metadata_snap 2>/dev/null; then
        lvm_unlock

        # Read metadata while reserved (this can take time, but doesn't modify LVM state)
        thin_dump -m "$tmeta_device" > /dev/null 2>&1 || true

        # Release metadata snapshot (serialized with LVM lock)
        lvm_lock
        dmsetup message "/dev/mapper/${pool_dm_name}" 0 release_metadata_snap 2>/dev/null || true
        lvm_unlock

        TOTAL_METADATA_SNAPS=$((TOTAL_METADATA_SNAPS + 1))
        log_success "Metadata snapshot operation complete (total: $TOTAL_METADATA_SNAPS)"
    else
        lvm_unlock
        log_warning "Failed to reserve metadata snapshot (pool may be busy)"
    fi
}

#######################################
# Recycle a batch of volumes
# Sequence: snapshot -> race I/O+discard -> thin_meta snap -> thin_dump -> discard -> delete -> recreate
# Usage: recycle_batch <start_vol> <end_vol>
# Race mode: Runs I/O and discard SIMULTANEOUSLY to trigger refcount races
#######################################
recycle_batch() {
    local start_idx=$1
    local end_idx=$2

    log_info "Recycling volumes ${start_idx} to ${end_idx}..."
    log_info "Race mode: ${RACE_MODE}"

    # Process volumes in sub-batches of PARALLEL_DELETES
    for batch_start in $(seq $start_idx $PARALLEL_DELETES $end_idx); do
        local batch_end=$((batch_start + PARALLEL_DELETES - 1))
        if [[ $batch_end -gt $end_idx ]]; then
            batch_end=$end_idx
        fi

        log_info "Processing sub-batch: volumes ${batch_start} to ${batch_end}"

        # Step 1: Take snapshots (LVM operations serialized)
        # Remove any existing snapshot first, then create new snapshot of the volume
        log_info "  Step 1/8: Taking snapshots..."
        local pool_stats=$(get_pool_stats)
        log_info "  Pool usage before snapshot: ${pool_stats}"

        for i in $(seq $batch_start $batch_end); do
            # Remove old snapshot if exists
            lvm_lock
            lvremove -f "${VG_NAME}/thin_vol_${i}_snap" 2>/dev/null || true
            lvm_unlock
            # Create new snapshot of the volume
            lvm_lock
            lvcreate -s -n "thin_vol_${i}_snap" "${VG_NAME}/thin_vol_${i}"
            lvm_unlock
        done

        pool_stats=$(get_pool_stats)
        log_info "  Pool usage after snapshot: ${pool_stats}"

        # Step 2: RACE MODE - Run I/O and discard CONCURRENTLY
        if [[ "$RACE_MODE" == "enabled" ]]; then
            log_info "  Step 2/8: RACE MODE - Concurrent I/O + Discard for ${SNAPSHOT_IO_DURATION}s..."
            pool_stats=$(get_pool_stats)
            log_info "  Pool usage before concurrent ops: ${pool_stats}"

            local io_pids=()
            local discard_pids=()

            # Start I/O on all volumes in batch
            for i in $(seq $batch_start $batch_end); do
                (
                    local device="/dev/${VG_NAME}/thin_vol_${i}"
                    local target="$device"

                    if [[ "$VOLUME_MODE" == "formatted" ]]; then
                        target="/mnt/thin_vol_${i}/testfile"
                    fi

                    # Run FIO with continuous random writes
                    fio --name="race_io_vol_${i}" \
                        --filename="$target" \
                        --size=50% \
                        --rw=randwrite \
                        --bs=4k \
                        --ioengine=libaio \
                        --iodepth=32 \
                        --direct=1 \
                        --runtime=${SNAPSHOT_IO_DURATION} \
                        --time_based \
                        --output="${LOG_DIR}/fio_race_vol_${i}_iter_${ITERATION_COUNT}.log" \
                        >/dev/null 2>&1
                ) &
                io_pids+=($!)
            done

            # Small delay to let I/O start, then issue discards WHILE I/O is running
            sleep 1

            # Start aggressive discards CONCURRENTLY with I/O
            for i in $(seq $batch_start $batch_end); do
                (
                    local device="/dev/${VG_NAME}/thin_vol_${i}"
                    local snap_device="/dev/${VG_NAME}/thin_vol_${i}_snap"

                    # Issue multiple discards in rapid succession while I/O is running
                    for attempt in $(seq 1 5); do
                        if [[ "$VOLUME_MODE" == "formatted" && "$FSTRIM_MODE" == "1" ]]; then
                            # Use fstrim on mounted filesystem
                            fstrim "/mnt/thin_vol_${i}" 2>/dev/null || true
                        else
                            # Partial discards to create more race opportunities
                            local vol_size=$(blockdev --getsize64 "$device" 2>/dev/null || echo 0)
                            if [[ $vol_size -gt 0 ]]; then
                                local chunk=$((vol_size / 4))
                                # Discard different regions rapidly
                                blkdiscard -o 0 -l $chunk "$device" 2>/dev/null || true
                                blkdiscard -o $chunk -l $chunk "$device" 2>/dev/null || true
                                blkdiscard -o $((chunk * 2)) -l $chunk "$device" 2>/dev/null || true
                                blkdiscard -o $((chunk * 3)) -l $chunk "$device" 2>/dev/null || true
                            fi
                        fi
                        # Also discard on snapshot to stress refcounts
                        if [[ "$DISCARD_DURING_SNAPSHOT" == "1" ]]; then
                            blkdiscard "$snap_device" 2>/dev/null || true
                        fi
                        sleep 0.5
                    done
                ) &
                discard_pids+=($!)
            done

            # Wait for discards to complete (they should finish before I/O)
            for pid in "${discard_pids[@]}"; do
                wait "$pid" 2>/dev/null || true
            done
            TOTAL_DISCARDS=$((TOTAL_DISCARDS + (batch_end - batch_start + 1) * 5))

            # Wait for I/O to complete
            for pid in "${io_pids[@]}"; do
                wait "$pid" 2>/dev/null || true
            done

            pool_stats=$(get_pool_stats)
            log_info "  Pool usage after concurrent ops: ${pool_stats}"

        else
            # Sequential mode (original behavior)
            log_info "  Step 2/8: Sequential I/O for ${SNAPSHOT_IO_DURATION}s..."
            pool_stats=$(get_pool_stats)
            log_info "  Pool usage before I/O: ${pool_stats}"

            local pids=()
            for i in $(seq $batch_start $batch_end); do
                (
                    local device="/dev/${VG_NAME}/thin_vol_${i}"
                    local target="$device"

                    if [[ "$VOLUME_MODE" == "formatted" ]]; then
                        target="/mnt/thin_vol_${i}"
                    fi

                    fio --name="snapshot_io_vol_${i}" \
                        --filename="$target" \
                        --size=10% \
                        --rw=randwrite \
                        --bs=4k \
                        --ioengine=libaio \
                        --iodepth=16 \
                        --direct=1 \
                        --runtime=${SNAPSHOT_IO_DURATION} \
                        --time_based \
                        --output="${LOG_DIR}/fio_snapshot_vol_${i}_iter_${ITERATION_COUNT}.log" \
                        >/dev/null 2>&1
                ) &
                pids+=($!)
            done

            for pid in "${pids[@]}"; do
                wait "$pid"
            done

            pool_stats=$(get_pool_stats)
            log_info "  Pool usage after I/O: ${pool_stats}"

            # Step 3: Sequential discard
            log_info "  Step 3/8: Discarding volumes..."
            pool_stats=$(get_pool_stats)
            log_info "  Pool usage before discard: ${pool_stats}"

            pids=()
            for i in $(seq $batch_start $batch_end); do
                (
                    local device="/dev/${VG_NAME}/thin_vol_${i}"

                    if [[ "$VOLUME_MODE" == "formatted" ]]; then
                        if [[ "$FSTRIM_MODE" == "1" ]]; then
                            fstrim "/mnt/thin_vol_${i}" 2>/dev/null || true
                        fi
                        umount "/mnt/thin_vol_${i}" 2>/dev/null || true
                    fi

                    blkdiscard "$device" 2>/dev/null || true
                ) &
                pids+=($!)
            done

            for pid in "${pids[@]}"; do
                wait "$pid"
            done
            TOTAL_DISCARDS=$((TOTAL_DISCARDS + (batch_end - batch_start + 1)))

            pool_stats=$(get_pool_stats)
            log_info "  Pool usage after discard: ${pool_stats}"
        fi

        # Step 4: Unmount if formatted and race mode (wasn't unmounted yet)
        if [[ "$VOLUME_MODE" == "formatted" && "$RACE_MODE" == "enabled" ]]; then
            log_info "  Step 4/8: Unmounting volumes..."
            for i in $(seq $batch_start $batch_end); do
                umount "/mnt/thin_vol_${i}" 2>/dev/null || true
            done
        fi

        # Step 5: Perform thin pool metadata snapshot operation
        # This simulates what monitoring tools do to inspect pool metadata
        # I/O continues on this batch and other batch during this operation
        log_info "  Step 5/8: Thin pool metadata snapshot..."
        metadata_snapshot_operation

        # Step 6: Stop I/O on this batch ONLY - right before deletion
        # I/O on the other batch continues throughout
        log_info "  Step 6/8: Stopping I/O on batch ${batch_start}-${batch_end} before deletion..."
        stop_io_workload_range $batch_start $batch_end

        # Step 7: Delete volumes - discard whole volume first, then delete
        # NOTE: LVM operations (lvremove) MUST be serialized - they cannot run in parallel
        # blkdiscard is a block device operation but we run it before delete for each volume
        log_info "  Step 7/8: Deleting volumes (discard then delete)..."
        pool_stats=$(get_pool_stats)
        log_info "  Pool usage before volume delete: ${pool_stats}"

        # For each volume: discard whole volume, then delete (serialized)
        for i in $(seq $batch_start $batch_end); do
            local device="/dev/${VG_NAME}/thin_vol_${i}"

            # Discard the whole volume first (block device op, no LVM lock needed)
            blkdiscard "$device" 2>/dev/null || true
            TOTAL_DISCARDS=$((TOTAL_DISCARDS + 1))

            # Then delete the volume (LVM op, needs lock)
            lvm_lock
            lvremove -f "${VG_NAME}/thin_vol_${i}" 2>/dev/null || true
            lvm_unlock
            TOTAL_DELETES=$((TOTAL_DELETES + 1))
        done

        # Delete snapshots (LVM operations serialized)
        log_info "  Deleting snapshots..."
        for i in $(seq $batch_start $batch_end); do
            lvm_lock
            lvremove -f "${VG_NAME}/thin_vol_${i}_snap" 2>/dev/null || true
            lvm_unlock
        done

        pool_stats=$(get_pool_stats)
        log_info "  Pool usage after delete: ${pool_stats}"

        # Recreate volumes (LVM operations serialized)
        log_info "  Recreating volumes..."

        local pool_size=$(lvs --noheadings --units b -o lv_size "${THIN_POOL}" | tr -d ' B')
        local total_provisioned=$((pool_size * POOL_CAPACITY_PERCENT / 100))
        local volume_size=$((total_provisioned / NUM_VOLUMES))
        local volume_size_mb=$((volume_size / 1024 / 1024))

        for i in $(seq $batch_start $batch_end); do
            lvm_lock
            lvcreate -V "${volume_size_mb}M" -T "${THIN_POOL}" -n "thin_vol_${i}"
            lvm_unlock
            TOTAL_CREATES=$((TOTAL_CREATES + 1))

            # Format if needed (not an LVM operation, can run after unlock)
            if [[ "$VOLUME_MODE" == "formatted" ]]; then
                mkfs.ext4 -F "/dev/${VG_NAME}/thin_vol_${i}" >/dev/null 2>&1
                mount "/dev/${VG_NAME}/thin_vol_${i}" "/mnt/thin_vol_${i}"
            fi
        done

        pool_stats=$(get_pool_stats)
        log_info "  Pool usage after recreate: ${pool_stats}"

        # Step 8: Restart I/O on the recreated volumes
        log_info "  Step 8/8: Restarting I/O on batch ${batch_start}-${batch_end}..."
        start_io_workload_range $batch_start $batch_end
    done

    log_success "Batch recycling complete for volumes ${start_idx}-${end_idx}"
}

#######################################
# Get thin pool usage statistics
#######################################
get_pool_stats() {
    local data_percent=$(lvs --noheadings -o data_percent "${THIN_POOL}" 2>/dev/null | tr -d ' ')
    local meta_percent=$(lvs --noheadings -o metadata_percent "${THIN_POOL}" 2>/dev/null | tr -d ' ')

    # Default to 0 if empty
    data_percent=${data_percent:-0}
    meta_percent=${meta_percent:-0}

    echo "${data_percent},${meta_percent}"
}

#######################################
# Check for metadata exhaustion warning
#######################################
check_metadata_exhaustion() {
    local pool_stats=$(get_pool_stats)
    IFS=',' read -r data_pct meta_pct <<< "$pool_stats"

    # Remove decimal for comparison
    local meta_int=${meta_pct%.*}
    local data_int=${data_pct%.*}

    if [[ $meta_int -ge 95 ]]; then
        log_error "!!! CRITICAL: Metadata usage at ${meta_pct}% - approaching exhaustion !!!"
        log_error "This may trigger 'space map common: unable to decrement block' errors"
        echo "$(date): METADATA CRITICAL - ${meta_pct}%" >> "${LOG_DIR}/metadata_warnings.log"
    elif [[ $meta_int -ge 80 ]]; then
        log_warn "WARNING: Metadata usage at ${meta_pct}% - high usage"
        echo "$(date): METADATA WARNING - ${meta_pct}%" >> "${LOG_DIR}/metadata_warnings.log"
    fi

    if [[ $data_int -ge 95 ]]; then
        log_warn "WARNING: Data usage at ${data_pct}% - pool nearly full"
    fi

    # Check for pool errors in dmesg
    if dmesg | tail -50 | grep -qi "space map\|unable to decrement\|thin pool\|dm-thin" 2>/dev/null; then
        log_error "!!! KERNEL ERROR DETECTED - Check dmesg for thin pool errors !!!"
        dmesg | tail -20 | grep -i "thin\|dm-\|space map" >> "${LOG_DIR}/kernel_errors.log" 2>/dev/null || true
    fi
}

#######################################
# Print iteration summary
#######################################
print_iteration_summary() {
    local iteration=$1
    local runtime=$2
    local pool_stats=$3

    IFS=',' read -r data_pct meta_pct <<< "$pool_stats"

    echo ""
    log_info "=========================================="
    log_info "Iteration $iteration Summary"
    log_info "=========================================="
    log_info "Runtime: ${runtime}s"
    log_info "Total Creates: $TOTAL_CREATES"
    log_info "Total Deletes: $TOTAL_DELETES"
    log_info "Total Discards: $TOTAL_DISCARDS"
    log_info "Total Metadata Snaps: $TOTAL_METADATA_SNAPS"
    log_info "Pool Data Used: ${data_pct}%"
    log_info "Pool Metadata Used: ${meta_pct}%"

    # Get aggregate I/O stats
    local agg_stats=$(grep "^${iteration},aggregate," "$IOSTAT_LOG" | tail -1)
    if [[ -n "$agg_stats" ]]; then
        IFS=',' read -r _ _ _ rio rbytes wio wbytes dio dbytes fio <<< "$agg_stats"
        local rbytes_mb=$((rbytes / 1024 / 1024))
        local wbytes_mb=$((wbytes / 1024 / 1024))
        local dbytes_mb=$((dbytes / 1024 / 1024))

        log_info "Aggregate I/O (since start):"
        log_info "  Read: $rio ops, ${rbytes_mb} MB"
        log_info "  Write: $wio ops, ${wbytes_mb} MB"
        log_info "  Discard: $dio ops, ${dbytes_mb} MB"
        log_info "  Flush: $fio ops"
    fi

    # Get delta I/O stats for this iteration
    local delta_stats=$(grep "^${iteration},delta," "$IOSTAT_LOG" | head -1)
    if [[ -n "$delta_stats" ]]; then
        IFS=',' read -r _ _ _ rio rbytes wio wbytes dio dbytes fio <<< "$delta_stats"
        local rbytes_mb=$((rbytes / 1024 / 1024))
        local wbytes_mb=$((wbytes / 1024 / 1024))
        local dbytes_mb=$((dbytes / 1024 / 1024))

        log_info "This Iteration I/O:"
        log_info "  Read: $rio ops, ${rbytes_mb} MB"
        log_info "  Write: $wio ops, ${wbytes_mb} MB"
        log_info "  Discard: $dio ops, ${dbytes_mb} MB"
        log_info "  Flush: $fio ops"
    fi

    log_info "=========================================="
    echo ""
}

#######################################
# Run single iteration with batch rotation
# All 16 volumes have I/O running
# Alternate between batch A (1-8) and batch B (9-16) for recycling
# I/O stops on batch only before deletion, other batch continues
#######################################
run_iteration() {
    ITERATION_COUNT=$((ITERATION_COUNT + 1))
    local current_time=$(date +%s)
    local runtime=$((current_time - START_TIME))

    # Determine which batch to recycle this iteration (alternates 0, 1, 0, 1, ...)
    # Batch 0 = volumes 1 to BATCH_SIZE (1-8)
    # Batch 1 = volumes (BATCH_SIZE+1) to NUM_VOLUMES (9-16)
    local batch_to_recycle=$((ITERATION_COUNT % 2))
    local recycle_start recycle_end

    if [[ $batch_to_recycle -eq 1 ]]; then
        # Odd iterations: recycle batch A (1-8)
        recycle_start=1
        recycle_end=$BATCH_SIZE
    else
        # Even iterations: recycle batch B (9-16)
        recycle_start=$((BATCH_SIZE + 1))
        recycle_end=$NUM_VOLUMES
    fi

    log_info "Starting iteration $ITERATION_COUNT (runtime: ${runtime}s)"
    log_info "Recycling batch: volumes ${recycle_start}-${recycle_end}"
    log_info "I/O continues on: all volumes until deletion"

    # Capture I/O stats before
    capture_iostats "before" "$ITERATION_COUNT"

    # For the first iteration, start I/O on ALL volumes (1-16)
    # For subsequent iterations, I/O should already be running on all volumes
    # (previous iteration restarted I/O on recycled batch)
    if [[ $ITERATION_COUNT -eq 1 ]]; then
        log_info "First iteration: Starting I/O on ALL volumes (1-${NUM_VOLUMES})..."
        start_io_workload_all
        # Let I/O run for a bit before recycling
        sleep 5
    fi

    # Recycle the selected batch
    # I/O continues on all volumes until right before deletion (handled inside recycle_batch)
    # After deletion+recreation, I/O is restarted on the recycled batch (handled inside recycle_batch)
    recycle_batch $recycle_start $recycle_end

    # Let I/O stabilize after batch recycling
    sleep 3

    # Capture I/O stats after
    capture_iostats "after" "$ITERATION_COUNT"

    # Calculate deltas
    calculate_iostat_delta "$ITERATION_COUNT"

    # Calculate aggregate stats
    calculate_aggregate_stats "$ITERATION_COUNT"

    # Get pool statistics
    local pool_stats=$(get_pool_stats)
    IFS=',' read -r data_pct meta_pct <<< "$pool_stats"

    # Check for metadata exhaustion and kernel errors
    check_metadata_exhaustion

    # Log to stats file
    echo "${ITERATION_COUNT},${runtime},${TOTAL_CREATES},${TOTAL_DELETES},${TOTAL_DISCARDS},${TOTAL_METADATA_SNAPS},${data_pct},${meta_pct}" >> "$STATS_LOG"

    # Print summary
    print_iteration_summary "$ITERATION_COUNT" "$runtime" "$pool_stats"
}

#######################################
# Check if test should continue
#######################################
should_continue() {
    # Check max iterations
    if [[ $MAX_ITERATIONS -gt 0 && $ITERATION_COUNT -ge $MAX_ITERATIONS ]]; then
        log_info "Reached maximum iterations: $MAX_ITERATIONS"
        return 1
    fi

    # Check max hours
    if [[ $MAX_HOURS -gt 0 ]]; then
        local current_time=$(date +%s)
        local runtime=$((current_time - START_TIME))
        local max_seconds=$((MAX_HOURS * 3600))

        if [[ $runtime -ge $max_seconds ]]; then
            log_info "Reached maximum runtime: $MAX_HOURS hours"
            return 1
        fi
    fi

    return 0
}

#######################################
# Main execution
#######################################
main() {
    log_info "LVM Thin Pool Stress Test - Version $VERSION"
    log_info "=========================================="

    # Parse arguments
    parse_args "$@"

    # Validate inputs
    validate_inputs

    # Setup logging
    setup_logging

    # Display configuration
    log_info "Configuration:"
    log_info "  Drives: $DRIVES"
    log_info "  Parallel Deletes: $PARALLEL_DELETES"
    log_info "  Max Hours: $MAX_HOURS (0 = indefinite)"
    log_info "  Max Iterations: $MAX_ITERATIONS (0 = indefinite)"
    log_info "  Metadata Size: $METADATA_SIZE"
    log_info "  Pool Capacity: ${POOL_CAPACITY_PERCENT}%"
    log_info "  Total Volumes: $NUM_VOLUMES"
    log_info "  I/O Volumes: $IO_VOLUMES"
    log_info "  Cycle Volumes: $CYCLE_VOLUMES"
    log_info "  Volume Mode: $VOLUME_MODE"
    log_info "  Log Directory: $LOG_DIR"
    log_info "Race Condition Stress Settings:"
    log_info "  Race Mode: $RACE_MODE"
    log_info "  Concurrent Discard+IO: $CONCURRENT_DISCARD_IO"
    log_info "  Aggressive Discard: $AGGRESSIVE_DISCARD"
    log_info "  Metadata Stress: $METADATA_STRESS"
    log_info "  Fstrim Mode: $FSTRIM_MODE"
    log_info "  Discard During Snapshot: $DISCARD_DURING_SNAPSHOT"
    log_info "  Snapshot I/O Duration: ${SNAPSHOT_IO_DURATION}s"
    log_info "=========================================="

    # Setup thin pool
    setup_thin_pool

    # Create initial volumes
    create_thin_volumes

    # Run test iterations
    log_info "Starting stress test iterations..."

    while should_continue; do
        run_iteration
    done

    # Final summary
    local end_time=$(date +%s)
    local total_runtime=$((end_time - START_TIME))

    log_success "=========================================="
    log_success "Test Complete!"
    log_success "=========================================="
    log_success "Total Runtime: ${total_runtime}s ($((total_runtime / 60)) minutes)"
    log_success "Total Iterations: $ITERATION_COUNT"
    log_success "Total Creates: $TOTAL_CREATES"
    log_success "Total Deletes: $TOTAL_DELETES"
    log_success "Total Discards: $TOTAL_DISCARDS"
    log_success "Total Metadata Snaps: $TOTAL_METADATA_SNAPS"
    log_success "Logs saved to: $LOG_DIR"
    log_success "=========================================="
}

# Run main function
main "$@"

