#!/usr/bin/env bash
# Converted by Beau Bilyeu (beau.bilyeu@gmail.com) to cover all use cases for
#   polling graphite-bound Java stats
#
# Collect metrics on your JVM and allow you to trace usage in graphite
# Modified: Mario Harvey - badmadrad.com
#
# You must have openjdk-7-jdk and openjdk-7-jre packages installed
# http://openjdk.java.net/install/
#
#  Example Use: ./java-graphite.sh -t systemd -n jira.somedomain.com -r 'TotalHeap'
#    Ex Output: jvm.jira.zii.aero.heap.Committed_Heap 6144


# Also make sure the user "sensu" can ${SUDO} without password
while getopts 't:n:r:h:' OPT; do
case $OPT in
t) TYPE=$OPTARG;;
n) NAME=$OPTARG;;
h) hlp="yes";;
*) echo "$HELP"; exit 1;;
esac
done
#usage
HELP="
        usage $0 [ -t type -n value -h ]
                -t --> TYPE of check (command, daemontools, or systemd)
                -n --> NAME or name of jvm process < value
                -h --> print this help screen
"
if [ "$hlp" == "yes" ]; then
        echo "$HELP"
        exit 0
fi

## Debug line
#echo -e "Type: '$TYPE'\nReturn: '$RETURN'\nName: '$NAME'"

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

## Exit on error that no PID was found
if [ -z "$PID" ] || [ "$PID" == "" ]; then
    (>&2 echo "CRITICAL: No PID found for '$NAME' with type '$TYPE'")
    exit 2
fi

# Get the UID & associated user running the JVM.
PUID=$(grep Uid /proc/${PID}/status | awk '{print $2}')
USER=$(getent passwd ${PUID} | awk -F: '{ print $1 }')
# Get heap capacity of JVM
TotalHeap=$(su ${USER} -c "${jstat} -gccapacity $PID  | tail -n 1 | awk '{ print (\$4 + \$5 + \$6 + \$10) / 1024 }'" 2>/dev/null)
HeapStats=$(su ${USER} -c "${jstat} -gc $PID  | tail -n 1" 2>/dev/null)

UsedHeap=$( echo ${HeapStats} | awk '{ print ($3 + $4 + $6 + $8 + $10) / 1024 }')
ParEden=$( echo ${HeapStats} | awk '{ print ($6) / 1024 }')
ParSur=$( echo ${HeapStats} | awk '{ print ($3 + $4) / 1024 }')
OldGen=$( echo ${HeapStats} | awk '{ print ($8) / 1024 }')
PermGen=$( echo ${HeapStats} | awk '{ print ($10) / 1024 }')

perfdata=""
perfdata="${perfdata} heap=${UsedHeap}MB;0;0;0;${TotalHeap}"
perfdata="${perfdata} edenutil=${ParEden}"
perfdata="${perfdata} survivorutil=${ParSur}"
perfdata="${perfdata} oldutil=${OldGen}"
perfdata="${perfdata} permutil=${PermGen}"

echo "OK: $NAME|$perfdata"

# exit normally
exit 0