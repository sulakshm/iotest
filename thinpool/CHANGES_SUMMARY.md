# LVM Thin Pool Stress Test - Changes Summary

## Changes Made (2026-02-10)

### 1. Default Volume Capacity Changed from 50% to 80%

**Rationale**: Increase stress on the thin pool by using more capacity by default.

**Files Modified**:
- `thin_pool_stress_test.sh`: Changed `POOL_CAPACITY_PERCENT=50` to `POOL_CAPACITY_PERCENT=80`
- `thin_pool_test_scenarios.sh`: Updated all scenarios to use `-c 80`
- `Makefile`: Updated test targets to use `-c 80`

**Impact**: 
- All volumes will now use 80% of pool capacity instead of 50%
- More aggressive stress testing by default
- Higher pool utilization during tests

### 2. Enhanced Thin Pool Monitoring

**Feature**: Continuous monitoring and reporting of thin pool data and metadata usage throughout the test.

**Implementation**:
- Pool usage (tdata and tmeta) is now reported at every step of the volume cycling process
- Usage is logged before and after each operation:
  - Before/after snapshot creation
  - Before/after I/O operations
  - Before/after discard operations
  - Before/after volume deletion
  - Before/after snapshot deletion
  - Before/after volume recreation

**Output Example**:
```
[INFO]   Step 1/5: Taking snapshots...
[INFO]   Pool usage before snapshot: 45.2,3.1
[INFO]   Pool usage after snapshot: 48.7,3.5
[INFO]   Step 2/5: Writing I/O for 30s...
[INFO]   Pool usage before I/O: 48.7,3.5
[INFO]   Pool usage after I/O: 52.3,3.8
```

### 3. New Volume Deletion Sequence with Snapshots

**Previous Sequence**:
1. Unmount (if formatted)
2. Discard volume
3. Delete volume
4. Recreate volume

**New Sequence**:
1. **Take snapshot** of the volume
2. **Write new I/O** on the original volume for 30 seconds (configurable)
3. **Discard** the original volume
4. **Delete** the original volume
5. **Delete** the snapshot
6. **Recreate** the volume

**Rationale**: 
- Tests thin pool snapshot functionality
- Validates COW (Copy-on-Write) behavior
- Stresses metadata usage with snapshots
- Tests discard behavior with snapshots present
- More realistic production scenario

**Configuration**:
- New parameter: `--snapshot-io-duration` (default: 30 seconds)
- Controls how long I/O runs on volume after snapshot is taken
- Can be adjusted via command line

### 4. New Configuration Parameter

**Parameter**: `--snapshot-io-duration SECONDS`

**Default**: 30 seconds

**Purpose**: Controls the duration of I/O operations on a volume after a snapshot is created

**Usage**:
```bash
# Use default 30 seconds
sudo ./thin_pool_stress_test.sh -d /dev/sdb,/dev/sdc -p 4

# Custom 60 seconds
sudo ./thin_pool_stress_test.sh -d /dev/sdb,/dev/sdc -p 4 --snapshot-io-duration 60
```

## Technical Details

### Snapshot I/O Workload

When a snapshot is created, the script runs FIO on the original volume with:
- **Pattern**: Random writes (to maximize COW operations)
- **Size**: 10% of volume
- **Block Size**: 4KB
- **Engine**: libaio
- **Queue Depth**: 16
- **Direct I/O**: Yes
- **Duration**: Configurable (default 30s)

This ensures that:
- COW operations are triggered
- Metadata is updated
- Snapshot diverges from original
- Pool usage increases realistically

### Pool Monitoring Points

The script now monitors and reports pool usage at 7 key points during each batch:

1. **Before snapshot creation**: Baseline usage
2. **After snapshot creation**: Metadata increase from snapshot
3. **Before I/O**: Pre-COW state
4. **After I/O**: Post-COW state (data divergence)
5. **After discard**: Effect of discard on pool
6. **After volume delete**: Space reclamation from volume
7. **After snapshot delete**: Space reclamation from snapshot
8. **After recreate**: New volume allocation

### Statistics Collected

All existing statistics are still collected, plus:
- Snapshot creation count (implicit in volume cycling)
- Pool usage at each operation step
- COW overhead from snapshot I/O

## Backward Compatibility

### Breaking Changes
- **Default capacity changed**: Scripts expecting 50% will now get 80%
  - **Workaround**: Explicitly specify `-c 50` if needed

### Non-Breaking Changes
- New `--snapshot-io-duration` parameter is optional
- All existing command-line parameters work as before
- Log format remains the same
- Statistics format remains the same

## Migration Guide

### For Existing Users

If you want to maintain the old behavior (50% capacity, no snapshots):

**Option 1**: Use explicit capacity parameter
```bash
sudo ./thin_pool_stress_test.sh -d /dev/sdb,/dev/sdc -p 4 -c 50
```

**Option 2**: The snapshot sequence is always active now, but you can minimize its impact:
```bash
sudo ./thin_pool_stress_test.sh -d /dev/sdb,/dev/sdc -p 4 -c 50 --snapshot-io-duration 5
```

### For New Users

Simply use the defaults for more aggressive testing:
```bash
sudo ./thin_pool_stress_test.sh -d /dev/sdb,/dev/sdc -p 4
```

## Testing Recommendations

### Quick Validation
```bash
# Test with new defaults (30 minutes)
make test-quick DRIVES=/dev/sdb,/dev/sdc
```

### Monitor Pool Usage
```bash
# In a separate terminal, watch pool usage in real-time
watch -n 2 'sudo lvs -o +data_percent,metadata_percent stress_vg/stress_pool'
```

### Verify Snapshot Behavior
Check the logs for snapshot-related operations:
```bash
grep -i "snapshot" thin_pool_stress_logs/stress_test_*.log
```

## Performance Impact

### Expected Changes

1. **Longer iteration time**: Each iteration now includes:
   - Snapshot creation time
   - 30 seconds of I/O per volume
   - Snapshot deletion time
   - Approximately +30-60 seconds per batch

2. **Higher metadata usage**: Snapshots increase metadata consumption
   - Monitor metadata_percent closely
   - May need larger metadata volume for long tests

3. **More realistic stress**: Better simulates production scenarios with snapshots

### Recommendations

- **Metadata size**: Consider increasing from 15G to 20G for long tests
- **Monitoring**: Watch metadata usage more closely
- **Capacity**: 80% default may fill pool faster - monitor data_percent

## Files Modified

| File | Changes |
|------|---------|
| `thin_pool_stress_test.sh` | • Changed default capacity to 80%<br>• Added snapshot sequence<br>• Added pool monitoring<br>• Added `--snapshot-io-duration` parameter |
| `thin_pool_test_scenarios.sh` | • Updated all scenarios to use 80% capacity |
| `Makefile` | • Updated test targets to use 80% capacity |
| `CHANGES_SUMMARY.md` | • This file (new) |

## Next Steps

1. Review the changes in `thin_pool_stress_test.sh`
2. Test with a quick validation run
3. Monitor pool usage during test
4. Adjust `--snapshot-io-duration` if needed
5. Consider increasing metadata size for long tests

## Questions or Issues?

If you encounter any issues with the new behavior:
1. Check pool metadata usage - may need larger metadata volume
2. Verify snapshot operations in logs
3. Adjust `--snapshot-io-duration` to reduce iteration time
4. Use `-c 50` to reduce capacity stress if needed

