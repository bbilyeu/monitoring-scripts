#!/bin/bash

##
## Author: Beau Bilyeu (beau.bilyeu@gmail.com)
## Usage: ./check_mysql.sh /path/to/user/.my.cnf [-m] [-r [warn_sec=900] [crit_sec=3600]] [-c [warn%=75] [crit%=90]]
##
## (none) = MySQL State Check (is it up?)
## -r = Replicataion Check
## -m = Metrics
## -c = Connection status (used vs max)
##
##  Huge credit to the following superheroes and their tools:
##      Gerhard Lausser, https://labs.consol.de/nagios/check_mysql_health/, https://github.com/lausser/check_mysql_health
##      Jean-Marie Renouard, https://github.com/major/MySQLTuner-perl/blob/master/mysqltuner.pl
##
##  Noteable Reference: https://nagios-plugins.org/doc/guidelines.html
##

helpArgs="/(-h|-?|--help|--?)/i"
trueArgs="/(t|1|True)/i"
falseArgs="/(f|0|False)/i"

mysql=$(command -v mysql)
timeout=$(command -v timeout)
bc=$(command -v bc)
conf=""
perfData=""
query=""
WARN=0
CRIT=0

## print help string and exit
printHelp()
{
   echo -e "Usage: $0 /path/to/user/.my.cnf [-m] [-r [warn_sec=900] [crit_sec=3600]] [-c [warn%=75] [crit%=90]]\n\tNo parameters is state check\n\t-m = Metrics\n\t-r = Slave Replication\n\t-c = Connection Status (used vs max)"
}

## Syntax: roundToInt "$arg1"
## REQUIRED: arg1 to be floating point (duh!)
roundToInt()
{
    if [ -z "$1" ] || [ "$1" == "" ]; then
        echo -n ""
    else
        echo -en "$(printf %.f "$1")"
    fi
}

## Syntax: roundToInt "$arg1" "$arg2"
## REQUIRED: arg1 to be floating point, 
##              arg2 number of decimal places
setPrecision()
{
    if [ -z "$1" ] || [ "$1" == "" ] || [ -z "$2" ] || [ "$2" == "" ]; then
        echo -n ""
    else
        echo -en "$(printf %."$2"f "$1")"
    fi
}

## Syntax: getPcnt "$arg1" "$arg2" ["$arg3"]
## REQUIRED: arg1 and arg2 must be numerical
## OPTIONAL: (bool) arg3 is inversion of the percentage
getPcnt()
{
    if [ -z "$1" ] || [ "$1" == "" ] || [ -z "$2" ] || [ "$2" == "" ]; then
        echo -n ""
    else
        if [ "$3" ] && [[ $trueArgs =~ $3 ]]; then
            echo -en "$(  ${bc} <<< " scale=4; 100 - ( ($1 / $2) * 100 ) " )"  ## return inverted percentage            
        else
            echo -en "$(  ${bc} <<< " scale=4; ($1 / $2) * 100 " )"            ## return normal percentage
        fi
    fi
}

## Syntax: getPcnt "$arg1" "$arg2" ["$arg3"]
## REQUIRED: arg1 and arg2 must be numerical
## OPTIONAL: (bool) arg3 is inversion of the percentage
getIntPcnt()
{
    if [ -z "$1" ] || [ "$1" == "" ] || [ -z "$2" ] || [ "$2" == "" ]; then
        echo -n ""
    else
        if [ "$3" ] && [[ $trueArgs =~ $3 ]]; then
            echo -en "$( roundToInt "$(getPcnt "$1" "$2" "$3")" )"    ## pass inversion flag 
        else
            echo -en "$( roundToInt "$(getPcnt "$1" "$2")" )"         ## normal run
        fi
    fi
}

###########################

### int main() ###

## ensure the mysql client is installed
if [ -z "$mysql" ] || [ "$mysql" == "" ]; then
    echo "UNKNOWN: 'mysql' client not found!"
    exit 3
fi

## ensure bc is installed
if [ -z "$bc" ] || [ "$bc" == "" ]; then
    echo "UNKNOWN: 'bc' not found! Please install via 'yum install bc' or 'apt-get install bc'"
    exit 3
fi

## ensure we have a valid defaults-file (config)
if [[ $1 =~ $helpArgs ]]; then
    printHelp
    exit 0
elif [ -z "$1" ] || [ "$1" == "" ]; then
    echo "UNKNOWN: No .my.cnf file passed"
    printHelp 
    exit 3
elif [ ! -f "$1" ]; then
    echo "UNKNOWN: '$1' is not a valid file."
    printHelp
    exit 3
elif [ -f "$1" ]; then
    conf="$1"
fi

## perform a quick connection test
connTest=$(${mysql} --defaults-file="$conf" -e "SELECT VERSION();")
if [[ $connTest =~ "VERSION" ]]; then
    if [ "$2" == "-r" ]; then
        ### Slave Replication ###

        ## if exists and if numeric, set them, else set baseline
        if [ -n "$3" ] && [ "$3" != "" ] && [[ $3 =~ ^[0-9]+$ ]]; then WARN="$3"; else WARN=900; fi
        if [ -n "$4" ] && [ "$4" != "" ] && [[ $4 =~ ^[0-9]+$ ]]; then CRIT="$4"; else CRIT=3600; fi
        
        slaveStatus=$(${mysql} --defaults-file="$conf" -e "SHOW SLAVE STATUS\G;")

        ## START slave status
        if [ "$slaveStatus" == "" ] || [ -z "$slaveStatus" ]; then
            echo "UNKNOWN: MySQL replication is not configured."
            exit 3
        else
            mHost=""        # Master_Host
            ioRun="No"      # Slave_IO_Running
            sqlRun="No"     # Slave_SQL_Running
            secBehind="0"   # Seconds_Behind_Master

            IFS=$'\n'
            for i in $slaveStatus; do
                if [[ $i =~ "Master_Host" ]]; then mHost=$(echo "$i" | awk '{print $2}'); 
                elif [[ $i =~ "Slave_IO_Running"  ]]; then ioRun=$(echo "$i" | awk '{print $2}'); 
                elif [[ $i =~ "Slave_SQL_Running" ]]; then sqlRun=$(echo "$i" | awk '{print $2}');
                elif [[ $i =~ "Seconds_Behind_Master" ]]; then secBehind=$(echo "$i" | awk '{print $2}'); 
                fi
            done

            ## finally, the output!
            if [ "$secBehind" == "NULL" ]; then
                echo "CRITICAL: Seconds_Behind_Master is NULL, replication is not functioning or configured."; exit 2
            elif [ "$ioRun" == "No" ]; then 
                echo "CRITICAL: Slave_IO_Running returned 'No'."; exit 2
            elif [ "$sqlRun" == "No" ]; then 
                echo "CRITICAL: Slave_SQL_Running returned 'No'."; exit 2
            else
                output="Replication is $secBehind seconds behind the master host '$mHost'"
                perfData="${perfData} secBehind=${secBehind}s;$WARN;$CRIT;0;"

                if [ "$secBehind" -gt "$CRIT" ]; then
                    echo "CRITICAL: $output|$perfData"; exit 2
                elif [ "$secBehind" -gt "$WARN" ]; then
                    echo "WARNING: $output|$perfData"; exit 1
                else
                    echo "OK: $output|$perfData"; exit 0
                fi
            fi ## END output
        fi ## END slave status
    elif [ "$2" == "-m" ]; then
        ### Metrics ###
        
        tableCacheHitRate="" 
        pcntQueryCacheUsed=""
        queryCachePrunesPerDay=""
        pcntFilesOpen=""
        pcntTableLocksImmediate=""
        pcntTempDisk=""
        threadCacheHitRate=""
        pcntAbortedConn=""
        pcntInnoLogFileSize=""
        pcntReads=""
        pcntWrites=""
        
        ## perf schema check
        #hasPerfSchema=0
        #query=$(${mysql} --defaults-file="$conf" -e "SHOW VARIABLES LIKE 'performance_schema';")
        #if [ "$query" == "" ] || [ -z "$query" ]; then hasPerfSchema=0; else hasPerfSchema=1; fi
        #query=""
        
        ### START metrics
        declare -A gStats
        declare -a queries=("SHOW GLOBAL STATUS" "SHOW GLOBAL VARIABLES")
        for q in "${queries[@]}"; do
            query=$(${mysql} --defaults-file="$conf" -e "$q;" | sed -e 's/\t/,/g')
            IFS=$'\n'; read -r -d '' -a row <<< "$query"    ## break into rows based on newline
            for r in "${row[@]}"; do                        ## loop through row elements, comma separated
                IFS=',' read -r -a field <<< "$r"
                gStats["${field[0]}"]="${field[1]}"         ## place in gStats hash (ex: gstats["Uptime"]="1234")
                #echo "gstats[${field[0]}] = ${field[1]}"
            done
        done

        ## Query Cache
        onPattern="/(ON|1)/i"
        if [[ ${gStats[query_cache_type]} =~ $onPattern ]] && [ "${gStats[query_cache_type]}" != "0" ]; then
            pcntQueryCacheUsed=$( getIntPcnt "${gStats[Qcache_free_memory]}" "${gStats[query_cache_size]}" "true" )
            queryCachePrunesPerDay=$((${gStats[Qcache_lowmem_prunes]} / (${gStats[Uptime]} / 86400)))
            
            perfData="${perfData} pcntQueryCacheUsed=${pcntQueryCacheUsed}%;90:;80:;"
            perfData="${perfData} queryCachePrunesPerDay=${queryCachePrunesPerDay};"
        fi
        
        ## Table Cache
        if [[ "${gStats[Opened_tables]}" -gt "0" ]]; then 
            tableCacheHitRate=$( setPrecision "$(getPcnt "${gStats[Open_tables]}" "${gStats[Opened_tables]}")" "2" )
        else 
            tableCacheHitRate=100; 
        fi
        perfData="${perfData} tableCacheHitRate=${tableCacheHitRate}%;99:;95:;"
        
        ## Open Files
        if [[ "${gStats[open_files_limit]}" -gt "0" ]]; then 
            pcntFilesOpen=$( getIntPcnt "${gStats[Open_files]}" "${gStats[open_files_limit]}" ) 
            
            perfData="${perfData} pcntFilesOpen=${pcntFilesOpen}%;:80,:95"
        fi
        
        ## Table Locks
        if [[ "${gStats[Table_locks_immediate]}" -gt "0" ]]; then 
            if [[ "${gStats[Table_locks_waited]}" -gt "0" ]]; then
                pcntTableLocksImmediate=$((${gStats[Table_locks_immediate]} * 100 / (${gStats[Table_locks_waited]} + ${gStats[Table_locks_immediate]}))) 
            else
                pcntTableLocksImmediate=100
            fi
            perfData="${perfData} pcntTableLocksImmediate=${pcntTableLocksImmediate}%;95:;90:;"
        fi
        
        ## Temp Tables
        if [[ "${gStats[Created_tmp_tables]}" -gt "0" ]]; then 
            if [[ "${gStats[Created_tmp_disk_tables]}" -gt "0" ]]; then
                pcntTempDisk=$( getIntPcnt "${gStats[Created_tmp_disk_tables]}" "${gStats[Created_tmp_tables]}" ); 
            else 
                pcntTempDisk=0
            fi
            perfData="${perfData} pcntTempDisk=${pcntTempDisk}%;:25;:50;"
        fi
        
        ## Thread Caching
        if [[ "${gStats[thread_cache_size]}" -gt "0" ]]; then
            threadCacheHitRate=$( setPrecision "$(getPcnt "${gStats[Threads_created]}" "${gStats[Connections]}" "True")" "2" )
            perfData="${perfData} threadCacheHitRate=${threadCacheHitRate}%;90:;80:;"
        fi
        
        ## Aborted Connections
        if [[ "${gStats[Connections]}" -gt "0" ]]; then 
            pcntAbortedConn=$( setPrecision "$(getPcnt "${gStats[Aborted_connects]}" "${gStats[Connections]}")" "2" ); 
            
            perfData="${perfData} pcntAbortedConn=${pcntAbortedConn}%;:2;:5;"
        fi
        
        ## InnoDB Log File Percentage
        pcntInnoLogFileSize=$( setPrecision "$(getPcnt "$((${gStats[innodb_log_file_size]} * ${gStats[innodb_log_files_in_group]}))" "${gStats[innodb_buffer_pool_size]}")" "2" )
        perfData="${perfData} pcntInnoLogFileSize=${pcntInnoLogFileSize}%;25:;;"
        
        ## InnoDB Buffer Pool Utilization
        sizeQuery="SELECT SUM((ROUND(SUM(data_length + index_length) / 1024 / 1024, 2)) AS 'Size (MB)' FROM information_schema.TABLES GROUP BY table_schema;"
        if allDBSizeMB=$(  ${bc} <<< " scale=2; "$(du -s ${gStats[datadir]} | awk '{print $1}')" / 1024  "); then
            bufferPoolMB=$( ${bc} <<< " scale=2; "${gStats[innodb_buffer_pool_size]}" / 1024 / 1024" )
            systemMemMB=$(( $(roundToInt "$( ${bc} <<< "scale=4; $(grep MemTotal /proc/meminfo | awk '{print $2}') / 1024 / 1024")") * 1024 ))
            pcntPoolRatio=$( setPrecision "$( getPcnt "$bufferPoolMB" "$allDBSizeMB" )" "2" )
            
            perfData="${perfData} innoBufferPoolRatio=$pcntPoolRatio%;80:;"
            #perfData="${perfData} innoBufferPoolUsage=${bufferPoolMB}MB;;;0;$bufferPoolMB"
        fi
        
        ## InnoDB - Read Efficiency
        if [[ "${gStats[Innodb_buffer_pool_read_requests]}" ]] && [ "${gStats[Innodb_buffer_pool_read_requests]}" -gt "0" ]; then
            pcntInnoReadEfficiency=$( setPrecision "$(getPcnt "$((${gStats[Innodb_buffer_pool_read_requests]} - ${gStats[Innodb_buffer_pool_reads]}))" "${gStats[Innodb_buffer_pool_read_requests]}")" "2" )
            
            perfData="${perfData} pcntInnoReadEfficiency=${pcntInnoReadEfficiency}%;97:;95:;"
        fi
        
        ## InnoDB - Write Efficiency
        if [[ "${gStats[Innodb_log_write_requests]}" ]] && [ "${gStats[Innodb_log_write_requests]}" -gt "0" ]; then
            pcntInnoWriteEfficiency=$( setPrecision "$(getPcnt "$((${gStats[Innodb_log_write_requests]} - ${gStats[Innodb_log_writes]}))" "${gStats[Innodb_log_write_requests]}")" "2" )

            perfData="${perfData} pcntInnoWriteEfficiency=${pcntInnoWriteEfficiency}%;97:;95:;"
        fi
        
        ## Read / Write Percentages
        totalReads=${gStats[Com_select]}
        totalWrites=$((${gStats[Com_delete]} + ${gStats[Com_insert]} + ${gStats[Com_update]}))
        totalActivity=$(($totalReads + $totalWrites))
        pcntReads=$( getIntPcnt "$totalReads" "$totalActivity" )
        pcntWrites=$((100 - $pcntReads))
        
        perfData="${perfData} pcntReads=${pcntReads}%;"
        perfData="${perfData} pcntWrites=${pcntWrites}%;"
        
        echo "OK: Metrics polled.|$perfData"; exit 0
        ### END metrics
    elif [ "$2" == "-c" ]; then
        ### Connection Status
        
        ## if exists and if numeric, set them, else set baseline
        if [ -n "$3" ] && [ "$3" != "" ] && [[ $3 =~ ^[0-9]+$ ]]; then WARN="$3"; else WARN=75; fi
        if [ -n "$4" ] && [ "$4" != "" ] && [[ $4 =~ ^[0-9]+$ ]]; then CRIT="$4"; else CRIT=90; fi
        
        ## actual query
        output=$(${mysql} --defaults-file="$conf" -sNe"SELECT VARIABLE_VALUE,@@GLOBAL.max_connections FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME = 'THREADS_CONNECTED';")
        connUsed=$(echo $output | awk '{print $1}')
        connMax=$(echo $output | awk '{print $2}')
        connRatio=$( ${bc} <<< "($connUsed / $connMax) * 100")
        warnUsed=$( printf %.f "$( ${bc} <<< "$connMax * ($WARN * 0.01)")" )
        critUsed=$( printf %.f "$( ${bc} <<< "$connMax * ($CRIT * 0.01)")" )
        
        perfData="${perfData} connections=$connUsed;$warnUsed;$critUsed,0,$connMax;"
        perfData="${perfData} connectionRatio=$connRatio%;$WARN;$CRIT;"
        
        if [ "$connRatio" -gt "$CRIT" ]; then
            echo "CRITICAL: $connRatio% of maximum connections used|$perfData"
            exit 2
        elif [ "$connRatio" -gt "$WARN" ]; then
            echo "WARNING: $connRatio% of maximum connections used|$perfData"
            exit 1
        else
            echo "OK: $connRatio% of maximum connections used|$perfData"
            exit 0
        fi
        
        ### END Connection Status
    else ## no args passed
        ## "is it up?"
        echo "OK: MySQL is up."
        exit 0
    fi
else
    ## connection unsuccessful, exit
    echo "CRITICAL: Unable to connect to MySQL using '$conf', error: '$connTest'"
    exit 2
    
fi

## if we got this far, something went wrong
echo "WARNING: An unexpected outcome occurred. Please investigate."
exit 1