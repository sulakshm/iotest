#!/bin/bash

## run from setup dir - /var/cores/lns
## verify based on current targets config

dmsetup message /dev/mapper/pwx0-pxpool-tpool 0 reserve_metadata_snap
thin_ls -m  /dev/mapper/pwx0-pxpool_tmeta
dmsetup message /dev/mapper/pwx0-pxpool-tpool 0 release_metadata_snap

./iotest -targets ./mytargets -verify

