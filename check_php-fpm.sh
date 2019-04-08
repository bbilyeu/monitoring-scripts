#!/bin/bash

##
## Author: Beau Bilyeu (beau.bilyeu@gmail.com)
## Usage: ./check_php-fpm.sh <url> <port> [-m]
##
## (none) = php-fpm State Check (is it up?)
## -m = Metrics
##

helpArgs="/(-h|-?|--help|--?)/i"
trueArgs="/(t|1|True)/i"
falseArgs="/(f|0|False)/i"

portStatus="open"
url="$1"
port="$2"

## print help string and exit
printHelp()
{
   echo -e "Usage: $0 <url> <port> [-m]\n\t(no parameters) = state check\n\t-m = Metrics"
}

## ensure we have a valid url and port
if [[ $1 =~ $helpArgs ]]; then
    printHelp
    exit 0
elif [ -z "$1" ] || [ "$1" == "" ]; then
    echo "UNKNOWN: No url or IP address passed."
    printHelp 
    exit 3
elif [ -z "$2" ] || [ "$2" == "" ]; then
    echo "UNKNOWN: No port passed."
    printHelp
    exit 3
elif [ -n "$1" ] && [ -n "$2" ]; then
    url="$1"
    port="$2"
fi

## check port
{ exec 3<>"/dev/tcp/$url/$port"; } > /dev/null 2>&1 || portStatus="closed"

if [ "$portStatus" == "open" ]; then
    ## check http status code
    retCode=$(curl -s -o /dev/null -w "%{http_code}" "http://$url:$port/php-fpm_status")
    if [ "$retCode" == "200" ]; then
        if [ "$3" == "-m" ]; then
            ## metrics check
            stats=$(curl -s "http://$url:$port/php-fpm_status")
            IFS=$'\n'; read -r -d '' -a row <<< "$stats"
            for r in "${row[@]}"; do  
                IFS=':' read -r -a field <<< "$r"
                value=$(echo "${field[1]}" | tr -d '[:space:]' )
                case "${field[0]}" in
                    "start since")          perfData="${perfData} startSince=${value}s;";;
                    "accepted conn")        perfData="${perfData} acceptedConn=${value};";;
                    "listen queue")         perfData="${perfData} listenQueue=${value};";;
                    "max listen queue")     perfData="${perfData} maxListenQueue=${value};";;
                    "listen queue len")     perfData="${perfData} listenQueueLen=${value};";;
                    "idle processes")       perfData="${perfData} idleProcs=${value};";;
                    "active processes")     perfData="${perfData} activeProcs=${value};";;
                    "total processes")      perfData="${perfData} totalProcs=${value};";;
                    "max active processes") perfData="${perfData} maxActiveProcs=${value};";;
                    "max children reached") perfData="${perfData} maxChildrenReached=${value};";;
                    "slow requests")        perfData="${perfData} slowRequests=${value};";;
                esac
            done
            
            echo "OK: php-fpm metrics|$perfData"
            exit 0
        else
            ## state check
            echo "OK: php-fpm is up"
            exit 0
        fi
    else
        echo "WARNING: http://$url:$port/php-fpm_status returned a status code '$retCode' instead of 200."
        exit 1
    fi
else
    echo "CRITICAL: http://$url:$port is not responding."
    exit 2
fi

echo "UNKNOWN: Could not reach http://$url:$port"
exit 3