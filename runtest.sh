#!/bin/bash

## setup.sh creates 16 data colors with random data (4K)
## create the targets(mytargets file under /var/cores/lns) list of devices (tag, path, data color[0-15])
## run from /var/cores/lns - setup dir

#for p in $(cat mytargets |  awk '{print $2}'); do blkdiscard $p; done

umount /var/lib/osd/mounts/vol1
umount /var/lib/osd/mounts/vol2
umount /var/lib/osd/mounts/vol3
umount /var/lib/osd/mounts/vol4
umount /var/lib/osd/mounts/vol5

## file test rm file and recreate it
mount /dev/mapper/pwx1-262882370262478795 /var/lib/osd/mounts/vol2
mount /dev/mapper/pwx2-16737316052676059 /var/lib/osd/mounts/vol3
mount /dev/mapper/pwx1-912608769206379708 /var/lib/osd/mounts/vol4
mount /dev/mapper/pwx0-78287799441958780 /var/lib/osd/mounts/vol5
mount /dev/mapper/pwx2-681592565474254003 /var/lib/osd/mounts/vol1

for i in $(seq 1 5); do
rm -f /var/lib/osd/mounts/vol$i/test
truncate -s200G /var/lib/osd/mounts/vol$i/test
done

./iotest -targets ./mytargets -shuffle
dmsetup message /dev/mapper/pwx0-pxpool-tpool 0 reserve_metadata_snap
thin_ls -m  /dev/mapper/pwx0-pxpool_tmeta
dmsetup message /dev/mapper/pwx0-pxpool-tpool 0 release_metadata_snap

dmsetup message /dev/mapper/pwx1-pxpool-tpool 0 reserve_metadata_snap
thin_ls -m  /dev/mapper/pwx1-pxpool_tmeta
dmsetup message /dev/mapper/pwx1-pxpool-tpool 0 release_metadata_snap

dmsetup message /dev/mapper/pwx2-pxpool-tpool 0 reserve_metadata_snap
thin_ls -m  /dev/mapper/pwx2-pxpool_tmeta
dmsetup message /dev/mapper/pwx2-pxpool-tpool 0 release_metadata_snap

nohup ./iotest -targets ./mytargets -random > nohup.filetest-$(date +%s).out &
