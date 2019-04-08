#!/bin/bash
##
## FILE: check_nfs.sh
##
## DESCRIPTION: This is a nagios compatible script to checks NFS mounts against what
##                          should be mounted in /etc/fstab and if there is a stale mount.
##
## ORIGINAL AUTHOR: Dennis Ruzeski (denniruz@gmail.com)##
## Original Creation Date: 1/23/2013
##
## Last Modified: 2019-04-01 by Beau Bilyeu (beau.bilyeu@gmail.com)
##
## VERSION: 1.1
##
## USAGE: ./check_nfs.sh
##        This version takes no arguments
##
## This was modified to fulfill the issues with stale mount detection the original author had in the previous ToDo.
## The original code is still here, just commented out.
##

critCount=0
warnCount=0
declare -a nfs_mounts=( $(grep -v ^\# /etc/fstab |grep nfs |awk '{print $2}') )
declare -a MNT_STATUS   ## Mount
declare -a SFH_STATUS   ## State File Handle
declare -a BMNT_STATUS  ## Bad Mount

for mount_type in "${nfs_mounts[@]}"; do
    mountTest=$(stat -f -c '%T' "${mount_type}" 2>&1)
    if [ "$mountTest" == "nfs" ]; then
        if ! stat -t "${mount_type}" > /dev/null 2>&1; then
            ## add warning to error output array
            SFH_STATUS=("${SFH_STATUS[@]}" "${mount_type} might be stale.")
            warnCount=$((warnCount+1))
        else
            ## add 'ok' to ok output array
            MNT_STATUS=("${MNT_STATUS[@]}" "${mount_type} is ok.")
        fi
    elif [[ $mountTest =~ Stale ]]; then 
        ## definitively stale mount via out (ex: "stat: cannot stat '/mnt/nfs/logs/jira3/': Stale file handle")
        SFH_STATUS=("${SFH_STATUS[@]}" "${mount_type} is stale.")
        critCount=$((critCount+1))
    else
        ## something went way off
        BMNT_STATUS=("${BMNT_STATUS[@]}" "${mount_type} is not properly mounted.")
        critCount=$((critCount+1))
    fi
done

## exit block
if [ $critCount -gt 0 ]; then
    echo "CRITICAL: NFS mounts are stale or unavailable." "${SFH_STATUS[@]}" "${BMNT_STATUS[@]}" 
    exit 2
elif [ $critCount -eq 0 ] && [ $warnCount -gt 0 ]; then
    echo "WARNING: NFS mounts may be stale." "${SFH_STATUS[@]}" "${MNT_STATUS[@]}" 
    exit 1
elif [ $critCount -eq 0 ] && [ $warnCount -eq 0 ] && [ "${#MNT_STATUS[@]}" -gt 0 ]; then
    echo "OK: NFS mounts are functioning within normal operating parameters." "${MNT_STATUS[@]}" 
    exit 0
else 
    echo "UNKNOWN: No NFS mounts, active or stale, could be found."
    exit 3
fi
