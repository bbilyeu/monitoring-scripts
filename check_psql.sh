#!/bin/bash

## Author: Beau Bilyeu (beau.bilyeu@gmail.com)
## Usage: ./check_psql.sh /path/to/user/.pgpass someUserName [-m]

## Huge credit to the following authors and their articles:
# Margo Schaedel, https://www.influxdata.com/blog/metrics-to-monitor-in-your-postgresql-database/
# Emily Chang, https://www.datadoghq.com/blog/postgresql-monitoring/
# Denish Patel, http://www.pateldenish.com/2013/07/postgres-9-2-monitoring-temp-files-generation-in-real-time.html

help="Usage: ./check_psql.sh /path/to/user/.pgpass \$userName [-m]"

## ensure we have a real file
if [ -z "$1" ] || [ "$1" == "" ] || [ ! -f "$1" ]; then 
    echo -e "UNKNOWN: No such file. $help\n"; 
    exit 3
## ensure we at least have a string with a user name
elif [ -z "$2" ] || [ "$2" == "" ]; then
    echo -e "UNKNOWN: No user passed. $help\n"; 
    exit 3
else
    psql=$(command -v psql)
    if [ -z "$psql" ] || [ "$psql" == "" ]; then 
        psql=$(which psql);
        if [ -z "$psql" ] || [ "$psql" == "" ]; then
            echo "UNKNOWN: psql executable not found."
            exit 3
        fi
    fi
    psql=$(echo "$psql" | tr -d '\n')
    export PGPASSFILE="$1"
    pcmd="${psql} -U $2 -w"
    if err=$($pcmd -c "select version();" 2>&1 >/dev/null); then
        if [ "$3" == "-m" ]; then
            ## metrics
            perfData=""
            
            ## get version major/minor/release
            boolNineTwoSafe=0
            postgres=$(command -v postgres)
            if [ -n "$postgres" ]; then
                versionCheck=$($postgres -V)                    ## output similar to: postgres (PostgreSQL) 8.4.20
                IFS=' ' read -r -a field <<< "$versionCheck"    ## break into "postgres" "(PostgreSQL)" "8.4.20"
                IFS='.' read -r -a pversion <<< "${field[2]}"   ## break final into "8" "4" "20"
                
                if [[ ${pversion[0]} -eq ${pversion[0]} ]] && [[ ${pversion[1]} -eq ${pversion[1]} ]]; then
                    if [[ ${pversion[0]} -gt 9 ]]; then boolNineTwoSafe=1; 
                    elif [[ ${pversion[0]} -eq 9 ]] && [[ ${pversion[1]} -ge 2 ]]; then boolNineTwoSafe=1;
                    fi
                fi
            fi
            
            ## block to catch for postgresql versions before 9.2, which introduced "temp_bytes"
            if [[ $boolNineTwoSafe -eq 1 ]]; then 
                ## version at/above 9.2.x
                if ! results=$($pcmd -t -A -F"," -c "
                SELECT datname, 
                CASE WHEN (pg_database_size(datname) > 0) THEN round(CAST(float8 (pg_database_size(datname)::float/1024/1024) as numeric),2) ELSE 0 END as size_in_mb,
                numbackends as active_connections, 
                CASE WHEN (blks_hit > 0) THEN round(CAST(float8 (blks_hit::float/(blks_read + blks_hit)*100) as numeric),3) ELSE 0 END as cache_hit_ratio, 
                CASE WHEN (xact_commit > 0) THEN round(CAST(float8 (xact_commit::float/(xact_commit + xact_rollback)*100) as numeric),3) ELSE 0 END as xact_success_ratio, 
                CASE WHEN (tup_fetched > 0) THEN round(CAST(float8 ((tup_fetched::float/tup_returned)*100) as numeric),3) ELSE 0 END as approx_read_efficiency, 
                round(CAST(float8 (temp_bytes::float/1024/1024) as numeric),2) as temp_disk_used_MB 
                FROM pg_stat_database WHERE datname NOT LIKE 'template%' ORDER BY datname;" 2>&1); then
                    echo "CRITICAL: Unable to run metrics query. PostgreSQL Error: [$results]"
                    exit 2
                fi
                #echo "$results"
            else 
                ## version below 9.2.x
                if ! results=$($pcmd -t -A -F"," -c "
                SELECT datname, 
                CASE WHEN (pg_database_size(datname) > 0) THEN round(CAST(float8 (pg_database_size(datname)::float/1024/1024) as numeric),2) ELSE 0 END as size_in_mb,
                numbackends as active_connections, 
                CASE WHEN (blks_hit > 0) THEN round(CAST(float8 (blks_hit::float/(blks_read + blks_hit)*100) as numeric),3) ELSE 0 END as cache_hit_ratio, 
                CASE WHEN (xact_commit > 0) THEN round(CAST(float8 (xact_commit::float/(xact_commit + xact_rollback)*100) as numeric),3) ELSE 0 END as xact_success_ratio, 
                CASE WHEN (tup_fetched > 0) THEN round(CAST(float8 ((tup_fetched::float/tup_returned)*100) as numeric),3) ELSE 0 END as approx_read_efficiency 
                FROM pg_stat_database WHERE datname NOT LIKE 'template%' ORDER BY datname;" 2>&1); then
                    echo "CRITICAL: Unable to run metrics query. PostgreSQL Error: [$results]"
                    exit 2
                fi
            fi
            
            ## break output into an array of rows
            IFS=$'\n'; read -r -d '' -a row <<< "$results"
            for i in "${row[@]}"; do
                ## break row into an array of values (field)
                IFS=',' read -r -a field <<< "$i"
                perfData="${perfData} ${field[0]}_size=${field[1]}MB;" ## size_in_mb
                perfData="${perfData} ${field[0]}_activeConn=${field[2]};" ## active_connections
                perfData="${perfData} ${field[0]}_cacheHitRatio=${field[3]}%;90:;75:;" ## cache_hit_ratio
                perfData="${perfData} ${field[0]}_xactSuccessRatio=${field[4]}%;90:;75:;" ## xact_success_ratio
                perfData="${perfData} ${field[0]}_approxReadEfficiency=${field[5]}%;" ## approx_read_efficiency
                if [[ $boolNineTwoSafe -eq 1 ]]; then perfData="${perfData} ${field[0]}_tmpDiskUsed=${field[6]}MB;"; fi ## temp_disk_used_mb (if 9.2.x or above)
            done
            
            echo "OK: Connection Successful|$perfData"
            exit 0
        else
            ## "is it up?"
            echo "OK: PostgreSQL is up."
            exit 0
        fi
    else
        echo "CRITICAL: PostgreSQL cannot process 'select version()', error: '$err'"
        exit 2
    fi
fi

## if we got this far, something went wrong
echo "WARNING: An unexpected outcome occurred. Please investigate."
exit 1