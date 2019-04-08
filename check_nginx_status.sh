#!/bin/bash

##
## Author: Beau Bilyeu (beau.bilyeu@gmail.com)
## Usage: ./check_nginx_status.sh [host=127.0.0.1] [port=80] [uri=/nginx_status]
##
## (none) = 127.0.0.1:80/nginx_status
## host = $host:80/nginx_status
## port = $host:$port/nginx_status
## uri = $host:$port/$uri
##
##  Noteable Reference: https://www.keycdn.com/support/nginx-status
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
if [[ "$3" ]]; then uri="$3"; else uri="/nginx_status"; fi

#echo "DEBUG: host [$host], port [$port], uri [$uri], 1 [$1], 2 [$2], 3 [$3]"

## print help string and exit
printHelp()
{
   echo -e "Usage: $0 [host=127.0.0.1] [port=80] [uri=/nginx_status]\n\t(no parameters) = 127.0.0.1:80/nginx_status\n\thost = \$host:80/nginx_status\n\tport = \$host:\$port/nginx_status\n\turi = \$host:\$port/\$uri\n"
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
        
        actConnPattern="Active connection"
        metricsPattern="^ [0-9]"
        rwwPattern="^Reading"
        for r in "${row[@]}"; do  
            IFS=' ' read -r -a field <<< "$r"
            if [[ $r =~ $actConnPattern ]]; then 
                value="${field[2]// }"
                perfData="${perfData} activeConn=$value;"
            elif [[ $r =~ $metricsPattern ]]; then
                ## server accepts
                value="${field[0]}"
                perfData="${perfData} accepts=$value;"
                ## server handled
                value="${field[1]// }"
                perfData="${perfData} handled=$value;"
                ## server requests
                value="${field[2]// }"
                perfData="${perfData} requests=$value;"
            elif [[ $r =~ $rwwPattern ]]; then
                value="${field[1]// }"
                perfData="${perfData} reading=$value;"
                value="${field[3]// }"
                perfData="${perfData} writing=$value;"
                value="${field[5]// }"
                perfData="${perfData} waiting=$value;"
            fi
        done

        echo "OK: nginx_status|$perfData"
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