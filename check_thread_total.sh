#!/bin/bash

##
## Author: Beau Bilyeu (beau.bilyeu@gmail.com)
## Usage: ./check_thread_total.sh
##
##  Noteable Reference: https://askubuntu.com/questions/88972/how-to-get-from-terminal-total-number-of-threads-per-process-and-total-for-al
##

threadCount=$(ps -eo nlwp | tail -n +2 | awk '{ num_threads += $1 } END { print num_threads }')
threadMax=""

if [ -f "/proc/sys/kernel/threads-max" ]; then threadMax=$(cat /proc/sys/kernel/threads-max); fi

if [ ! -z "$threadMax" ] && [ "$threadMax" != "" ]; then
    warnCount=$(bc <<< "$threadMax / 0.75")
    critCount=$(bc <<< "$threadMax / 0.90")
    
    if [ "$threadCount" -gt "$warnCount" ]; then
        echo "WARN: Thread count|threadCount=$threadCount;$warnCount;$critCount;0;$threadMax"
        exit 1
    elif [ "$threadCount" -gt "$critCount" ]; then
        echo "CRIT: Thread count|threadCount=$threadCount;$warnCount;$critCount;0;$threadMax"
        exit 2
    else
        echo "OK: Thread count|threadCount=$threadCount;$warnCount;$critCount;0;$threadMax"
        exit 0
    fi
fi

## shouldn't occur, but it's here anyway
echo "UNKNOWN: /proc/sys/kernel/threads-max not found."
exit 3
