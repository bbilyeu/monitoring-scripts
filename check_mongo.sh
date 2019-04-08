#!/bin/bash

##
## Author: Beau Bilyeu (beau.bilyeu@gmail.com)
## Usage: ./check_mysql.sh /path/to/user/.my.cnf [-m] [-r [warn_sec=900] [crit_sec=3600]] [-c [warn%=75] [crit%=90]]
##
## Attempts to connect and run "db.version()" to ensure 'up' state
##

mongo=$(command -v mongo)

## ensure the mongo client is installed
if [ -z "$mongo" ] || [ "$mongo" == "" ]; then
    echo "UNKNOWN: 'mongo' client not found!"
    exit 3
fi

if ! out=$($mongo --eval "printjson(db.version())" --quiet); then
    echo "CRITICAL: Could not connect. Error: [$out]"
    exit 2
else
    echo "OK: mongo version '$(echo $out | tr -d '\"')'"
    exit 0
fi