#!/bin/bash

##
## Author: Beau Bilyeu (beau.bilyeu@gmail.com)
## Usage: ./check_apache_status.sh [host=127.0.0.1] [port=80] [uri=/server-status?auto]
##
## (none) = 127.0.0.1:80/server-status?auto
## host = $host:80/server-status?auto
## port = $host:$port/server-status?auto
## uri = $host:$port/$uri
##
##  Noteable Reference: https://httpd.apache.org/docs/2.4/mod/mod_status.html
##

helpArgs="/(-h|-\?|--help|--\?)/i"
trueArgs="/(t|1|True)/i"
falseArgs="/(f|0|False)/i"
portStatus="open"

## process arguments, or default values
host=""
if [[ "$1" ]]; then host="$1"; else host="127.0.0.1"; fi
port=""
if [[ "$2" ]]; then port="$2"; else port="80"; fi
uri=""
if [[ "$3" ]]; then uri="$3"; else uri="/server-status?auto"; fi

#echo "DEBUG: host [$host], port [$port], uri [$uri], 1 [$1], 2 [$2], 3 [$3]"

## print help string and exit
printHelp()
{
   echo -e "Usage: $0 [host=127.0.0.1] [port=80] [uri=/server-status?auto]\n\t(no parameters) = 127.0.0.1:80/server-status?auto\n\thost = \$host:80/server-status?auto\n\tport = \$host:\$port/server-status?auto\n\turi = \$host:\$port/\$uri\n"
}

## ensure we have a valid hostname/IP and port
if [[ $1 =~ $helpArgs ]]; then
    printHelp
    exit 0
elif [ -z "$host" ] || [ "$host" == "" ]; then
    echo -e "UNKNOWN: Blank hostname or IP address passed.\n"
    printHelp 
    exit 3
elif [ -z "$port" ] || [ "$port" == "" ]; then
    echo -e "UNKNOWN: Blank port passed. \n"
    printHelp
    exit 3
fi

## check port
{ exec 3<>"/dev/tcp/$host/$port"; } > /dev/null 2>&1 || portStatus="closed"

if [ "$portStatus" == "open" ]; then
    ## check http status code
    retCode=$(curl -s -o /dev/null -w "%{http_code}" "http://$host:$port/$uri")
    if [ "$retCode" == "200" ]; then
        stats=$(curl -s "http://$host:$port/$uri")
        IFS=$'\n'; read -r -d '' -a row <<< "$stats"
        
        # 1. Parse key:value pairs
        # 2. Parse "Scoreboard: ..." string, counting symbols (. _ S R W K D C L G I) and total length
        
        for r in "${row[@]}"; do  
            IFS=' ' read -r -a field <<< "$r"
            
            if [[ $r =~ 'Total Accesses' ]]; then 
                value="${field[2]// }"
                perfData="${perfData} totalAccesses=$value;"
            elif [[ $r =~ 'Total kBytes' ]]; then 
                value="${field[2]// }"
                perfData="${perfData} totalKBs=${value}KB;"
            elif [[ $r =~ 'CPULoad' ]]; then 
                value="${field[1]// }"
                value=$(bc <<< " scale=2; $value * 100.0 " 2>/dev/null)
                value=$(printf %0.2f "$value")
                perfData="${perfData} cpuLoad=$value%;"
            elif [[ $r =~ 'Uptime' ]]; then 
                value="${field[1]// }"
                perfData="${perfData} uptime=${value}s;"
            elif [[ $r =~ 'ReqPerSec' ]]; then 
                value="${field[1]// }"
                value=$(printf %0.2f "$value")
                perfData="${perfData} requestsPerSec=$value;"
            elif [[ $r =~ 'BytesPerSec' ]]; then 
                value="${field[1]// }"
                value=$(printf %0.2f "$value")
                perfData="${perfData} bytesPerSec=${value}B;"
            elif [[ $r =~ 'BytesPerReq' ]]; then 
                value="${field[1]// }"
                value=$(printf %0.2f "$value")
                perfData="${perfData} bytesPerRequest=${value}B;"
            elif [[ $r =~ 'BusyWorkers' ]]; then 
                value="${field[1]// }"
                perfData="${perfData} busyWorkers=$value;"
            elif [[ $r =~ 'IdleWorkers' ]]; then 
                value="${field[1]// }"
                perfData="${perfData} idleWorkers=$value;"
            elif [[ ${field[0]} =~ Scoreboard ]]; then
                sb="${field[1]// }"
                
                workersOpen=$(tr -dc '.' <<<"$sb" | awk '{ print length; }' 2>/dev/null);
                if [ -z "$workersOpen" ] || [ "$workersOpen" == "" ]; then workersOpen=0; fi
                perfData="${perfData} workersOpen=$workersOpen;"
                
                workersWaiting=$(tr -dc '_' <<<"$sb" | awk '{ print length; }' 2>/dev/null); 
                if [ -z "$workersWaiting" ] || [ "$workersWaiting" == "" ]; then workersWaiting=0; fi
                perfData="${perfData} workersWaiting=$workersWaiting;"
                
                workersStarting=$(tr -dc 'S' <<<"$sb" | awk '{ print length; }' 2>/dev/null); 
                if [ -z "$workersStarting" ] || [ "$workersStarting" == "" ]; then workersStarting=0; fi
                perfData="${perfData} workersStarting=$workersStarting;"
                
                workersReading=$(tr -dc 'R' <<<"$sb" | awk '{ print length; }' 2>/dev/null); 
                if [ -z "$workersReading" ] || [ "$workersReading" == "" ]; then workersReading=0; fi
                perfData="${perfData} workersReading=$workersReading;"
                
                workersSending=$(tr -dc 'W' <<<"$sb" | awk '{ print length; }' 2>/dev/null); 
                if [ -z "$workersSending" ] || [ "$workersSending" == "" ]; then workersSending=0; fi
                perfData="${perfData} workersSending=$workersSending;"
                
                workersKeepalive=$(tr -dc 'K' <<<"$sb" | awk '{ print length; }' 2>/dev/null); 
                if [ -z "$workersKeepalive" ] || [ "$workersKeepalive" == "" ]; then workersKeepalive=0; fi
                perfData="${perfData} workersKeepalive=$workersKeepalive;"
                
                workersDNSlookup=$(tr -dc 'D' <<<"$sb" | awk '{ print length; }' 2>/dev/null); 
                if [ -z "$workersDNSlookup" ] || [ "$workersDNSlookup" == "" ]; then workersDNSlookup=0; fi
                perfData="${perfData} workersDNSlookup=$workersDNSlookup;"
                
                workersLosing=$(tr -dc 'C' <<<"$sb" | awk '{ print length; }' 2>/dev/null); 
                if [ -z "$workersLosing" ] || [ "$workersLosing" == "" ]; then workersLosing=0; fi
                perfData="${perfData} workersLosing=$workersLosing;"
                
                workersLogging=$(tr -dc 'L' <<<"$sb" | awk '{ print length; }' 2>/dev/null); 
                if [ -z "$workersLogging" ] || [ "$workersLogging" == "" ]; then workersLogging=0; fi
                perfData="${perfData} workersLogging=$workersLogging;"
                
                workersFinishing=$(tr -dc 'G' <<<"$sb" | awk '{ print length; }' 2>/dev/null); 
                if [ -z "$workersFinishing" ] || [ "$workersFinishing" == "" ]; then workersFinishing=0; fi
                perfData="${perfData} workersFinishing=$workersFinishing;"
                
                workersIdleCleanup=$(tr -dc 'I' <<<"$sb" | awk '{ print length; }' 2>/dev/null); 
                if [ -z "$workersIdleCleanup" ] || [ "$workersIdleCleanup" == "" ]; then workersIdleCleanup=0; fi
                perfData="${perfData} workersIdleCleanup=$workersIdleCleanup;"
                
                perfData="${perfData} workersTotal=${#sb};"
            fi
        done

        echo "OK: apache status|$perfData"
        exit 0
    else
        echo "WARNING: http://$host:$port/$uri returned a status code '$retCode' instead of 200."
        exit 1
    fi
else
    echo "CRITICAL: http://$host:$port is not responding."
    exit 2
fi

echo "UNKNOWN: Could not reach http://$host:$port"
exit 3