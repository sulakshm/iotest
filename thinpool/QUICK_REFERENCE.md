# LVM Thin Pool Stress Test - Quick Reference

## What's New (Latest Update)

### 🎯 Key Changes

1. **Default Capacity: 50% → 80%**
   - More aggressive stress testing by default
   - Volumes now use 80% of pool capacity

2. **Snapshot-Based Volume Cycling**
   - Each volume deletion now includes snapshot operations
   - Tests COW (Copy-on-Write) behavior
   - Validates snapshot and discard interactions

3. **Continuous Pool Monitoring**
   - Pool usage (tdata/tmeta) reported at every step
   - Track metadata growth from snapshots
   - Monitor space reclamation from discards

## Quick Start

### Basic Test (80% capacity, with snapshots)
```bash
sudo ./thin_pool_stress_test.sh -d /dev/sdb,/dev/sdc -p 4 -h 4
```

### Legacy Behavior (50% capacity)
```bash
sudo ./thin_pool_stress_test.sh -d /dev/sdb,/dev/sdc -p 4 -h 4 -c 50
```

### Custom Snapshot I/O Duration
```bash
sudo ./thin_pool_stress_test.sh -d /dev/sdb,/dev/sdc -p 4 --snapshot-io-duration 60
```

## New Volume Cycling Sequence

```
For each volume selected for deletion:

1. Take Snapshot
   └─ Monitor pool usage (metadata increase)

2. Write I/O for 30s (configurable)
   ├─ Random writes to trigger COW
   ├─ 10% of volume size
   └─ Monitor pool usage (data divergence)

3. Discard Volume
   ├─ Unmount if formatted
   ├─ blkdiscard
   └─ Monitor pool usage (space reclamation)

4. Delete Volume
   ├─ lvremove volume
   └─ Monitor pool usage (space reclamation)

5. Delete Snapshot
   ├─ lvremove snapshot
   └─ Monitor pool usage (space reclamation)

6. Recreate Volume
   ├─ lvcreate new volume
   ├─ Format if needed
   └─ Monitor pool usage (new allocation)
```

## Command-Line Parameters

### New Parameter
| Parameter | Default | Description |
|-----------|---------|-------------|
| `--snapshot-io-duration` | 30 | Seconds of I/O after snapshot |

### Updated Defaults
| Parameter | Old Default | New Default |
|-----------|-------------|-------------|
| `-c, --capacity-percent` | 50 | **80** |

### All Parameters
```
Required:
  -d, --drives DRIVES              Comma-separated drives

Optional:
  -p, --parallel-deletes NUM       Parallel deletes (default: 2)
  -h, --max-hours HOURS            Max runtime hours (default: 0=indefinite)
  -i, --max-iterations NUM         Max iterations (default: 0=indefinite)
  -m, --metadata-size SIZE         Metadata size (default: 15G)
  -c, --capacity-percent PCT       Pool capacity % (default: 80)
  -n, --num-volumes NUM            Number of volumes (default: 16)
  -v, --volume-mode MODE           raw or formatted (default: raw)
  -l, --log-dir DIR                Log directory
      --vg-name NAME               VG name (default: stress_vg)
      --pool-name NAME             Pool name (default: stress_pool)
      --snapshot-io-duration SEC   Snapshot I/O duration (default: 30)
      --help                       Show help
```

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

## Common Scenarios

### 1. Quick Validation (30 min)
```bash
make test-quick DRIVES=/dev/sdb,/dev/sdc
```

### 2. Standard Test (4 hours)
```bash
make test-standard DRIVES=/dev/sdb,/dev/sdc
```

### 3. High Stress (8 hours, 8 parallel)
```bash
make test-stress DRIVES=/dev/sdb,/dev/sdc,/dev/sdd
```

### 4. Minimal Snapshot Impact
```bash
sudo ./thin_pool_stress_test.sh \
  -d /dev/sdb,/dev/sdc \
  -p 4 \
  --snapshot-io-duration 5
```

### 5. Maximum Snapshot Stress
```bash
sudo ./thin_pool_stress_test.sh \
  -d /dev/sdb,/dev/sdc \
  -p 4 \
  --snapshot-io-duration 120 \
  -c 90
```

## Performance Expectations

### Iteration Time Impact
- **Old**: ~60-90 seconds per iteration
- **New**: ~90-150 seconds per iteration
  - +30s for snapshot I/O (configurable)
  - +10-20s for snapshot operations

### Metadata Usage
- **Snapshots increase metadata usage**
- Monitor `metadata_percent` closely
- Consider increasing metadata size for long tests:
  ```bash
  sudo ./thin_pool_stress_test.sh -d /dev/sdb,/dev/sdc -m 20G
  ```

### Pool Capacity
- **80% default fills pool faster**
- Monitor `data_percent` closely
- Reduce if pool fills too quickly:
  ```bash
  sudo ./thin_pool_stress_test.sh -d /dev/sdb,/dev/sdc -c 60
  ```

## Troubleshooting

### Pool Metadata Full
**Symptom**: Test fails with metadata errors

**Solution**: Increase metadata size
```bash
sudo ./thin_pool_stress_test.sh -d /dev/sdb,/dev/sdc -m 20G
```

### Pool Data Full
**Symptom**: Cannot create volumes, pool at 100%

**Solution**: Reduce capacity percentage
```bash
sudo ./thin_pool_stress_test.sh -d /dev/sdb,/dev/sdc -c 60
```

### Iteration Too Slow
**Symptom**: Each iteration takes too long

**Solution**: Reduce snapshot I/O duration
```bash
sudo ./thin_pool_stress_test.sh -d /dev/sdb,/dev/sdc --snapshot-io-duration 10
```

### Snapshot Creation Fails
**Symptom**: Errors during snapshot creation

**Solution**: Check pool has enough space
```bash
# Check current usage
sudo lvs -o +data_percent,metadata_percent stress_vg/stress_pool

# Reduce capacity or increase pool size
sudo ./thin_pool_stress_test.sh -d /dev/sdb,/dev/sdc -c 50
```

## Log Analysis

### Check Snapshot Operations
```bash
grep -i "snapshot" thin_pool_stress_logs/stress_test_*.log
```

### Monitor Pool Usage Trends
```bash
grep "Pool usage" thin_pool_stress_logs/stress_test_*.log
```

### Analyze Metadata Growth
```bash
awk -F',' '{print $1","$7}' thin_pool_stress_logs/stats_*.log
```

## Best Practices

1. **Start with quick test** to validate setup
2. **Monitor metadata usage** - snapshots increase metadata
3. **Watch pool capacity** - 80% fills faster than 50%
4. **Adjust snapshot I/O** based on your needs
5. **Use larger metadata** for long tests (20G instead of 15G)
6. **Monitor in real-time** using watch commands

## Migration from Old Version

### Keep Old Behavior
```bash
# Use 50% capacity explicitly
sudo ./thin_pool_stress_test.sh -d /dev/sdb,/dev/sdc -c 50
```

### Adopt New Behavior
```bash
# Use defaults (80% capacity, 30s snapshot I/O)
sudo ./thin_pool_stress_test.sh -d /dev/sdb,/dev/sdc
```

### Gradual Adoption
```bash
# Start with 60% capacity, short snapshot I/O
sudo ./thin_pool_stress_test.sh \
  -d /dev/sdb,/dev/sdc \
  -c 60 \
  --snapshot-io-duration 15
```

## Quick Commands

```bash
# Install dependencies
make install

# Check requirements
make check

# Make scripts executable
make permissions

# Run quick test
make test-quick DRIVES=/dev/sdb,/dev/sdc

# Analyze results
make analyze

# Clean up logs
make clean

# Emergency LVM cleanup
make clean-lvm DRIVES=/dev/sdb,/dev/sdc
```

