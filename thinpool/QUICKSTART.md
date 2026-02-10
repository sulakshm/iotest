# LVM Thin Pool Stress Test - Quick Start Guide

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

**Option A: Interactive Menu (Recommended for First Time)**
```bash
sudo ./thin_pool_test_scenarios.sh
```

**Option B: Direct Command**
```bash
# Quick 30-minute test
sudo ./thin_pool_stress_test.sh -d /dev/sdb,/dev/sdc -p 2 -h 0.5

# Standard 4-hour test
sudo ./thin_pool_stress_test.sh -d /dev/sdb,/dev/sdc -p 4 -h 4

# High stress test
sudo ./thin_pool_stress_test.sh -d /dev/sdb,/dev/sdc -p 8 -h 8
```

### Step 3: Analyze Results
```bash
sudo ./analyze_thin_pool_logs.sh ./thin_pool_stress_logs
```

## Common Test Scenarios

### 1. Quick Validation Test (30 minutes)
```bash
sudo ./thin_pool_stress_test.sh \
  -d /dev/sdb,/dev/sdc \
  -p 2 \
  -h 0.5 \
  -n 16 \
  -c 50 \
  -v raw
```

**Use Case**: Verify setup and basic functionality

### 2. Standard Stress Test (4 hours)
```bash
sudo ./thin_pool_stress_test.sh \
  -d /dev/sdb,/dev/sdc \
  -p 4 \
  -h 4 \
  -n 16 \
  -c 50 \
  -v raw
```

**Use Case**: Regular stress testing

### 3. High Stress Test (8 hours)
```bash
sudo ./thin_pool_stress_test.sh \
  -d /dev/sdb,/dev/sdc,/dev/sdd \
  -p 8 \
  -h 8 \
  -n 16 \
  -c 80 \
  -v raw
```

**Use Case**: Maximum stress with high parallelism

### 4. Formatted Filesystem Test (4 hours)
```bash
sudo ./thin_pool_stress_test.sh \
  -d /dev/sdb,/dev/sdc \
  -p 4 \
  -h 4 \
  -n 16 \
  -c 50 \
  -v formatted
```

**Use Case**: Test with actual filesystems

### 5. Long-Term Stability Test (7 days)
```bash
sudo ./thin_pool_stress_test.sh \
  -d /dev/sdb,/dev/sdc \
  -p 2 \
  -h 168 \
  -n 16 \
  -c 50 \
  -v raw
```

**Use Case**: Long-term reliability testing

### 6. Large Pool Test (32 volumes)
```bash
sudo ./thin_pool_stress_test.sh \
  -d /dev/sdb,/dev/sdc,/dev/sdd,/dev/sde \
  -p 6 \
  -h 8 \
  -n 32 \
  -c 60 \
  -v raw \
  -m 20G
```

**Use Case**: Test with larger configurations

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

## Example Workflow

```bash
# 1. Prepare environment
cd pxlens/ioload
chmod +x *.sh

# 2. Run quick validation
sudo ./thin_pool_stress_test.sh -d /dev/sdb,/dev/sdc -p 2 -h 0.5

# 3. Analyze results
sudo ./analyze_thin_pool_logs.sh ./thin_pool_stress_logs

# 4. If successful, run longer test
sudo ./thin_pool_stress_test.sh -d /dev/sdb,/dev/sdc -p 4 -h 4

# 5. Analyze again
sudo ./analyze_thin_pool_logs.sh ./thin_pool_stress_logs

# 6. Archive logs
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
| `-n` | Number of volumes | 16 (default), 32 (large) |
| `-c` | Capacity % | 50 (safe), 80 (stress) |
| `-v` | Volume mode | raw (faster), formatted (realistic) |

## Next Steps

After successful testing:
1. Review all log files
2. Compare results across different configurations
3. Identify any performance bottlenecks
4. Document findings
5. Adjust parameters for specific use cases

