#!/usr/bin/env bash
# Converted by Beau Bilyeu (beau.bilyeu@gmail.com) to cover all use 
#   cases for polling graphite-bound Java stats
#
# Collect metrics on your JVM and allow you to trace usage in graphite
# Modified: Mario Harvey - badmadrad.com
#
# You must have openjdk-7-jdk and openjdk-7-jre packages installed
# http://openjdk.java.net/install/
#
#  Example Use: ./java-pct -t systemd -w 90 -c 95 -n jira.somedomain.com 
#    Ex Output: HEAP OK - jvm heap usage: 73% | 4499.92 MB out of 6144 MB


# Also make sure the user "sensu" can ${SUDO} without password
while getopts 't:w:c:n:hp' OPT; do
  case $OPT in
    t)  TYPE=$OPTARG;;
    w)  WARN=$OPTARG;;
    c)  CRIT=$OPTARG;;
    n)  NAME=$OPTARG;;
    h)  hlp="yes";;
    *)  unknown="yes";;
  esac
done

# usage
HELP="
    usage: $0 [ -t type -n value -w value -c value -p -h ]

        -n --> Name of JVM process < value
        -w --> Warning Percentage < value
        -c --> Critical Percentage < value
        -h --> print this help screen
"

if [ "$hlp" == "yes" ]; then
        echo "$HELP"
        exit 0
fi

## ensure we have a valid type
if [ "$TYPE" != "command" ] && [ "$TYPE" != "daemontools" ] && [ "$TYPE" != "systemd" ]; then
    echo -e "Invalid type. Type must be 'command', 'daemontools', or 'systemd'.$HELP"
    exit 1
fi

[ -r /etc/profile.d/java.sh ] && . /etc/profile.d/java.sh
export PATH=${PATH}:/usr/local/bin

NAME=${NAME:=0}
PID=0
RETVAL=""

# Get the absolute path to needed binaries to avoid sudo pathing weirdness later on
svstat=$(command -v svstat 2>/dev/null)
jstat=$(command -v jstat 2>/dev/null)

if [ -z "$svstat" ] && [ -z "$jstat" ]; then
    echo -e "ERROR: jstat and svstat not installed\n"
    exit 1
fi

# Get PID of JVM.
case $TYPE in
command) PID=$(ps aux | grep "${NAME}" | grep -v grep | grep -v "${0}" | awk '{print $2}');;
daemontools) PID=$(${svstat} /service/j2ee_${NAME}/ 2>/dev/null | grep -oP "\(pid \d*\)" | grep -oP "\d+");;
systemd) PID=$(systemctl status -n 0 j2ee_${NAME}.service 2>/dev/null | grep PID | awk '{ print $3 }');;
esac

# Get the UID & associated user running the JVM.
PUID=$(grep Uid /proc/${PID}/status | awk '{print $2}')
USER=$(getent passwd ${PUID} | awk -F: '{ print $1 }')
# Get heap capacity of JVM
TotalHeap=$(su ${USER} -c "${jstat} -gccapacity $PID  | tail -n 1 | awk '{ print (\$4 + \$5 + \$6 + \$10) / 1024 }'" 2> /dev/null)
UsedHeap=$(su ${USER} -c "${jstat} -gc ${PID}  | tail -n 1 | awk '{ print (\$3 + \$4 + \$6 + \$8) / 1024 }'" 2> /dev/null)
HeapPer=$(echo "scale=3; $UsedHeap / $TotalHeap * 100" | bc -l| cut -d "." -f1)
WarnTotalHeap=$(echo "scale=3; $TotalHeap * $WARN * 0.01" | bc -l| cut -d "." -f1)
CritTotalHeap=$(echo "scale=3; $TotalHeap * $CRIT * 0.01" | bc -l| cut -d "." -f1)

if [ "$HeapPer" = "" ]; then
  echo "HEAP UNKNOWN -"
  exit 3
fi

## output line
output="jvm heap usage: $HeapPer% | heap_usage="$HeapPer"%;$WARN;$CRIT;0 heap_mb=${UsedHeap}MB;$WarnTotalHeap;$CritTotalHeap;0;$TotalHeap"

if (( $HeapPer >= $CRIT )); then
  echo "HEAP CRITICAL - $output"
  exit 2
elif (( $HeapPer >= $WARN )); then
  echo "HEAP WARNING - $output"
  exit 1
else
  echo "HEAP OK - $output"
  exit 0
fi

# exit normally
exit 0