#!/bin/bash
for p in $(cat mytargets |  awk '{print $2}'); do blkdiscard $p; done
./iotest -targets ./mytargets -shuffle
nohup ./iotest -targets ./mytargets -random > nohup.localtest-$(date +%s).out &

