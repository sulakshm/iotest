#!/bin/bash
#
# LVM Thin Pool Stress Test - Log Analysis Tool
#
# Analyzes log files from thin pool stress tests and generates reports
# Extended for race condition stress testing and refcount corruption detection
#

set -euo pipefail

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

#######################################
# Print usage
#######################################
usage() {
    cat << EOF
LVM Thin Pool Stress Test - Log Analysis Tool

Usage: $0 <log_directory> [options]

Analyzes stress test logs and generates summary reports.
Specifically designed to detect 'space map common: unable to decrement block' errors.

Options:
  --check-kernel    Also check current dmesg for thin pool errors
  --verbose         Show detailed race condition analysis
  --help            Show this help

Examples:
  $0 ./thin_pool_stress_logs
  $0 ./logs/max_stress_test_20260210 --check-kernel
  $0 ./logs/metadata_exhaustion_test --verbose

EOF
    exit 1
}

#######################################
# Analyze statistics log
#######################################
analyze_stats() {
    local stats_file=$1
    
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Statistics Summary${NC}"
    echo -e "${BLUE}========================================${NC}"
    
    # Skip header lines
    local data=$(grep -v "^#" "$stats_file")
    
    # Get totals
    local total_iterations=$(echo "$data" | wc -l)
    local last_line=$(echo "$data" | tail -1)
    
    IFS=',' read -r iter runtime creates deletes discards data_pct meta_pct <<< "$last_line"
    
    echo "Total Iterations: $total_iterations"
    echo "Total Runtime: ${runtime}s ($((runtime / 60)) minutes, $((runtime / 3600)) hours)"
    echo "Total Creates: $creates"
    echo "Total Deletes: $deletes"
    echo "Total Discards: $discards"
    echo "Final Pool Data Usage: ${data_pct}%"
    echo "Final Pool Metadata Usage: ${meta_pct}%"
    echo ""
    
    # Calculate averages
    local avg_creates=$((creates / total_iterations))
    local avg_deletes=$((deletes / total_iterations))
    local avg_discards=$((discards / total_iterations))
    
    echo "Average per Iteration:"
    echo "  Creates: $avg_creates"
    echo "  Deletes: $avg_deletes"
    echo "  Discards: $avg_discards"
    echo ""
    
    # Pool usage trend
    echo "Pool Usage Trend:"
    echo "Iteration | Data% | Meta%"
    echo "----------|-------|------"
    echo "$data" | awk -F',' '{printf "%9d | %5s | %5s\n", $1, $6, $7}' | tail -10
    echo ""

    # Check for high metadata usage (potential corruption trigger)
    local max_meta=$(echo "$data" | awk -F',' '{print $7}' | sort -n | tail -1)
    local max_meta_int=${max_meta%.*}
    if [[ $max_meta_int -ge 80 ]]; then
        echo -e "${RED}!!! HIGH METADATA USAGE DETECTED: ${max_meta}% !!!${NC}"
        echo "This may have triggered refcount corruption"
        echo ""
    fi
}

#######################################
# Analyze I/O statistics
#######################################
analyze_iostats() {
    local iostat_file=$1

    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}I/O Statistics Summary${NC}"
    echo -e "${BLUE}========================================${NC}"
    
    # Get aggregate stats
    local agg_stats=$(grep ",aggregate," "$iostat_file" | tail -1)
    
    if [[ -z "$agg_stats" ]]; then
        echo "No aggregate statistics found"
        return
    fi
    
    IFS=',' read -r iter phase device rio rbytes wio wbytes dio dbytes fio <<< "$agg_stats"
    
    # Convert to human-readable
    local rbytes_gb=$((rbytes / 1024 / 1024 / 1024))
    local wbytes_gb=$((wbytes / 1024 / 1024 / 1024))
    local dbytes_gb=$((dbytes / 1024 / 1024 / 1024))
    
    echo "Total I/O Operations:"
    echo "  Read:    $rio ops, ${rbytes_gb} GB"
    echo "  Write:   $wio ops, ${wbytes_gb} GB"
    echo "  Discard: $dio ops, ${dbytes_gb} GB"
    echo "  Flush:   $fio ops"
    echo ""
    
    # Calculate I/O rates
    local total_ops=$((rio + wio + dio + fio))
    local total_bytes=$((rbytes + wbytes + dbytes))
    local total_gb=$((total_bytes / 1024 / 1024 / 1024))
    
    echo "Total Operations: $total_ops"
    echo "Total Data: ${total_gb} GB"
    echo ""
    
    # Per-iteration averages
    local avg_rio=$((rio / iter))
    local avg_wio=$((wio / iter))
    local avg_dio=$((dio / iter))
    
    echo "Average per Iteration:"
    echo "  Read Ops:    $avg_rio"
    echo "  Write Ops:   $avg_wio"
    echo "  Discard Ops: $avg_dio"
    echo ""
    
    # Show per-device breakdown
    echo "Per-Device I/O (last iteration):"
    echo "Device | Read Ops | Write Ops | Discard Ops"
    echo "-------|----------|-----------|------------"
    grep "^${iter},delta," "$iostat_file" | \
        awk -F',' '{printf "%-6s | %8d | %9d | %11d\n", $3, $4, $6, $8}'
    echo ""
}

#######################################
# Analyze iteration timing
#######################################
analyze_timing() {
    local stats_file=$1
    
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Iteration Timing Analysis${NC}"
    echo -e "${BLUE}========================================${NC}"
    
    local data=$(grep -v "^#" "$stats_file")
    
    # Calculate iteration durations
    local prev_runtime=0
    local total_duration=0
    local count=0
    
    echo "Iteration | Duration (s)"
    echo "----------|-------------"
    
    while IFS=',' read -r iter runtime creates deletes discards data_pct meta_pct; do
        local duration=$((runtime - prev_runtime))
        if [[ $iter -gt 1 ]]; then
            echo "$iter | $duration"
            total_duration=$((total_duration + duration))
            count=$((count + 1))
        fi
        prev_runtime=$runtime
    done <<< "$data"
    
    if [[ $count -gt 0 ]]; then
        local avg_duration=$((total_duration / count))
        echo ""
        echo "Average Iteration Duration: ${avg_duration}s"
    fi
    echo ""
}

#######################################
# Check for errors
#######################################
check_errors() {
    local log_dir=$1

    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Error Analysis${NC}"
    echo -e "${BLUE}========================================${NC}"

    local main_log=$(find "$log_dir" -name "stress_test_*.log" | head -1)

    if [[ -z "$main_log" ]]; then
        echo "No main log file found"
        return
    fi

    local error_count=$(grep -i "error" "$main_log" 2>/dev/null | wc -l)
    local warn_count=$(grep -i "warn" "$main_log" 2>/dev/null | wc -l)

    echo "Errors: $error_count"
    echo "Warnings: $warn_count"
    echo ""

    if [[ $error_count -gt 0 ]]; then
        echo -e "${RED}Recent Errors:${NC}"
        grep -i "error" "$main_log" | tail -5
        echo ""
    fi

    if [[ $warn_count -gt 0 ]]; then
        echo -e "${YELLOW}Recent Warnings:${NC}"
        grep -i "warn" "$main_log" | tail -5
        echo ""
    fi
}

#######################################
# Analyze kernel errors (refcount corruption)
#######################################
analyze_kernel_errors() {
    local log_dir=$1

    echo -e "${RED}========================================${NC}"
    echo -e "${RED}Kernel Error Analysis (Refcount Corruption)${NC}"
    echo -e "${RED}========================================${NC}"

    local kernel_log="${log_dir}/kernel_errors.log"

    if [[ -f "$kernel_log" ]]; then
        local error_count=$(wc -l < "$kernel_log")
        echo -e "${RED}!!! KERNEL ERRORS DETECTED: $error_count entries !!!${NC}"
        echo ""
        echo "Kernel error log contents:"
        echo "---"
        cat "$kernel_log"
        echo "---"
        echo ""

        # Check for specific refcount corruption error
        if grep -qi "unable to decrement" "$kernel_log" 2>/dev/null; then
            echo -e "${RED}*** TARGET ERROR FOUND: 'unable to decrement block' ***${NC}"
            echo -e "${RED}*** REFCOUNT CORRUPTION SUCCESSFULLY REPRODUCED ***${NC}"
            echo ""
        fi

        if grep -qi "space map" "$kernel_log" 2>/dev/null; then
            echo -e "${RED}*** SPACE MAP ERRORS DETECTED ***${NC}"
            grep -i "space map" "$kernel_log"
            echo ""
        fi
    else
        echo "No kernel errors logged during test"
        echo ""
    fi
}

#######################################
# Analyze metadata exhaustion warnings
#######################################
analyze_metadata_warnings() {
    local log_dir=$1

    echo -e "${YELLOW}========================================${NC}"
    echo -e "${YELLOW}Metadata Exhaustion Analysis${NC}"
    echo -e "${YELLOW}========================================${NC}"

    local meta_log="${log_dir}/metadata_warnings.log"

    if [[ -f "$meta_log" ]]; then
        local warning_count=$(grep -c "WARNING" "$meta_log" 2>/dev/null || echo 0)
        local critical_count=$(grep -c "CRITICAL" "$meta_log" 2>/dev/null || echo 0)

        echo "Metadata Warnings: $warning_count"
        echo "Metadata Critical: $critical_count"
        echo ""

        if [[ $critical_count -gt 0 ]]; then
            echo -e "${RED}!!! CRITICAL METADATA EXHAUSTION EVENTS !!!${NC}"
            echo "These events may have triggered refcount corruption:"
            grep "CRITICAL" "$meta_log" | tail -10
            echo ""
        fi

        if [[ $warning_count -gt 0 ]]; then
            echo "High metadata usage events:"
            grep "WARNING" "$meta_log" | tail -5
            echo ""
        fi
    else
        echo "No metadata exhaustion warnings logged"
        echo ""
    fi
}

#######################################
# Analyze race mode effectiveness
#######################################
analyze_race_mode() {
    local log_dir=$1
    local verbose=$2

    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}Race Mode Analysis${NC}"
    echo -e "${CYAN}========================================${NC}"

    local main_log=$(find "$log_dir" -name "stress_test_*.log" | head -1)

    if [[ -z "$main_log" ]]; then
        echo "No main log file found"
        return
    fi

    # Check if race mode was enabled
    if grep -q "Race mode: enabled" "$main_log" 2>/dev/null; then
        echo -e "${GREEN}Race Mode: ENABLED${NC}"

        # Count concurrent operations
        local concurrent_ops=$(grep -c "RACE MODE - Concurrent" "$main_log" 2>/dev/null || echo 0)
        echo "Concurrent I/O+Discard cycles: $concurrent_ops"

        # Count discard operations
        local total_discards=$(grep -c "Discarding" "$main_log" 2>/dev/null || echo 0)
        echo "Total discard operations: $total_discards"

        if [[ "$verbose" == "true" ]]; then
            echo ""
            echo "Race condition stress details:"
            grep -E "(RACE MODE|concurrent|discard race)" "$main_log" | tail -20
        fi
    else
        echo -e "${YELLOW}Race Mode: DISABLED (sequential operations)${NC}"
        echo "This test used sequential operations - less likely to trigger refcount issues"
    fi
    echo ""

    # Check for metadata stress mode
    if grep -q "Metadata Stress: 1" "$main_log" 2>/dev/null; then
        echo -e "${RED}Metadata Stress Mode: ENABLED (512M metadata)${NC}"
    fi

    # Check for fstrim mode
    if grep -q "Fstrim Mode: 1" "$main_log" 2>/dev/null; then
        echo "Fstrim Mode: ENABLED"
    fi
    echo ""
}

#######################################
# Check current kernel dmesg for errors
#######################################
check_current_dmesg() {
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}Current Kernel Messages (dmesg)${NC}"
    echo -e "${RED}========================================${NC}"

    echo "Checking current dmesg for thin pool errors..."
    echo ""

    local thin_errors=$(dmesg 2>/dev/null | grep -iE "thin|dm-|space map|unable to decrement" | tail -20)

    if [[ -n "$thin_errors" ]]; then
        echo -e "${RED}Thin pool related kernel messages found:${NC}"
        echo "$thin_errors"
        echo ""

        if echo "$thin_errors" | grep -qi "unable to decrement"; then
            echo -e "${RED}*** TARGET ERROR FOUND IN DMESG ***${NC}"
            echo -e "${RED}*** 'unable to decrement block' - REFCOUNT CORRUPTION ***${NC}"
        fi
    else
        echo "No thin pool errors found in current dmesg"
    fi
    echo ""
}

#######################################
# Generate summary report
#######################################
generate_report() {
    local log_dir=$1
    local check_kernel=$2
    local verbose=$3
    local output_file="${log_dir}/analysis_report.txt"

    {
        echo "============================================================"
        echo "LVM Thin Pool Stress Test - Analysis Report"
        echo "Purpose: Detect 'space map common: unable to decrement block'"
        echo "============================================================"
        echo "Generated: $(date)"
        echo "Log Directory: $log_dir"
        echo ""

        # Find log files
        local stats_file=$(find "$log_dir" -name "stats_*.log" 2>/dev/null | head -1)
        local iostat_file=$(find "$log_dir" -name "iostat_*.log" 2>/dev/null | head -1)

        # First check for the target error (most important)
        analyze_kernel_errors "$log_dir"

        # Check metadata exhaustion
        analyze_metadata_warnings "$log_dir"

        # Analyze race mode effectiveness
        analyze_race_mode "$log_dir" "$verbose"

        if [[ -n "$stats_file" ]]; then
            analyze_stats "$stats_file"
        fi

        if [[ -n "$iostat_file" ]]; then
            analyze_iostats "$iostat_file"
        fi

        if [[ -n "$stats_file" ]]; then
            analyze_timing "$stats_file"
        fi

        check_errors "$log_dir"

        # Check current dmesg if requested
        if [[ "$check_kernel" == "true" ]]; then
            check_current_dmesg
        fi

        # Final verdict
        echo "============================================================"
        echo "VERDICT"
        echo "============================================================"

        local kernel_log="${log_dir}/kernel_errors.log"
        if [[ -f "$kernel_log" ]] && grep -qi "unable to decrement" "$kernel_log" 2>/dev/null; then
            echo -e "${RED}*** REFCOUNT CORRUPTION REPRODUCED ***${NC}"
            echo "The 'space map common: unable to decrement block' error was detected."
            echo "Check kernel_errors.log for details."
        elif [[ -f "$kernel_log" ]] && [[ -s "$kernel_log" ]]; then
            echo -e "${YELLOW}KERNEL ERRORS DETECTED - Review kernel_errors.log${NC}"
        else
            local meta_log="${log_dir}/metadata_warnings.log"
            if [[ -f "$meta_log" ]] && grep -q "CRITICAL" "$meta_log" 2>/dev/null; then
                echo -e "${YELLOW}HIGH METADATA PRESSURE DETECTED${NC}"
                echo "Metadata reached critical levels. Continue testing to trigger corruption."
            else
                echo "No refcount corruption detected in this test run."
                echo "Consider:"
                echo "  - Running longer tests"
                echo "  - Using --metadata-stress option"
                echo "  - Increasing parallel deletes (-p 8)"
                echo "  - Increasing capacity (-c 95)"
            fi
        fi
        echo ""

    } | tee "$output_file"

    echo -e "${GREEN}Report saved to: $output_file${NC}"
}

#######################################
# Main
#######################################
main() {
    local log_dir=""
    local check_kernel="false"
    local verbose="false"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --check-kernel)
                check_kernel="true"
                shift
                ;;
            --verbose)
                verbose="true"
                shift
                ;;
            --help)
                usage
                ;;
            -*)
                echo "Unknown option: $1"
                usage
                ;;
            *)
                log_dir="$1"
                shift
                ;;
        esac
    done

    if [[ -z "$log_dir" ]]; then
        usage
    fi

    if [[ ! -d "$log_dir" ]]; then
        echo "Error: Directory not found: $log_dir"
        exit 1
    fi

    generate_report "$log_dir" "$check_kernel" "$verbose"
}

main "$@"

