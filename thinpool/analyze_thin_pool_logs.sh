#!/bin/bash
#
# LVM Thin Pool Stress Test - Log Analysis Tool
#
# Analyzes log files from thin pool stress tests and generates reports
#

set -euo pipefail

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

#######################################
# Print usage
#######################################
usage() {
    cat << EOF
LVM Thin Pool Stress Test - Log Analysis Tool

Usage: $0 <log_directory>

Analyzes stress test logs and generates summary reports.

Example:
  $0 ./thin_pool_stress_logs

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
    
    local error_count=$(grep -i "error" "$main_log" | wc -l)
    local warn_count=$(grep -i "warn" "$main_log" | wc -l)
    
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
# Generate summary report
#######################################
generate_report() {
    local log_dir=$1
    local output_file="${log_dir}/analysis_report.txt"
    
    {
        echo "LVM Thin Pool Stress Test - Analysis Report"
        echo "Generated: $(date)"
        echo "Log Directory: $log_dir"
        echo ""
        
        # Find log files
        local stats_file=$(find "$log_dir" -name "stats_*.log" | head -1)
        local iostat_file=$(find "$log_dir" -name "iostat_*.log" | head -1)
        
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
        
    } | tee "$output_file"
    
    echo -e "${GREEN}Report saved to: $output_file${NC}"
}

#######################################
# Main
#######################################
main() {
    if [[ $# -lt 1 ]]; then
        usage
    fi
    
    local log_dir=$1
    
    if [[ ! -d "$log_dir" ]]; then
        echo "Error: Directory not found: $log_dir"
        exit 1
    fi
    
    generate_report "$log_dir"
}

main "$@"

