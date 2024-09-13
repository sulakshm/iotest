#!/bin/bash

## run from setup dir - /var/cores/lns
## verify based on current targets config

#mount /dev/mapper/pwx1-248657805099382910 /var/lib/osd/mounts/vol1

#mount /dev/mapper/pwx1-262882370262478795 /var/lib/osd/mounts/vol2
#mount /dev/mapper/pwx2-16737316052676059 /var/lib/osd/mounts/vol3
#mount /dev/mapper/pwx1-912608769206379708 /var/lib/osd/mounts/vol4
#mount /dev/mapper/pwx0-78287799441958780 /var/lib/osd/mounts/vol5
#mount /dev/mapper/pwx2-681592565474254003 /var/lib/osd/mounts/vol1
#
dmsetup message /dev/mapper/pwx1-pxpool-tpool 0 reserve_metadata_snap
thin_ls -m  /dev/mapper/pwx1-pxpool_tmeta
dmsetup message /dev/mapper/pwx1-pxpool-tpool 0 release_metadata_snap

#dmsetup message /dev/mapper/pwx1-pxpool-tpool 0 reserve_metadata_snap
#thin_ls -m  /dev/mapper/pwx1-pxpool_tmeta
#dmsetup message /dev/mapper/pwx1-pxpool-tpool 0 release_metadata_snap

#dmsetup message /dev/mapper/pwx2-pxpool-tpool 0 reserve_metadata_snap
#thin_ls -m  /dev/mapper/pwx2-pxpool_tmeta
#dmsetup message /dev/mapper/pwx2-pxpool-tpool 0 release_metadata_snap

./iotest -targets ./mytargets -verify -flush 64

