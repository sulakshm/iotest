# iotest


## setup
1. create a top level work dir /var/cores/lns
2. copy setup.sh, verify.sh, runtest.sh, iotest to the above dir.
3. run setup.sh
4. setup targets
5. initiate io test
6. check data

## reference

### setup 
```
# bash setup.sh
/var/cores/lns /var/cores/lns
mkdir: cannot create directory ‘in’: File exists
1+0 records in
1+0 records out
4096 bytes (4.1 kB, 4.0 KiB) copied, 0.00042205 s, 9.7 MB/s
1+0 records in
1+0 records out
4096 bytes (4.1 kB, 4.0 KiB) copied, 0.000681752 s, 6.0 MB/s
1+0 records in
1+0 records out
4096 bytes (4.1 kB, 4.0 KiB) copied, 0.000424058 s, 9.7 MB/s
1+0 records in
1+0 records out
4096 bytes (4.1 kB, 4.0 KiB) copied, 0.00119967 s, 3.4 MB/s
1+0 records in
1+0 records out
4096 bytes (4.1 kB, 4.0 KiB) copied, 0.000465667 s, 8.8 MB/s
1+0 records in
1+0 records out
4096 bytes (4.1 kB, 4.0 KiB) copied, 0.000330888 s, 12.4 MB/s
1+0 records in
1+0 records out
4096 bytes (4.1 kB, 4.0 KiB) copied, 0.000339073 s, 12.1 MB/s
1+0 records in
1+0 records out
4096 bytes (4.1 kB, 4.0 KiB) copied, 0.000367458 s, 11.1 MB/s
1+0 records in
1+0 records out
4096 bytes (4.1 kB, 4.0 KiB) copied, 0.000386638 s, 10.6 MB/s
1+0 records in
1+0 records out
4096 bytes (4.1 kB, 4.0 KiB) copied, 0.000461373 s, 8.9 MB/s
1+0 records in
1+0 records out
4096 bytes (4.1 kB, 4.0 KiB) copied, 0.000475682 s, 8.6 MB/s
1+0 records in
1+0 records out
4096 bytes (4.1 kB, 4.0 KiB) copied, 0.000475896 s, 8.6 MB/s
1+0 records in
1+0 records out
4096 bytes (4.1 kB, 4.0 KiB) copied, 0.000469014 s, 8.7 MB/s
1+0 records in
1+0 records out
4096 bytes (4.1 kB, 4.0 KiB) copied, 0.000635699 s, 6.4 MB/s
1+0 records in
1+0 records out
4096 bytes (4.1 kB, 4.0 KiB) copied, 0.000347354 s, 11.8 MB/s
1+0 records in
1+0 records out
4096 bytes (4.1 kB, 4.0 KiB) copied, 0.000449872 s, 9.1 MB/s
```

### set targets (name, path, color=<int> is a data pattern from above [0,15])
```
# cat mytargets
248657805099382910 /dev/mapper/pwx1-248657805099382910 3
```

### run iotest
```
# bash runtest.sh
discard /dev/mapper/pwx1-248657805099382910
shuffled->target 248657805099382910, path /dev/mapper/pwx1-248657805099382910, color 3
DEV MAPPED CREATE_TIME SNAP_TIME
  1  33MiB           0         0
  4      0           0         0
#
```

### run verification
based on a journal file j.dat 
```
#bash verify.sh
DEV MAPPED CREATE_TIME SNAP_TIME
  1  33MiB           0         0
  4 660MiB           0         0
target 248657805099382910, path /dev/mapper/pwx1-248657805099382910, color 0
tgt 248657805099382910: using color 0
using journal /var/cores/lns/j.dat
journal opened at 3

verify done
#
```
