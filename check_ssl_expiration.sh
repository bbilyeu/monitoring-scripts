#!/bin/bash

##
## Author: Beau Bilyeu (beau.bilyeu@gmail.com)
## Usage: ./check_ssl_expiration.sh <hostname_or_ip> <domain> [port=443] [warn=30] [crit=10]
##
## (none) = prints helps
## hostname_or_ip = The server's hostname or IP address
## domain = Domain to check (e.g. www.mydomain.com)
## port = The port to check (default=443)
## warn = Throw warning if days left is equal to or less than this (default=30)
## crit = Throw critical if days left is equal to or less than this (default=10)
##
##
##  Noteable Referencs: 
##      https://linuxconfig.org/how-to-count-days-since-a-specific-date-until-today-using-bash-shell
##      https://www.shellhacks.com/openssl-check-ssl-certificate-expiration-date/
##

helpArgs="/(-h|-?|--help|--?)/i"
trueArgs="/(t|1|True)/i"
falseArgs="/(f|0|False)/i"

target=""
domain=""
port=443
warn=30
crit=10

## print help string and exit
printHelp()
{
   echo -e "Usage: $0 <hostname_or_ip> <domain> [port=443] [warn=30] [crit=10]\n\thostname_or_ip = The server's hostname or IP address\n\tdomain = Domain to check (e.g. www.mydomain.com)\n\tport = The port to check (default=443)\n\twarn = Throw warning if days left is equal to or less than this (default=30)\n\tcrit = Throw critical if days left is equal to or less than this (default=10)\n"
}

## int main()
if [[ $1 =~ $helpArgs ]]; then
    printHelp
    exit 0
elif [ -z "$1" ] || [ "$1" == "" ]; then
    echo "UNKNOWN: No hostname or IP address passed"
    printHelp 
    exit 3
elif [ -z "$2" ] || [ "$2" == "" ]; then
    echo "UNKNOWN: No domain passed"
    printHelp 
    exit 3
else
    target="$1"
    domain="$2"
    if [ -n "$3" ] && [ "$3" != "" ] && [[ $3 =~ ^[0-9]+$ ]]; then port="$3"; fi
    if [ -n "$4" ] && [ "$4" != "" ] && [[ $4 =~ ^[0-9]+$ ]]; then warn="$4"; fi
    if [ -n "$5" ] && [ "$5" != "" ] && [[ $5 =~ ^[0-9]+$ ]]; then crit="$5"; fi
fi


## catch time outs
if ! sslOutput=$(/bin/echo | timeout 10 /bin/openssl s_client -servername "$domain" -connect "$target":"$port" 2>/dev/null | /bin/openssl x509 -noout -dates 2>/dev/null | grep 'notAfter'); then
    echo "UNKNOWN: Timeout occurred attempting to reach '$target:$port'"
    exit 3
fi

## ensure we have output
if [ -z "$sslOutput" ] || [ "$sslOutput" == "" ]; then
    echo "UNKNOWN: Unable to load SSL certificate for '$domain' from '$target:$port'"
    exit 3
fi

## break out date and get days left
notAfter="${sslOutput:9}"
daysLeft=$(( ($(/bin/date +%s --date "$notAfter")-$(/bin/date +%s))/(3600*24) ))

## ensure we STILL have output
if [ -z "$daysLeft" ] || [ "$daysLeft" == "" ] || [[ ! $daysLeft =~ ^[0-9]+$ ]]; then
    echo "UNKNOWN: daysLeft is blank, though a date ($notAfter) was returned from the SSL certificate for '$domain' from '$target:$port'"
    exit 3
fi

if [ "$daysLeft" -le "0" ]; then
    echo "CRITICAL: The SSL certificate for '$domain' at '$target:$port' is expired."
    exit 2
elif [ "$daysLeft" -le "$crit" ]; then
    echo "CRITICAL: The SSL certificate for '$domain' at '$target:$port' has less than $crit days left ($daysLeft remaining)."
    exit 2
elif [ "$daysLeft" -le "$warn" ]; then
    echo "WARNING: The SSL certificate for '$domain' at '$target:$port' has less than $warn days left ($daysLeft remaining)."
    exit 1
else
    echo "OK: The SSL certificate for '$domain' at '$target:$port' has $daysLeft days left."
    exit 0
fi