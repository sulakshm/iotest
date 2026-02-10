#!/bin/bash
#
# LVM Thin Pool Stress Test - Common Scenarios
#
# This script provides pre-configured test scenarios for common use cases
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STRESS_SCRIPT="${SCRIPT_DIR}/thin_pool_stress_test.sh"

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Color codes for race mode indicator
RED='\033[0;31m'
CYAN='\033[0;36m'

#######################################
# Print scenario menu
#######################################
show_menu() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}LVM Thin Pool Stress Test Scenarios${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    echo -e "${CYAN}Purpose: Reproduce 'space map common: unable to decrement block' errors${NC}"
    echo ""
    echo "Select a test scenario:"
    echo ""
    echo -e "${RED}=== REFCOUNT CORRUPTION SCENARIOS (Race Mode) ===${NC}"
    echo "  1) Quick Race Test (30 min, concurrent I/O+discard)"
    echo "  2) Standard Race Test (4 hours, race mode enabled)"
    echo "  3) Metadata Exhaustion Test (minimal metadata, high stress)"
    echo "  4) Maximum Stress Test (8 parallel, 95% capacity, race mode)"
    echo "  5) Formatted + Fstrim Race Test (mounted fs with fstrim)"
    echo ""
    echo -e "${YELLOW}=== BASELINE SCENARIOS (No Race Mode) ===${NC}"
    echo "  6) Baseline Test (4 hours, sequential operations)"
    echo "  7) Extended Baseline (24 hours, no race conditions)"
    echo ""
    echo -e "${GREEN}=== OTHER SCENARIOS ===${NC}"
    echo "  8) Large Pool Test (32 volumes, 6 parallel deletes)"
    echo "  9) Stability Test (7 days, moderate stress)"
    echo " 10) Custom Configuration"
    echo " 11) Exit"
    echo ""
}

#######################################
# Get drives from user
#######################################
get_drives() {
    echo -e "${YELLOW}Available block devices:${NC}"
    lsblk -d -n -o NAME,SIZE,TYPE | grep disk
    echo ""
    read -p "Enter drives (comma-separated, e.g., /dev/sdb,/dev/sdc): " drives
    echo "$drives"
}

#######################################
# Scenario 1: Quick Race Test
# Purpose: Fast validation of race condition stress
#######################################
scenario_quick_race() {
    local drives=$(get_drives)

    echo -e "${RED}Starting Quick Race Test (concurrent I/O+discard)...${NC}"
    echo -e "${YELLOW}This test runs I/O and discard SIMULTANEOUSLY to trigger refcount races${NC}"
    "$STRESS_SCRIPT" \
        -d "$drives" \
        -p 4 \
        -h 0.5 \
        -n 16 \
        -c 80 \
        -v raw \
        --race-mode enabled \
        --snapshot-io-duration 20 \
        -l "./logs/quick_race_test_$(date +%Y%m%d_%H%M%S)"
}

#######################################
# Scenario 2: Standard Race Test
# Purpose: Standard duration race condition stress
#######################################
scenario_standard_race() {
    local drives=$(get_drives)

    echo -e "${RED}Starting Standard Race Test (4 hours)...${NC}"
    echo -e "${YELLOW}Race mode enabled - concurrent I/O and discard operations${NC}"
    "$STRESS_SCRIPT" \
        -d "$drives" \
        -p 4 \
        -h 4 \
        -n 16 \
        -c 80 \
        -v raw \
        --race-mode enabled \
        --snapshot-io-duration 30 \
        -l "./logs/standard_race_test_$(date +%Y%m%d_%H%M%S)"
}

#######################################
# Scenario 3: Metadata Exhaustion Test
# Purpose: Stress tmeta to near-100% to trigger corruption
#######################################
scenario_metadata_exhaustion() {
    local drives=$(get_drives)

    echo -e "${RED}Starting Metadata Exhaustion Test...${NC}"
    echo -e "${YELLOW}Using minimal 512M metadata to stress tmeta exhaustion${NC}"
    echo -e "${YELLOW}This is the most likely scenario to trigger refcount corruption${NC}"
    "$STRESS_SCRIPT" \
        -d "$drives" \
        -p 6 \
        -h 4 \
        -n 24 \
        -c 90 \
        -v raw \
        --race-mode enabled \
        --metadata-stress \
        --snapshot-io-duration 45 \
        -l "./logs/metadata_exhaustion_test_$(date +%Y%m%d_%H%M%S)"
}

#######################################
# Scenario 4: Maximum Stress Test
# Purpose: Maximum parallel operations with race conditions
#######################################
scenario_max_stress() {
    local drives=$(get_drives)

    echo -e "${RED}Starting Maximum Stress Test...${NC}"
    echo -e "${YELLOW}8 parallel deletes, 95% capacity, race mode - MAXIMUM STRESS${NC}"
    "$STRESS_SCRIPT" \
        -d "$drives" \
        -p 8 \
        -h 8 \
        -n 16 \
        -c 95 \
        -v raw \
        --race-mode enabled \
        --snapshot-io-duration 60 \
        -l "./logs/max_stress_test_$(date +%Y%m%d_%H%M%S)"
}

#######################################
# Scenario 5: Formatted + Fstrim Race Test
# Purpose: Test race conditions with mounted filesystems
#######################################
scenario_fstrim_race() {
    local drives=$(get_drives)

    echo -e "${RED}Starting Formatted + Fstrim Race Test...${NC}"
    echo -e "${YELLOW}Uses fstrim on mounted filesystems with concurrent I/O${NC}"
    "$STRESS_SCRIPT" \
        -d "$drives" \
        -p 4 \
        -h 4 \
        -n 16 \
        -c 80 \
        -v formatted \
        --race-mode enabled \
        --fstrim-mode \
        --snapshot-io-duration 30 \
        -l "./logs/fstrim_race_test_$(date +%Y%m%d_%H%M%S)"
}

#######################################
# Scenario 6: Baseline Test (No Race)
# Purpose: Baseline comparison without race conditions
#######################################
scenario_baseline() {
    local drives=$(get_drives)

    echo -e "${GREEN}Starting Baseline Test (no race conditions)...${NC}"
    echo -e "${YELLOW}Sequential operations - use for comparison with race mode${NC}"
    "$STRESS_SCRIPT" \
        -d "$drives" \
        -p 4 \
        -h 4 \
        -n 16 \
        -c 80 \
        -v raw \
        --no-race-mode \
        -l "./logs/baseline_test_$(date +%Y%m%d_%H%M%S)"
}

#######################################
# Scenario 7: Extended Baseline
# Purpose: Long-running baseline without race conditions
#######################################
scenario_extended_baseline() {
    local drives=$(get_drives)

    echo -e "${GREEN}Starting Extended Baseline Test (24 hours)...${NC}"
    echo -e "${YELLOW}No race conditions - sequential operations${NC}"
    "$STRESS_SCRIPT" \
        -d "$drives" \
        -p 4 \
        -h 24 \
        -n 16 \
        -c 80 \
        -v raw \
        --no-race-mode \
        -l "./logs/extended_baseline_test_$(date +%Y%m%d_%H%M%S)"
}

#######################################
# Scenario 8: Large Pool Test
#######################################
scenario_large_pool() {
    local drives=$(get_drives)

    echo -e "${GREEN}Starting Large Pool Test...${NC}"
    "$STRESS_SCRIPT" \
        -d "$drives" \
        -p 6 \
        -h 8 \
        -n 32 \
        -c 60 \
        -v raw \
        -m 20G \
        --race-mode enabled \
        -l "./logs/large_pool_test_$(date +%Y%m%d_%H%M%S)"
}

#######################################
# Scenario 9: Stability Test
#######################################
scenario_stability() {
    local drives=$(get_drives)

    echo -e "${GREEN}Starting Stability Test (7 days)...${NC}"
    "$STRESS_SCRIPT" \
        -d "$drives" \
        -p 2 \
        -h 168 \
        -n 16 \
        -c 80 \
        -v raw \
        --race-mode enabled \
        -l "./logs/stability_test_$(date +%Y%m%d_%H%M%S)"
}

#######################################
# Scenario 10: Custom Configuration
#######################################
scenario_custom() {
    local drives=$(get_drives)

    echo ""
    echo -e "${BLUE}=== Basic Configuration ===${NC}"
    read -p "Parallel deletes (1-8) [4]: " parallel
    parallel=${parallel:-4}
    read -p "Max hours (0=indefinite) [4]: " hours
    hours=${hours:-4}
    read -p "Max iterations (0=indefinite) [0]: " iterations
    iterations=${iterations:-0}
    read -p "Number of volumes [16]: " volumes
    volumes=${volumes:-16}
    read -p "Pool capacity percent [80]: " capacity
    capacity=${capacity:-80}
    read -p "Volume mode (raw/formatted) [raw]: " mode
    mode=${mode:-raw}
    read -p "Metadata size (e.g., 15G, 512M) [15G]: " metadata
    metadata=${metadata:-15G}

    echo ""
    echo -e "${RED}=== Race Condition Options ===${NC}"
    read -p "Enable race mode? (y/n) [y]: " race_mode
    race_mode=${race_mode:-y}

    local race_opts=""
    if [[ "$race_mode" == "y" || "$race_mode" == "Y" ]]; then
        race_opts="--race-mode enabled"

        read -p "Use metadata stress (512M metadata)? (y/n) [n]: " meta_stress
        if [[ "$meta_stress" == "y" || "$meta_stress" == "Y" ]]; then
            race_opts="$race_opts --metadata-stress"
        fi

        if [[ "$mode" == "formatted" ]]; then
            read -p "Use fstrim mode? (y/n) [y]: " fstrim
            if [[ "$fstrim" == "y" || "$fstrim" == "Y" ]]; then
                race_opts="$race_opts --fstrim-mode"
            fi
        fi

        read -p "Snapshot I/O duration in seconds [30]: " io_duration
        io_duration=${io_duration:-30}
        race_opts="$race_opts --snapshot-io-duration $io_duration"
    else
        race_opts="--no-race-mode"
    fi

    echo ""
    echo -e "${GREEN}Starting Custom Test...${NC}"
    echo "Command: $STRESS_SCRIPT -d $drives -p $parallel -h $hours -i $iterations -n $volumes -c $capacity -v $mode -m $metadata $race_opts"
    echo ""

    # shellcheck disable=SC2086
    "$STRESS_SCRIPT" \
        -d "$drives" \
        -p "$parallel" \
        -h "$hours" \
        -i "$iterations" \
        -n "$volumes" \
        -c "$capacity" \
        -v "$mode" \
        -m "$metadata" \
        $race_opts \
        -l "./logs/custom_test_$(date +%Y%m%d_%H%M%S)"
}

#######################################
# Main menu loop
#######################################
main() {
    # Check if stress script exists
    if [[ ! -f "$STRESS_SCRIPT" ]]; then
        echo "Error: Stress test script not found at $STRESS_SCRIPT"
        exit 1
    fi

    # Make stress script executable
    chmod +x "$STRESS_SCRIPT"

    while true; do
        show_menu
        read -p "Enter choice [1-11]: " choice
        echo ""

        case $choice in
            1) scenario_quick_race ;;
            2) scenario_standard_race ;;
            3) scenario_metadata_exhaustion ;;
            4) scenario_max_stress ;;
            5) scenario_fstrim_race ;;
            6) scenario_baseline ;;
            7) scenario_extended_baseline ;;
            8) scenario_large_pool ;;
            9) scenario_stability ;;
            10) scenario_custom ;;
            11) echo "Exiting..."; exit 0 ;;
            *) echo "Invalid choice. Please select 1-11." ;;
        esac

        echo ""
        read -p "Press Enter to return to menu..."
        clear
    done
}

# Run main
main

