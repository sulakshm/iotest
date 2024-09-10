#!/bin/bash

## setup.sh creates 16 data colors with random data (4K)
## create the targets(mytargets file under /var/cores/lns) list of devices (tag, path, data color[0-15])
## run from /var/cores/lns - setup dir
for p in $(cat mytargets |  awk '{print $2}'); do blkdiscard $p; done
./iotest -targets ./mytargets -shuffle
dmsetup message /dev/mapper/pwx0-pxpool-tpool 0 reserve_metadata_snap
thin_ls -m  /dev/mapper/pwx0-pxpool_tmeta
dmsetup message /dev/mapper/pwx0-pxpool-tpool 0 release_metadata_snap

nohup ./iotest -targets ./mytargets -random > nohup.localtest-$(date +%s).out &
