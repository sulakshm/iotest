# LVM Thin Pool Stress Test - Quick Reference

## 🎯 Purpose

Reproduce **"space map common: unable to decrement block"** refcount corruption error.

## What's New (Latest Update)

### Race Condition Mode (Default: ENABLED)
- **Concurrent I/O + Discard**: Runs FIO and blkdiscard simultaneously
- **Aggressive Discard**: Multiple rapid partial discards per volume
- **Snapshot Discards**: Discard on both volume AND snapshot
- **Delete Race**: Background discard during lvremove

### Metadata Exhaustion Testing
- **`--metadata-stress`**: Use 512M metadata instead of 15G
- Forces tmeta to approach 100% - most likely to trigger corruption

### Kernel Error Detection
- Monitors dmesg for "unable to decrement block" errors
- Logs to `kernel_errors.log` and `metadata_warnings.log`

## Quick Start

### Recommended: Metadata Exhaustion Test (Most Likely to Trigger)
```bash
sudo ./thin_pool_stress_test.sh -d /dev/sdb,/dev/sdc -p 6 -c 90 --metadata-stress -h 4
```

### Quick Race Test (30 min validation)
```bash
sudo ./thin_pool_stress_test.sh -d /dev/sdb,/dev/sdc -p 4 -h 0.5
```

### Maximum Stress Test
```bash
sudo ./thin_pool_stress_test.sh -d /dev/sdb,/dev/sdc -p 8 -c 95 --snapshot-io-duration 60 -h 8
```

### Baseline Test (No Race - for Comparison)
```bash
sudo ./thin_pool_stress_test.sh -d /dev/sdb,/dev/sdc -p 4 -h 4 --no-race-mode
```

## Volume Cycling Sequence (Race Mode)

```
For each volume selected for deletion:

1. Take Snapshot
   └─ Monitor pool usage (metadata increase)

2. RACE MODE: Concurrent I/O + Discard
   ├─ Start FIO (randwrite, 32 queue depth)
   ├─ Wait 1s for I/O to start
   ├─ Issue aggressive discards WHILE I/O RUNS:
   │   ├─ 5 rapid iterations
   │   ├─ 4 partial regions per volume
   │   └─ Discard on snapshot too
   └─ Wait for both to complete

3. Delete Volume (with race)
   ├─ Background discard during delete
   └─ lvremove volume

4. Delete Snapshot
   └─ lvremove snapshot

5. Recreate Volume
   ├─ lvcreate new volume
   └─ Format if needed

6. Check for Kernel Errors
   └─ Monitor dmesg for "unable to decrement"
```

## Command-Line Parameters

### Race Condition Parameters
| Parameter | Default | Description |
|-----------|---------|-------------|
| `--race-mode MODE` | enabled | `enabled` or `disabled` |
| `--no-race-mode` | - | Shortcut to disable race mode |
| `--metadata-stress` | disabled | Use 512M metadata (stress tmeta) |
| `--fstrim-mode` | disabled | Use fstrim on mounted filesystems |
| `--snapshot-io-duration` | 30 | Seconds of I/O during snapshot phase |

### Basic Parameters
| Parameter | Default | Description |
|-----------|---------|-------------|
| `-d, --drives` | required | Comma-separated drives |
| `-p, --parallel-deletes` | 2 | Parallel deletes (1-8) |
| `-h, --max-hours` | 0 | Max hours (0=indefinite) |
| `-c, --capacity-percent` | 80 | Pool capacity % |
| `-n, --num-volumes` | 16 | Number of volumes |
| `-m, --metadata-size` | 15G | Metadata size (512M with --metadata-stress) |
| `-v, --volume-mode` | raw | `raw` or `formatted` |

## Monitoring Pool Usage

### Real-Time Monitoring
```bash
# Terminal 1: Run test
sudo ./thin_pool_stress_test.sh -d /dev/sdb,/dev/sdc -p 4

# Terminal 2: Watch pool usage
watch -n 2 'sudo lvs -o +data_percent,metadata_percent stress_vg/stress_pool'

# Terminal 3: Watch detailed pool info
watch -n 5 'sudo lvs -a -o +devices,data_percent,metadata_percent stress_vg'
```

### In-Test Monitoring
The script now automatically reports pool usage at each step:
```
[INFO]   Step 1/5: Taking snapshots...
[INFO]   Pool usage before snapshot: 45.2,3.1
[INFO]   Pool usage after snapshot: 48.7,3.5
[INFO]   Step 2/5: Writing I/O for 30s...
[INFO]   Pool usage before I/O: 48.7,3.5
[INFO]   Pool usage after I/O: 52.3,3.8
[INFO]   Step 3/5: Discarding volumes...
[INFO]   Pool usage before discard: 52.3,3.8
[INFO]   Pool usage after discard: 48.1,3.7
```

## Common Scenarios (Make Targets)

### Race Condition Tests (Recommended)
```bash
# Quick race test (30 min)
make test-race DRIVES=/dev/sdb,/dev/sdc

# Metadata exhaustion (BEST CHANCE TO TRIGGER)
make test-metadata-exhaustion DRIVES=/dev/sdb,/dev/sdc

# Maximum stress (8h, 95% capacity)
make test-max-stress DRIVES=/dev/sdb,/dev/sdc,/dev/sdd
```

### Baseline Tests (for Comparison)
```bash
# Baseline without race (4h)
make test-baseline DRIVES=/dev/sdb,/dev/sdc

# Standard test (race enabled)
make test-standard DRIVES=/dev/sdb,/dev/sdc
```

## Checking for Refcount Corruption

### After Test Completes
```bash
# Analyze logs with kernel error check
make analyze-kernel

# Or manually
sudo ./analyze_thin_pool_logs.sh ./thin_pool_stress_logs --check-kernel --verbose
```

### Check Log Files
```bash
# Check kernel error log (TARGET ERROR)
cat thin_pool_stress_logs/kernel_errors.log

# Check for "unable to decrement"
grep -i "unable to decrement" thin_pool_stress_logs/kernel_errors.log

# Check metadata exhaustion
cat thin_pool_stress_logs/metadata_warnings.log
```

### Check Live Kernel Messages
```bash
sudo dmesg | grep -i "unable to decrement\|space map"
```

## Performance Expectations

### With Race Mode
- Each iteration: ~60-90 seconds
- Concurrent I/O + discard creates maximum stress
- Metadata stress mode may cause slow operations near 100%

### Metadata Usage
- **With `--metadata-stress`**: Watch for 95%+ usage
- Pool may become unresponsive at 100% tmeta
- Script alerts at 80% (warning) and 95% (critical)

### Pool Capacity
- **80% default** fills pool quickly
- **90-95%** creates maximum pressure
  ```bash
  sudo ./thin_pool_stress_test.sh -d /dev/sdb,/dev/sdc -c 60
  ```

## Troubleshooting

### Refcount Error Not Triggered
**Symptom**: No kernel errors after test

**Solutions**:
1. Use `--metadata-stress` (512M metadata)
2. Increase capacity to 90-95%
3. Run longer (24+ hours)
4. Increase parallelism to 8

### Pool Metadata Full (Intentional with --metadata-stress)
**Symptom**: Pool becomes unresponsive at 100% tmeta

**Note**: This is expected with `--metadata-stress` and may trigger the target error
```bash
# Check metadata warnings log
cat thin_pool_stress_logs/metadata_warnings.log
```

### Pool Data Full
**Symptom**: Cannot create volumes

**Solution**: Reduce capacity or use fewer volumes
```bash
sudo ./thin_pool_stress_test.sh -d /dev/sdb,/dev/sdc -c 60 -n 12
```

## Best Practices

1. **Run metadata exhaustion test first** - most likely to trigger corruption
2. **Check kernel_errors.log after each run**
3. **Compare race vs baseline** - confirms race conditions are needed
4. **Monitor dmesg in real-time** during tests
5. **Archive logs** for each test run

## Quick Commands

```bash
# Install dependencies
make install

# Check requirements
make check

# Make scripts executable
make permissions

# Run metadata exhaustion test (RECOMMENDED)
make test-metadata-exhaustion DRIVES=/dev/sdb,/dev/sdc

# Run race test
make test-race DRIVES=/dev/sdb,/dev/sdc

# Analyze with kernel check
make analyze-kernel

# Clean up logs
make clean

# Emergency LVM cleanup
make clean-lvm DRIVES=/dev/sdb,/dev/sdc
```

## Success Indicators

When the target error is reproduced:

```
[ERROR] !!! KERNEL ERROR DETECTED - Check dmesg for thin pool errors !!!
```

In `kernel_errors.log`:
```
device-mapper: thin: space map common: unable to decrement block
```

Analysis output:
```
*** TARGET ERROR FOUND: 'unable to decrement block' ***
*** REFCOUNT CORRUPTION SUCCESSFULLY REPRODUCED ***
```

