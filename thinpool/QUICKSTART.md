# LVM Thin Pool Stress Test - Quick Start Guide

## Purpose

This tool is designed to **reproduce the "space map common: unable to decrement block" error** - a critical thin pool refcount corruption issue caused by:
- Discard/TRIM race conditions
- Metadata exhaustion
- Concurrent I/O and delete operations

## Prerequisites

### 1. Install Required Packages

**Ubuntu/Debian:**
```bash
sudo apt-get update
sudo apt-get install -y lvm2 fio util-linux
```

**RHEL/CentOS:**
```bash
sudo yum install -y lvm2 fio util-linux
```

### 2. Prepare Block Devices

Identify available drives:
```bash
lsblk -d
```

**⚠️ WARNING**: The test will **DESTROY ALL DATA** on the specified drives!

## Quick Start (3 Steps)

### Step 1: Make Scripts Executable
```bash
cd pxlens/ioload
chmod +x *.sh
```

### Step 2: Run a Test Scenario

**Option A: Interactive Menu (Recommended)**
```bash
sudo ./thin_pool_test_scenarios.sh
```

**Option B: Direct Command - Race Mode (Default)**
```bash
# Quick race test (30 min) - concurrent I/O + discard
sudo ./thin_pool_stress_test.sh -d /dev/sdb,/dev/sdc -p 4 -h 0.5

# Maximum stress - best chance to trigger corruption
sudo ./thin_pool_stress_test.sh -d /dev/sdb,/dev/sdc -p 8 -c 95 --metadata-stress

# Metadata exhaustion test
sudo ./thin_pool_stress_test.sh -d /dev/sdb,/dev/sdc -p 6 -c 90 --metadata-stress -h 4
```

### Step 3: Analyze Results
```bash
# Analyze logs and check for refcount errors
sudo ./analyze_thin_pool_logs.sh ./thin_pool_stress_logs

# Also check current kernel messages
sudo ./analyze_thin_pool_logs.sh ./thin_pool_stress_logs --check-kernel
```

## Recommended Test Scenarios (for Reproducing Corruption)

### 1. Metadata Exhaustion Test (MOST LIKELY TO TRIGGER)
```bash
sudo ./thin_pool_stress_test.sh \
  -d /dev/sdb,/dev/sdc \
  -p 6 \
  -h 4 \
  -n 24 \
  -c 90 \
  --metadata-stress
```
**Purpose**: Uses minimal 512M metadata to stress tmeta to near-100%

### 2. Maximum Race Condition Stress
```bash
sudo ./thin_pool_stress_test.sh \
  -d /dev/sdb,/dev/sdc \
  -p 8 \
  -h 8 \
  -n 16 \
  -c 95 \
  --snapshot-io-duration 60
```
**Purpose**: Maximum parallel operations with concurrent I/O and discard

### 3. Quick Race Validation (30 minutes)
```bash
sudo ./thin_pool_stress_test.sh \
  -d /dev/sdb,/dev/sdc \
  -p 4 \
  -h 0.5 \
  -c 80
```
**Purpose**: Fast validation that race mode is working

### 4. Formatted + Fstrim Race Test
```bash
sudo ./thin_pool_stress_test.sh \
  -d /dev/sdb,/dev/sdc \
  -p 4 \
  -h 4 \
  -v formatted \
  --fstrim-mode
```
**Purpose**: Test with mounted filesystems using fstrim

### 5. Baseline Test (No Race - for Comparison)
```bash
sudo ./thin_pool_stress_test.sh \
  -d /dev/sdb,/dev/sdc \
  -p 4 \
  -h 4 \
  --no-race-mode
```
**Purpose**: Sequential operations for baseline comparison

### 6. Long-Term Stability with Race Mode
```bash
sudo ./thin_pool_stress_test.sh \
  -d /dev/sdb,/dev/sdc \
  -p 4 \
  -h 168 \
  -c 80
```
**Purpose**: 7-day test with race conditions enabled

## Monitoring During Test

### Terminal 1: Run the test
```bash
sudo ./thin_pool_stress_test.sh -d /dev/sdb,/dev/sdc -p 4 -h 4
```

### Terminal 2: Monitor pool usage
```bash
watch -n 5 'sudo lvs -o +data_percent,metadata_percent stress_vg/stress_pool'
```

### Terminal 3: Monitor I/O
```bash
iostat -x 5 /dev/sdb /dev/sdc
```

### Terminal 4: Monitor system resources
```bash
htop
```

## Understanding Output

### Console Output
Each iteration shows:
- Runtime since test start
- Total creates/deletes/discards
- Pool data and metadata usage
- Aggregate I/O statistics (since start)
- Current iteration I/O statistics

### Log Files

**Location**: `./thin_pool_stress_logs/` (default)

**Files**:
1. `stress_test_YYYYMMDD_HHMMSS.log` - Main execution log
2. `stats_YYYYMMDD_HHMMSS.log` - CSV statistics per iteration
3. `iostat_YYYYMMDD_HHMMSS.log` - Detailed I/O statistics
4. `kernel_errors.log` - **Thin pool kernel errors (refcount corruption)**
5. `metadata_warnings.log` - **Metadata exhaustion events**

## Stopping the Test

### Graceful Stop
Press `Ctrl+C` - The script will automatically clean up:
- Stop I/O processes
- Unmount filesystems
- Remove LVM structures
- Save final statistics

### Force Stop (Emergency)
```bash
# Find the process
ps aux | grep thin_pool_stress

# Kill it
sudo pkill -9 -f thin_pool_stress

# Manual cleanup
sudo umount /mnt/thin_vol_* 2>/dev/null
sudo lvremove -f stress_vg
sudo vgremove -f stress_vg
sudo pvremove -f /dev/sdb /dev/sdc
```

## Analyzing Results

### Quick Analysis
```bash
sudo ./analyze_thin_pool_logs.sh ./thin_pool_stress_logs
```

### Check for Refcount Corruption
```bash
# Analyze with kernel message check
sudo ./analyze_thin_pool_logs.sh ./thin_pool_stress_logs --check-kernel

# Check kernel errors log directly
cat thin_pool_stress_logs/kernel_errors.log

# Check for the target error in dmesg
sudo dmesg | grep -i "unable to decrement"
sudo dmesg | grep -i "space map"
```

### Check Metadata Exhaustion
```bash
# View metadata warnings
cat thin_pool_stress_logs/metadata_warnings.log

# Check for critical events
grep "CRITICAL" thin_pool_stress_logs/metadata_warnings.log
```

### Manual Analysis

**View statistics:**
```bash
column -t -s',' thin_pool_stress_logs/stats_*.log | less
```

**Check aggregate I/O:**
```bash
grep "aggregate" thin_pool_stress_logs/iostat_*.log
```

**Find errors:**
```bash
grep -i error thin_pool_stress_logs/stress_test_*.log
```

## Troubleshooting

### Issue: "Drive is currently mounted"
```bash
# Unmount the drive
sudo umount /dev/sdb

# Or find what's using it
lsblk /dev/sdb
```

### Issue: "Permission denied"
```bash
# Run with sudo
sudo ./thin_pool_stress_test.sh -d /dev/sdb,/dev/sdc -p 4
```

### Issue: "fio: command not found"
```bash
# Install fio
sudo apt-get install fio  # Ubuntu/Debian
sudo yum install fio      # RHEL/CentOS
```

### Issue: Test hangs or crashes
```bash
# Check system logs
sudo dmesg | tail -50
sudo journalctl -xe

# Check for OOM killer
sudo grep -i "out of memory" /var/log/syslog
```

## Best Practices

1. **Start Small**: Begin with 2 drives and low parallelism
2. **Monitor First Run**: Watch all metrics during first test
3. **Save Logs**: Keep logs for comparison and analysis
4. **Test Incrementally**: Increase stress gradually
5. **Verify Cleanup**: Check that LVM structures are removed after test
6. **Use Dedicated Drives**: Never use drives with important data

## Example Workflow (Reproducing Refcount Corruption)

```bash
# 1. Prepare environment
cd pxlens/ioload
chmod +x *.sh

# 2. Run quick race test to validate setup
sudo ./thin_pool_stress_test.sh -d /dev/sdb,/dev/sdc -p 4 -h 0.5

# 3. Analyze results - check for kernel errors
sudo ./analyze_thin_pool_logs.sh ./thin_pool_stress_logs --check-kernel

# 4. Run metadata exhaustion test (most likely to trigger corruption)
sudo ./thin_pool_stress_test.sh -d /dev/sdb,/dev/sdc -p 6 -c 90 --metadata-stress -h 4

# 5. Analyze for refcount errors
sudo ./analyze_thin_pool_logs.sh ./thin_pool_stress_logs --check-kernel --verbose

# 6. Check kernel messages directly
sudo dmesg | grep -i "unable to decrement\|space map"

# 7. Archive logs
tar -czf thin_pool_test_$(date +%Y%m%d).tar.gz thin_pool_stress_logs/
```

## Getting Help

### Check Script Help
```bash
./thin_pool_stress_test.sh --help
```

### Enable Debug Mode
```bash
bash -x ./thin_pool_stress_test.sh -d /dev/sdb,/dev/sdc -p 4
```

### Common Parameters

| Parameter | Description | Recommended Values |
|-----------|-------------|-------------------|
| `-d` | Drives | 2-4 drives |
| `-p` | Parallel deletes | 2-4 for stability, 6-8 for stress |
| `-h` | Max hours | 0.5 (test), 4 (standard), 24+ (long) |
| `-n` | Number of volumes | 16 (default), 24 (metadata stress) |
| `-c` | Capacity % | 80 (default), 90-95 (stress) |
| `-v` | Volume mode | raw (faster), formatted (realistic) |

### Race Condition Parameters

| Parameter | Description | Purpose |
|-----------|-------------|---------|
| `--race-mode enabled` | Concurrent I/O+discard | Default - triggers race conditions |
| `--no-race-mode` | Sequential operations | Baseline comparison |
| `--metadata-stress` | Use 512M metadata | Stress tmeta to exhaustion |
| `--fstrim-mode` | Use fstrim on mounted fs | Test filesystem-level TRIM |
| `--snapshot-io-duration N` | I/O duration in seconds | Longer = more race opportunities |

## Next Steps

After successful testing:
1. Check `kernel_errors.log` for "unable to decrement block" errors
2. Check `metadata_warnings.log` for exhaustion events
3. Compare race mode vs baseline results
4. If no corruption detected, increase stress parameters
5. Document findings and kernel versions tested

