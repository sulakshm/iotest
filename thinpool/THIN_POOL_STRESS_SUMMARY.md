# LVM Thin Pool Stress Test - Complete Solution

## Overview

This is a comprehensive LVM thin pool stress testing solution that validates thin pool behavior under heavy I/O load, parallel volume operations, and discard operations.

## What's Included

### 1. Main Stress Test Script
**File**: `thin_pool_stress_test.sh`

**Features**:
- ✅ Configurable thin pool with 15G metadata (default)
- ✅ Passdown discard and skip zeroing enabled
- ✅ 1-8 parallel volume deletes
- ✅ Continuous FIO-based I/O workload
- ✅ blkdiscard before volume deletion
- ✅ Raw or formatted (ext4) volume modes
- ✅ Comprehensive I/O statistics collection
- ✅ Automatic cleanup on exit

**Statistics Collected**:
- Per-iteration I/O operations (read/write/discard/flush)
- Per-iteration bytes transferred
- Aggregate I/O since test start
- Pool data and metadata usage
- Volume create/delete/discard counts

### 2. Test Scenarios Script
**File**: `thin_pool_test_scenarios.sh`

**Pre-configured Scenarios**:
1. Quick Test (30 minutes, 2 parallel)
2. Standard Test (4 hours, 4 parallel)
3. Extended Test (24 hours, 4 parallel)
4. High Stress Test (8 hours, 8 parallel)
5. Stability Test (7 days, 2 parallel)
6. Formatted Volumes Test (4 hours, 4 parallel)
7. Large Pool Test (32 volumes, 6 parallel)
8. Custom Configuration

### 3. Log Analysis Script
**File**: `analyze_thin_pool_logs.sh`

**Analysis Features**:
- Statistics summary (iterations, runtime, operations)
- I/O statistics summary (total and per-device)
- Iteration timing analysis
- Error and warning detection
- Automated report generation

### 4. Documentation
- **README_THIN_POOL_STRESS.md**: Complete reference documentation
- **QUICKSTART.md**: Quick start guide with examples
- **THIN_POOL_STRESS_SUMMARY.md**: This file

## Quick Start

### 1. Install Dependencies
```bash
sudo apt-get install -y lvm2 fio util-linux  # Ubuntu/Debian
sudo yum install -y lvm2 fio util-linux      # RHEL/CentOS
```

### 2. Make Scripts Executable
```bash
cd pxlens/ioload
chmod +x *.sh
```

### 3. Run a Test
```bash
# Interactive menu
sudo ./thin_pool_test_scenarios.sh

# Or direct command
sudo ./thin_pool_stress_test.sh -d /dev/sdb,/dev/sdc -p 4 -h 4
```

### 4. Analyze Results
```bash
sudo ./analyze_thin_pool_logs.sh ./thin_pool_stress_logs
```

## Architecture

### Test Flow

```
┌─────────────────────────────────────────────────────────────┐
│                     Setup Phase                              │
│  • Create PVs on drives                                      │
│  • Create VG                                                 │
│  • Create thin pool (metadata + data)                       │
│  • Configure: passdown discard, skip zeroing                │
│  • Create N thin volumes (50% of pool capacity)             │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│                  Iteration Loop                              │
│                                                              │
│  1. Capture I/O stats (before)                              │
│                                                              │
│  2. Start I/O workload on 8 volumes                         │
│     • FIO: 70% read, 30% write                              │
│     • 4KB blocks, queue depth 16                            │
│     • Direct I/O, libaio engine                             │
│                                                              │
│  3. Cycle 8 volumes (parallel batches)                      │
│     • Unmount (if formatted)                                │
│     • blkdiscard                                            │
│     • Delete volumes                                        │
│     • Recreate volumes                                      │
│     • Format and mount (if formatted)                       │
│                                                              │
│  4. Stop I/O workload                                       │
│                                                              │
│  5. Capture I/O stats (after)                               │
│                                                              │
│  6. Calculate deltas and aggregates                         │
│                                                              │
│  7. Log statistics and print summary                        │
│                                                              │
│  Repeat until max hours/iterations reached                  │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│                   Cleanup Phase                              │
│  • Stop all I/O processes                                   │
│  • Unmount formatted volumes                                │
│  • Remove thin volumes                                      │
│  • Remove thin pool                                         │
│  • Remove VG and PVs                                        │
└─────────────────────────────────────────────────────────────┘
```

### I/O Statistics Collection

**Sources**: `/sys/block/*/stat` files

**Metrics Captured**:
- Read operations and bytes
- Write operations and bytes
- Discard operations and bytes
- Flush operations

**Collection Points**:
- Before each iteration
- After each iteration
- Delta (after - before)
- Aggregate (cumulative since start)

**Devices Monitored**:
- All input drives
- Thin pool device mapper device

## Configuration Options

### Command-Line Parameters

| Parameter | Description | Default | Range |
|-----------|-------------|---------|-------|
| `-d, --drives` | Drives (required) | - | Comma-separated |
| `-p, --parallel-deletes` | Parallel deletes | 2 | 1-8 |
| `-h, --max-hours` | Max runtime hours | 0 | 0+ (0=indefinite) |
| `-i, --max-iterations` | Max iterations | 0 | 0+ (0=indefinite) |
| `-m, --metadata-size` | Metadata size | 15G | Size string |
| `-c, --capacity-percent` | Pool capacity % | 50 | 1-100 |
| `-n, --num-volumes` | Number of volumes | 16 | 2+ |
| `-v, --volume-mode` | Volume mode | raw | raw, formatted |
| `-l, --log-dir` | Log directory | ./thin_pool_stress_logs | Path |
| `--vg-name` | VG name | stress_vg | String |
| `--pool-name` | Pool name | stress_pool | String |

### Thin Pool Configuration

**Automatically Configured**:
- `--discards passdown`: Discard requests passed to underlying devices
- `--zero n`: Skip zeroing of new blocks (faster provisioning)

**Metadata**: Separate 15G LV (configurable)
**Data**: Remaining space in VG

## Output Files

### Log Directory Structure
```
thin_pool_stress_logs/
├── stress_test_20260210_143022.log      # Main execution log
├── stats_20260210_143022.log            # CSV statistics
├── iostat_20260210_143022.log           # I/O statistics
├── fio_vol_1_iter_1.log                 # FIO output per volume/iteration
├── fio_vol_2_iter_1.log
├── ...
└── analysis_report.txt                  # Generated by analysis script
```

### Statistics Log Format
```csv
Iteration,Runtime(s),Creates,Deletes,Discards,Pool_Data_Used(%),Pool_Meta_Used(%)
1,45,16,8,8,12.5,2.3
2,92,24,16,16,15.2,2.8
```

### I/O Statistics Log Format
```csv
Iteration,Phase,Device,Read_Ops,Read_Bytes,Write_Ops,Write_Bytes,Discard_Ops,Discard_Bytes,Flush_Ops
1,before,/dev/sdb,1000,4096000,2000,8192000,0,0,10
1,after,/dev/sdb,1500,6144000,3000,12288000,100,1048576000,15
1,delta,/dev/sdb,500,2048000,1000,4096000,100,1048576000,5
1,aggregate,ALL,500,2048000,1000,4096000,100,1048576000,5
```

## Use Cases

### 1. Thin Pool Validation
**Scenario**: Verify thin pool functionality before production use
**Configuration**: Quick test (30 min), 2 parallel deletes
```bash
sudo ./thin_pool_stress_test.sh -d /dev/sdb,/dev/sdc -p 2 -h 0.5
```

### 2. Performance Benchmarking
**Scenario**: Measure thin pool performance under load
**Configuration**: Standard test (4 hours), 4 parallel deletes
```bash
sudo ./thin_pool_stress_test.sh -d /dev/sdb,/dev/sdc -p 4 -h 4
```

### 3. Stress Testing
**Scenario**: Push thin pool to limits
**Configuration**: High stress (8 hours), 8 parallel deletes, 80% capacity
```bash
sudo ./thin_pool_stress_test.sh -d /dev/sdb,/dev/sdc,/dev/sdd -p 8 -h 8 -c 80
```

### 4. Stability Testing
**Scenario**: Long-term reliability validation
**Configuration**: 7 days, 2 parallel deletes
```bash
sudo ./thin_pool_stress_test.sh -d /dev/sdb,/dev/sdc -p 2 -h 168
```

### 5. Filesystem Testing
**Scenario**: Test with actual filesystems
**Configuration**: Formatted mode, 4 hours
```bash
sudo ./thin_pool_stress_test.sh -d /dev/sdb,/dev/sdc -p 4 -h 4 -v formatted
```

## Monitoring

### Real-Time Monitoring Commands

**Pool Usage**:
```bash
watch -n 5 'sudo lvs -o +data_percent,metadata_percent stress_vg/stress_pool'
```

**I/O Statistics**:
```bash
iostat -x 5 /dev/sdb /dev/sdc
```

**System Resources**:
```bash
htop
```

**Disk Space** (formatted mode):
```bash
df -h /mnt/thin_vol_*
```

## Safety Features

### Automatic Cleanup
- Triggered on: Normal exit, Ctrl+C, SIGTERM
- Stops: All I/O processes
- Unmounts: All formatted volumes
- Removes: Thin volumes, thin pool, VG, PVs

### Input Validation
- Drive existence and type checking
- Drive mount status verification
- Parameter range validation
- Volume count validation

### Error Handling
- Graceful failure on errors
- Detailed error logging
- Safe cleanup on failure

## Performance Considerations

### FIO Workload
- **Pattern**: 70% read, 30% write (realistic mixed workload)
- **Block Size**: 4KB (common database/application size)
- **Queue Depth**: 16 (moderate concurrency)
- **Engine**: libaio (Linux native async I/O)
- **Direct I/O**: Bypasses page cache

### Optimization Tips
1. Use multiple drives for better performance
2. Adjust parallel deletes based on system capacity
3. Monitor system resources during test
4. Use raw mode for maximum I/O performance
5. Use formatted mode for realistic testing

## Troubleshooting

### Common Issues

**Drive in use**: Unmount or use different drive
**Insufficient space**: Use smaller metadata or larger drives
**FIO not found**: Install fio package
**Permission denied**: Run with sudo
**OOM errors**: Reduce parallel operations or add memory

### Debug Mode
```bash
bash -x ./thin_pool_stress_test.sh -d /dev/sdb,/dev/sdc -p 4
```

## Files Summary

| File | Purpose | Lines |
|------|---------|-------|
| `thin_pool_stress_test.sh` | Main stress test script | ~830 |
| `thin_pool_test_scenarios.sh` | Pre-configured scenarios | ~180 |
| `analyze_thin_pool_logs.sh` | Log analysis tool | ~150 |
| `README_THIN_POOL_STRESS.md` | Complete documentation | ~350 |
| `QUICKSTART.md` | Quick start guide | ~250 |
| `THIN_POOL_STRESS_SUMMARY.md` | This summary | ~150 |

**Total**: ~1,900 lines of code and documentation

## Next Steps

1. Review documentation
2. Install dependencies
3. Prepare test drives
4. Run quick validation test
5. Analyze results
6. Run longer tests as needed
7. Document findings

## Support

For issues or questions:
1. Check troubleshooting section
2. Review log files
3. Enable debug mode
4. Verify system requirements

