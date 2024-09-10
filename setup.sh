#!/bin/bash

mkdir -p /var/cores/lns
pushd /var/cores/lns

mkdir in
for i in $(seq 0 15); do 
  dd if=/dev/urandom of=in/in$i bs=4k count=1
done
