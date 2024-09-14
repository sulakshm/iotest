#!/bin/bash

#s=3
#for d in 909337393487342715 301021115403314116 925403605298131029 607941508795049988 1124864597118850913 253523752192170476 567856261472975682 406928161494094386 155386478392338987 535644189997773270; do
#	nohup ./iotest -dev /dev/mapper/pwx0-$d -seed $s > nohup.$d.out&
#	s=$((s+1))
#done

for p in $(cat mytargets |  awk '{print $2}'); do blkdiscard $p; done
./iotest -targets ./mytargets -shuffle
nohup ./iotest -targets ./mytargets -random > nohup.localtest-$(date +%s).out &
