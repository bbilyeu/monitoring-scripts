#!/bin/bash

##
## Author: Beau Bilyeu (beau.bilyeu@gmail.com)
## Usage: ./check_fds_by_procname.sh <username> <process_name>]
##
##  Attempts to find process IDs by string, then issues cat against
##      /proc/$PID/fd to sum up total FDs being used.

pOwner=""
pName=""
count=0

if [ "$#" != "2" ]; then
    echo "Usage: $0 <username> <process_name>"
    exit 0
elif [ "$#" == "2" ]; then
    pOwner="$1" ## read in username
    pName="$2"  ## read in proc name
fi

## get PID(s)
PID=$(pgrep -U "$pOwner" -u "$pOwner" -f "$pName") 
if [ -z "$PID" ] || [ "$PID" == "0" ]; then
    echo "UNKNOWN: Could not locate pids for '$pName' by user '$pOwner'."
    exit 3
fi

## loop through pid(s) and get values
for i in $PID; do 
    count=$((count + $(ls -lah "/proc/$i/fd" | wc -l))); ## append to count variable
done

## output
echo "OK: User $pOwner has $count $pName fds|${pName}_fds=$count"