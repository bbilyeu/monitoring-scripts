#!/bin/bash

##
## Author: Beau Bilyeu (beau.bilyeu@gmail.com)
## Usage: ./check_memcache.sh [-m|-M] [host=127.0.0.1] [port=11211]
##
## (none) = Attempt to connect to 127.0.0.1:11211 (is it up)
## -m = Optional, will return common metrics
## -M = Optional, will return all available metrics
## host = Optional, hostname or IP
## port = Optional, memcache's port
##
## Noteable References: 
##  https://docs.oracle.com/cd/E17952_01/mysql-5.6-en/ha-memcached-stats-general.html
##  https://github.com/memcached/memcached/blob/master/doc/protocol.txt
##  https://blog.serverdensity.com/monitor-memcached/
##

helpArgs="/(-h|-?|--help|--?)/i"

host="127.0.0.1"
port="11211"
portStatus="open"
perfData=""
minPerfData=""
warnings=""
criticals=""
metrics=0

if [[ $1 =~ $helpArgs ]]; then
    echo -e "Usage: $0 [-m] [host=127.0.0.1] [port=11211]\n\t(none) = Attempt to connect to 127.0.0.1:11211 (is it up)\n\t-m = Optional, will return metrics\n\thost = Optional, hostname or IP\n\tport = Optional, memcache's port"
    exit 0
fi

## ensure netcat is installed
if ! nc=$(command -v nc || command -v netcat); then
    echo "UNKNOWN: netcat not installed."
    exit 3
fi

## read in arguments (if applicable)
if [ "$1" == "-M" ]; then 
    metrics=2; 
    shift
elif [ "$1" == "-m" ]; then 
    metrics=1; 
    shift
fi
## remaining arguments
if [ -n "$1" ]; then host="$1"; fi
if [ -n "$2" ]; then port="$2"; fi

## check port
{ exec 3<>"/dev/tcp/$host/$port"; } > /dev/null 2>&1 || portStatus="closed"

## exit if port is closed
if [ "$portStatus" == "closed" ]; then
    echo "WARNING: Failed to reach $host:$port"
    exit 1
fi

## exit for "state" check
if [[ $metrics -eq 0 ]]; then
    echo "OK: Memcached is up"
    exit 0
fi


if ! stats=$(echo 'stats' | $nc $host $port 2>/dev/null); then
    echo "CRITICAL: Failed to echo 'stats' to $host:$port with error [$stats]"
    exit 2
else
    row=()
    field=()
    
    ## break down on rows (newline), then break into fields (space)
    IFS=$'\n'; read -r -d '' -a row <<< "$stats"
    
    ## if, somehow, no rows are returned then exit
    if [ "${#row[@]}" == "0" ]; then
        echo "UNKNOWN: No values returned."
        exit 3
    fi
    
    for r in "${row[@]}"; do  
        IFS=' ' read -r -a field <<< "$r"
        #counter=$((counter+1)); echo "row #$counter: [${field[0]}],[${field[1]}],[${field[2]//[$'\t\r\n']}]";  ### DEBUG
        
        ## ensure it is a valid line
        if [ "${field[0]}" == "STAT" ]; then
            val="${field[2]//[$'\t\r\n']}"   ## shorthand label for convenience
            case "${field[1]}" in
                uptime) 
                    perfData="${perfData} uptime=${val}s;180:~"
                    if [[ $val -lt 180 ]]; then warnings="${warnings} Uptime is less than 180 seconds;"; fi
                    ;;
                rusage_user) perfData="${perfData} rusage_user=${val}s";;
                rusage_system) perfData="${perfData} rusage_system=${val}s";;
                curr_connections) perfData="${perfData} currentConnections=${val}";;
                total_connections) perfData="${perfData} totalConnections=${val}";;
                connection_structures) perfData="${perfData} connectionStructs=${val}";;
                reserved_fds) perfData="${perfData} reservedFDs=${val}";;
                cmd_get) 
                    perfData="${perfData} totalGets=${val}"
                    minPerfData="${minPerfData} totalGets=${val}"
                    gets="$val"
                    ;;
                cmd_set) perfData="${perfData} sets=${val}";;
                cmd_flush) 
                    perfData="${perfData} flushes=${val};2:~"
                    minPerfData="${minPerfData} flushes=${val};2:~"
                    ;;
                get_hits) 
                    perfData="${perfData} getHits=${val}"
                    minPerfData="${minPerfData} getHits=${val}"
                    hits="$val"
                    ;;
                get_misses) perfData="${perfData} getMisses=${val}";;
                delete_misses) perfData="${perfData} deleteMisses=${val}";;
                delete_hits) perfData="${perfData} deleteHits=${val}";;
                incr_misses) perfData="${perfData} incrReqMisses=${val}";;
                incr_hits) perfData="${perfData} incrReqHits=${val}";;
                decr_misses) perfData="${perfData} decrReqMisses=${val}";;
                decr_hits) perfData="${perfData} decrReqHits=${val}";;
                cas_misses) perfData="${perfData} casReqMisses=${val}";;
                cas_hits) perfData="${perfData} casReqHits=${val}";;
                cas_badval) perfData="${perfData} casReqBadValues=${val}";;
                touch_hits) perfData="${perfData} touchHits=${val}";;
                touch_misses) perfData="${perfData} touchMisses=${val}";;
                auth_cmds) perfData="${perfData} authCommands=${val}";;
                auth_errors) perfData="${perfData} authErrors=${val}";;
                bytes_read) 
                    tmp=$(bc <<< "scale=2; $val / 1024"); 
                    perfData="${perfData} kbRead=${tmp}KB"
                    minPerfData="${minPerfData} kbRead=${tmp}KB"
                    ;;
                bytes_written) 
                    tmp=$(bc <<< "scale=2; $val / 1024"); 
                    perfData="${perfData} kbWrite=${tmp}KB"
                    minPerfData="${minPerfData} kbWrite=${tmp}KB"
                    ;;
                accepting_conns) 
                    perfData="${perfData} acceptingConnections=${val};:1~"
                    minPerfData="${minPerfData} acceptingConnections=${val};:1~"
                    if [ "$val" == "0" ]; then criticals="${criticals} memcached is not accepting connections;"; fi
                    ;;
                listen_disabled_num) perfData="${perfData} numMaxConnEvents=${val};1:~";;
                threads) perfData="${perfData} threads=${val}";;
                conn_yields) perfData="${perfData} connectionYields=${val};1:~";;
                hash_power_level) perfData="${perfData} hashPowerLevel=${val}";;
                hash_bytes) perfData="${perfData} hashBytes=${val}B";;
                expired_unfetched) perfData="${perfData} expiredUnfetched=${val}";;
                evicted_unfetched) perfData="${perfData} evictedUnfetched=${val}";;
                replication) perfData="${perfData} replication=${val}";;
                curr_items) perfData="${perfData} currentItemCount=${val}";;
                total_items) perfData="${perfData} totalItemCount=${val}";;
                evictions) 
                    perfData="${perfData} evictions=${val};1:~"
                    minPerfData="${minPerfData} evictions=${val};1:~"
                    ;;
                reclaimed) perfData="${perfData} reclaimed=${val}";;
                bytes) usedBytes="$val";;
                limit_maxbytes) maxBytes="$val";;
            esac
        fi
    done
    
    ## calculate fill percentage
    if [ -n "$usedBytes" ] && [ "$usedBytes" != "0" ] && [ -n "$maxBytes" ] && [ "$maxBytes" != "0" ]; then 
        fillPcnt=$(bc <<< "scale=2; ($usedBytes / $maxBytes) * 100" 2>/dev/null)
        perfData="fillPcnt=$fillPcnt%;0;90 ${perfData}"
        minPerfData="fillPcnt=$fillPcnt%;0;90 ${minPerfData}"
    fi

    ## calculate hit ratio
    if [ -n "$gets" ] && [ "$gets" != "0" ] && [ -n "$hits" ] && [ "$hits" != "0" ]; then 
        hitRatio=$(bc <<< "scale=2; ($hits / $gets) * 100" 2>/dev/null)
        perfData="hitRatio=$hitRatio% ${perfData}"
        minPerfData="hitRatio=$hitRatio% ${minPerfData}"
    fi

    ## finally, output
    if [ "$criticals" != "" ]; then
        echo "CRITICAL:$criticals"
        exit 2
    elif [ "$warnings" != "" ]; then
        echo "WARNING:$warnings"
        exit 1
    else
        if [ $metrics -eq 2 ]; then
            echo "OK: memcached metrics|$perfData"
            exit 0
        else ## must be metrics=1 at this point
            echo "OK: memcached metrics|$minPerfData"
            exit 0
        fi
    fi
fi
