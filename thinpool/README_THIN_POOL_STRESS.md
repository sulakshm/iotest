# LVM Thin Pool Stress Test

## Overview

This script performs comprehensive stress testing of LVM thin pools, specifically designed to **reproduce the "space map common: unable to decrement block" refcount corruption error**.

### Target Issue
The kernel error occurs when:
- **Discard/TRIM Race Conditions**: Concurrent discard and write/delete operations hit the same block
- **Metadata Exhaustion**: tmeta fills to 100%, corrupting B-tree transactions
- **Unsafe Caching**: Partial metadata writes during power failure

### How It Works
- Creates a thin pool with configurable metadata size
- Provisions multiple thin volumes (default: 16)
- Runs continuous I/O workload on half the volumes
- **Race Mode (default)**: Runs I/O and discard **concurrently** to trigger race conditions
- Cycles (snapshot → I/O → discard → delete) the other half with configurable parallelism
- Monitors for kernel errors and metadata exhaustion

## Features

### Core Functionality
- ✅ **Configurable Thin Pool**: 15G metadata (default) or 512M (metadata stress mode)
- ✅ **Parallel Volume Operations**: 1-8 volumes deleted/recreated simultaneously
- ✅ **Race Mode**: Concurrent I/O and discard operations (enabled by default)
- ✅ **Snapshot Operations**: Create snapshot before delete to stress COW refcounts
- ✅ **Aggressive Discard**: Multiple rapid partial discards per volume
- ✅ **Metadata Stress**: Option to use minimal metadata for exhaustion testing
- ✅ **Kernel Error Detection**: Monitors dmesg for thin pool errors

### Statistics Collection
- ✅ **Per-Iteration I/O Stats**: Read/Write/Discard/Flush operations and bytes
- ✅ **Aggregate Statistics**: Cumulative I/O since test start
- ✅ **Pool Usage Tracking**: Data and metadata utilization percentages (continuous monitoring)
- ✅ **Kernel Error Logging**: Captures "unable to decrement block" errors
- ✅ **Metadata Exhaustion Alerts**: Warns at 80%, critical at 95%

### Runtime Control
- ✅ **Indefinite Mode**: Run until manually stopped
- ✅ **Time-Limited**: Maximum runtime in hours
- ✅ **Iteration-Limited**: Maximum number of cycles
- ✅ **Graceful Cleanup**: Automatic cleanup on exit/interrupt

## Requirements

### System Requirements
- Linux system with LVM2 utilities
- Root/sudo access
- Available block devices (not in use)

### Software Dependencies
```bash
# Required packages
apt-get install -y lvm2 fio util-linux

# Or on RHEL/CentOS
yum install -y lvm2 fio util-linux
```

### Minimum Resources
- **Drives**: At least 1 block device (2+ recommended)
- **Space**: Minimum 20GB per drive
- **Memory**: 2GB+ recommended for I/O operations

## Usage

### Basic Syntax
```bash
./thin_pool_stress_test.sh -d <drives> [options]
```

### Common Examples

#### 1. Run indefinitely with 4 parallel deletes
```bash
./thin_pool_stress_test.sh -d /dev/sdb,/dev/sdc -p 4
```

#### 2. Run for 24 hours with formatted volumes
```bash
./thin_pool_stress_test.sh -d /dev/sdb,/dev/sdc,/dev/sdd -h 24 -v formatted
```

#### 3. Run 100 iterations with 8 parallel deletes
```bash
./thin_pool_stress_test.sh -d /dev/sdb,/dev/sdc -i 100 -p 8
```

#### 4. Custom configuration
```bash
./thin_pool_stress_test.sh \
  -d /dev/sdb,/dev/sdc,/dev/sdd \
  -p 6 \
  -h 48 \
  -m 20G \
  -c 60 \
  -n 32 \
  -v raw \
  -l /var/log/thin_pool_stress
```

## Command-Line Options

### Required Options
| Option | Description | Example |
|--------|-------------|---------|
| `-d, --drives` | Comma-separated list of drives | `-d /dev/sdb,/dev/sdc` |

### Basic Options
| Option | Description | Default | Range/Values |
|--------|-------------|---------|--------------|
| `-p, --parallel-deletes` | Number of parallel volume deletes | 2 | 1-8 |
| `-h, --max-hours` | Maximum runtime in hours (0=indefinite) | 0 | 0+ |
| `-i, --max-iterations` | Maximum iterations (0=indefinite) | 0 | 0+ |
| `-m, --metadata-size` | Metadata volume size | 15G | Size string |
| `-c, --capacity-percent` | Pool capacity to use for volumes | 80 | 1-100 |
| `-n, --num-volumes` | Total number of thin volumes | 16 | 2+ |
| `-v, --volume-mode` | Volume mode | raw | raw, formatted |
| `-l, --log-dir` | Log directory | ./thin_pool_stress_logs | Path |
| `--vg-name` | Volume group name | stress_vg | String |
| `--pool-name` | Thin pool name | stress_pool | String |

### Race Condition Options (for reproducing refcount corruption)
| Option | Description | Default |
|--------|-------------|---------|
| `--race-mode MODE` | Enable/disable concurrent I/O+discard | enabled |
| `--no-race-mode` | Shortcut to disable race mode | - |
| `--metadata-stress` | Use minimal 512M metadata (stress tmeta) | disabled |
| `--fstrim-mode` | Use fstrim on mounted filesystems | disabled |
| `--snapshot-io-duration SECS` | I/O duration during snapshot phase | 30 |

## Output and Logs

### Log Files

The script creates the following log files in the log directory:

#### 1. Main Log (`stress_test_YYYYMMDD_HHMMSS.log`)
- General execution log
- Iteration progress
- Error messages

#### 2. Statistics Log (`stats_YYYYMMDD_HHMMSS.log`)
Format:
```
Iteration,Runtime(s),Creates,Deletes,Discards,Pool_Data_Used(%),Pool_Meta_Used(%)
1,45,16,8,8,12.5,2.3
2,92,24,16,16,15.2,2.8
```

#### 3. I/O Statistics Log (`iostat_YYYYMMDD_HHMMSS.log`)
Format:
```
Iteration,Phase,Device,Read_Ops,Read_Bytes,Write_Ops,Write_Bytes,Discard_Ops,Discard_Bytes,Flush_Ops
1,before,/dev/sdb,1000,4096000,2000,8192000,0,0,10
1,after,/dev/sdb,1500,6144000,3000,12288000,100,1048576000,15
1,delta,/dev/sdb,500,2048000,1000,4096000,100,1048576000,5
1,aggregate,ALL,500,2048000,1000,4096000,100,1048576000,5
```

#### 4. Kernel Errors Log (`kernel_errors.log`)
**Critical for detecting refcount corruption!**
```
device-mapper: thin: space map common: unable to decrement block
device-mapper: thin: Couldn't decrement superblock
```

#### 5. Metadata Warnings Log (`metadata_warnings.log`)
```
Mon Feb 10 12:45:23 2026: METADATA CRITICAL - 96.2%
Mon Feb 10 12:46:15 2026: METADATA CRITICAL - 98.1%
```

### Console Output

Each iteration displays:
```
==========================================
Iteration 1 Summary
==========================================
Runtime: 45s
Total Creates: 16
Total Deletes: 8
Total Discards: 8
Pool Data Used: 12.5%
Pool Metadata Used: 2.3%
Aggregate I/O (since start):
  Read: 500 ops, 2 MB
  Write: 1000 ops, 4 MB
  Discard: 100 ops, 1000 MB
  Flush: 5 ops
This Iteration I/O:
  Read: 500 ops, 2 MB
  Write: 1000 ops, 4 MB
  Discard: 100 ops, 1000 MB
  Flush: 5 ops
==========================================
```

## How It Works

### Test Flow

1. **Setup Phase**
   - Validate input parameters
   - Create physical volumes on specified drives
   - Create volume group
   - Create thin pool with metadata and data LVs
   - Configure thin pool (passdown discard, no zeroing)

2. **Volume Creation**
   - Create N thin volumes (default: 16)
   - Calculate volume size based on pool capacity percentage (default: 80%)
   - Format volumes if mode=formatted

3. **Iteration Loop** (until max hours/iterations reached)
   - **Capture I/O stats (before)**
   - **Start I/O workload** on first 8 volumes (FIO)
   - **Cycle volumes** (second 8 volumes) - **NEW 6-STEP SEQUENCE**:
     1. **Take snapshot** of the volume
     2. **Write I/O** for configurable duration (triggers COW)
     3. **Race Mode**: Run I/O and discard **concurrently**
     4. **Delete volume** (with background discard race)
     5. **Delete snapshot**
     6. **Recreate volume**
   - **Check for kernel errors** (dmesg monitoring)
   - **Stop I/O workload**
   - **Capture I/O stats (after)**
   - **Log statistics and warnings**

4. **Cleanup Phase**
   - Stop all I/O processes
   - Unmount formatted volumes
   - Remove thin volumes
   - Remove thin pool
   - Remove volume group
   - Remove physical volumes

### Race Mode Details (Default: Enabled)

The race mode is designed to trigger the "unable to decrement block" error:

1. **Concurrent I/O + Discard**
   - FIO writes random data while blkdiscard runs on same volume
   - Queue depth 32 for maximum concurrency
   - Partial discards (4 regions per volume) to increase race opportunities

2. **Aggressive Discard**
   - 5 rapid discard iterations per volume
   - Discards on both volume AND snapshot simultaneously
   - Background discard during lvremove

3. **Metadata Stress Mode** (optional)
   - Uses 512M metadata instead of 15G
   - Forces tmeta to approach 100% usage
   - Most likely to trigger refcount corruption

### I/O Workload Details

FIO configuration per volume:
- **Pattern**: Random write (100% for race mode, 70/30 for baseline)
- **Block Size**: 4KB
- **I/O Engine**: libaio
- **Queue Depth**: 32 (race mode) or 16 (baseline)
- **Direct I/O**: Enabled
- **Size**: 50% of volume (race mode) or 90% (baseline)
- **Runtime**: Configurable (default 30s per cycle)

## Safety and Cleanup

### Automatic Cleanup

The script automatically cleans up on:
- Normal exit
- Ctrl+C (SIGINT)
- SIGTERM

Cleanup includes:
- Stopping all I/O processes
- Unmounting filesystems
- Removing LVM structures
- Removing physical volumes

### Manual Cleanup

If the script crashes, manually clean up:
```bash
# Stop any running fio processes
pkill -9 fio

# Unmount volumes
umount /mnt/thin_vol_* 2>/dev/null

# Remove LVM structures
lvremove -f stress_vg
vgremove -f stress_vg
pvremove -f /dev/sdb /dev/sdc
```

## Troubleshooting

### Common Issues

#### 1. Drive in use
```
ERROR: Drive /dev/sdb is currently mounted
```
**Solution**: Unmount the drive or use a different drive

#### 2. Insufficient space
```
ERROR: Insufficient space for metadata volume
```
**Solution**: Use smaller metadata size or larger drives

#### 3. FIO not found
```
ERROR: fio: command not found
```
**Solution**: Install fio package

#### 4. Permission denied
```
ERROR: Permission denied
```
**Solution**: Run with sudo/root privileges

### Debug Mode

Enable verbose output:
```bash
bash -x ./thin_pool_stress_test.sh -d /dev/sdb,/dev/sdc -p 4
```

## Performance Tuning

### Optimize for Maximum Stress

```bash
./thin_pool_stress_test.sh \
  -d /dev/sdb,/dev/sdc,/dev/sdd,/dev/sde \
  -p 8 \
  -n 32 \
  -c 80 \
  -v raw
```

### Optimize for Long-Term Stability

```bash
./thin_pool_stress_test.sh \
  -d /dev/sdb,/dev/sdc \
  -p 2 \
  -h 168 \
  -n 16 \
  -c 50 \
  -v formatted
```

## Monitoring

### Real-Time Monitoring

In separate terminals:

```bash
# Watch pool usage
watch -n 5 'lvs -o +data_percent,metadata_percent stress_vg/stress_pool'

# Monitor I/O
iostat -x 5 /dev/sdb /dev/sdc

# Watch disk space
df -h /mnt/thin_vol_*

# Monitor system resources
htop
```

### Log Analysis

```bash
# View iteration statistics
column -t -s',' thin_pool_stress_logs/stats_*.log

# Analyze I/O patterns
grep "aggregate" thin_pool_stress_logs/iostat_*.log

# Check for errors
grep -i error thin_pool_stress_logs/stress_test_*.log
```

## Best Practices

1. **Use dedicated drives**: Don't use drives with important data
2. **Monitor resources**: Watch CPU, memory, and I/O during test
3. **Start small**: Begin with 2 drives and low parallelism
4. **Increase gradually**: Scale up after verifying stability
5. **Save logs**: Keep logs for analysis and comparison
6. **Test different modes**: Try both raw and formatted modes
7. **Vary parameters**: Test different parallel delete counts

## Known Limitations

- Maximum 8 parallel deletes (can be increased by modifying script)
- Requires root/sudo access
- Only supports ext4 for formatted mode
- FIO workload is fixed (can be customized in script)

## Contributing

To modify the script:
1. Edit FIO parameters in `start_io_workload()` function
2. Adjust thin pool settings in `setup_thin_pool()` function
3. Customize statistics in `print_iteration_summary()` function

## License

This script is part of the PXLens project.

## Support

For issues or questions:
1. Check the troubleshooting section
2. Review log files for error messages
3. Verify system requirements are met
4. Test with minimal configuration first

