#!/usr/bin/python

##
## Author: Beau Bilyeu (beau.bilyeu@gmail.com)
## Usage:    ./check_haproxy.py /path/to/haproxy_stats.sock
##
## Noteable Reference: https://www.datadoghq.com/blog/monitoring-haproxy-performance-metrics/#frontend-metrics
##

from __future__ import unicode_literals
import sys
import os.path
import re

## import socket 
try:
    import socket
except ImportError, e:
    print("UNKNOWN: 'socket' python library not installed.")
    exit(3)

## import csv 
try:
    import csv
except ImportError, e:
    print("UNKNOWN: 'csv' python library not installed.")
    exit(3)
    
## import StringIO 
try:
    # for Python 2.x
    from StringIO import StringIO
except ImportError:
    # for Python 3.x
    from io import StringIO    
    
    
class HAProxyPool:
    proxyName = ""          # pxname
    hasBackend = False
    hasNode = False
    downNodes = []
    
    #### frontend stats ####
    requestPerSec = 0       # req_rate
    sessionPerSec = 0       # rate
    sessionUtilization = -1 # scur / slim * 100
    requestErrors = 0       # ereq
    requestsDenied = 0      # dreq
    returnCode400 = 0       # hrsp_4xx
    returnCode500 = 0       # hrsp_5xx
    bytesIn = 0             # bin
    bytesOut = 0            # hrsp_5xx
    
    #### backend stats ####
    responseTimeMS = -1     # rtime (v1.5 min)
    errorConnAttempts = 0   # econ
    denyResponses = 0       # dresp
    errorResponses = 0      # eresp
    reqsWaitingInQueue = 0  # qcur
    avgReqWaitTimeMS = -1   # qtime (v1.5 min)
    reqRedispatches = 0     # wredis
    reqConnRetried = 0      # wretr
    
    
    def __init__(self):
        self.data = []
        
    # requires BACKEND and at least one server/listener in UP state
    def isComplete(self):
        return (self.hasBackend and self.hasNode)
### END class HAProxyPool
    
def help ():
    print("Usage: " + os.path.basename(__file__) + " /path/to/haproxy_stats.sock")
    exit(0)

## ensure enough arguments are passed
if len(sys.argv) != 2:
    print("Invalid number of arguments.")
    help()
else:
    sockPath = sys.argv[1]
    pools = {}
    
    if os.path.exists(sockPath):
        sendStr = "show stat\;"
        
        ## create connection
        try:
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)   ## create unbound socket
            s.connect(sockPath)                                     ## connect to the passed socket
        except socket.error, msg:
            print("UNKNOWN: Failed to create a socket connection to '" + sockPath + "'.")
            exit(3)
        
        ## send "show stats" and accept return data
        try:
            eofReceived = False
            reply = ""
            sanity = 10
            totalsent = 0
            
            while totalsent < len(sendStr):
                sent = s.send(sendStr[totalsent:])
                if sent == 0:
                        print("CRITICAL: Socket connection broken!")
                        exit(2)
                totalsent = totalsent + sent
            
            while not eofReceived:
                sanity -= 1
                data = s.recv(4096)
                #print("data: " + data) ## DEBUG
                
                ## if no data, skip
                if len(data) > 0:
                    reply += data
                    ## haproxy's stats output is delimited by a newline (per docs)
                    ##  so double newline is the last line, followed by EOT newline
                    if "\n\n" in data:      
                        eofReceived = True
                        
                ## if it looped 10 time and did not get a reply/full-reply, something is wrong
                if sanity <= 0:
                    print("CRITICAL: Did not receive an 'eof' in reply. Exiting to prevent loop.")
                    exit(2)
        except socket.error, msg:
            print("CRITICAL: Failed to poll stats from '" + sockPath + "'. Error [" + str(msg) + "]")
            exit(2)
    ## END if option = "-s"
    else:
        ## ye dun goofed path
        print("UNKNOWN: No socket found at path '" + sockPath + "'.")
        exit(3)

    ## ensure that it actually has data
    ##  then parse it
    if reply != "":
        csvData = StringIO(reply[2:])
        reader = csv.DictReader(csvData)
        for row in reader:
            ## first check existence in pools dict
            if row['pxname'] not in pools.keys():
                pools[row['pxname']] = HAProxyPool()
                pools[row['pxname']].proxyName = row['pxname']

            ### update HAPP 'complete' state ###
            ## if down/no-LB appears, add it to the down nodes list and skip
            if row['status'] == "DOWN" or row['status'] == "NOLB":
                pools[row['pxname']].downNodes.append(row['svname'])
                continue
            elif row['svname'] == "BACKEND" and row['status'] == "UP":
                ## BACKEND metrics
                pools[row['pxname']].hasBackend = True
                if "rtime" in row.keys():   ## version dependent
                    pools[row['pxname']].responseTimeMS = row['rtime']
                if "qtime" in row.keys():   ## version dependent
                    pools[row['pxname']].avgReqWaitTimeMS = row['qtime']
                pools[row['pxname']].errorConnAttempts = row['econ'] if 'econ' in row.keys() and row['econ'] != "" else 0
                pools[row['pxname']].denyResponses = row['dresp'] if 'dresp' in row.keys() and row['dresp'] != "" else 0
                pools[row['pxname']].errorResponses = row['eresp'] if 'eresp' in row.keys() and row['eresp'] != "" else 0
                pools[row['pxname']].reqsWaitingInQueue = row['qcur'] if 'qcur' in row.keys() and row['qcur'] != "" else 0
                pools[row['pxname']].reqRedispatches = row['wredis'] if 'wredis' in row.keys() and row['wredis'] != "" else 0
                pools[row['pxname']].reqConnRetried = row['wretr'] if 'wretr' in row.keys() and row['wretr'] != "" else 0
            elif row['svname'] != "BACKEND" and row['svname'] != "FRONTEND" and row['status'] == "UP":
                ### node/server/listener metrics
                pools[row['pxname']].hasNode = True
                pools[row['pxname']].requestPerSec = row['req_rate'] if 'req_rate' in row.keys() and row['req_rate'] != "" else 0
                pools[row['pxname']].sessionPerSec = row['rate'] if 'rate' in row.keys() and row['rate'] != "" else 0
                pools[row['pxname']].requestErrors = row['ereq'] if 'ereq' in row.keys() and row['ereq'] != "" else 0
                pools[row['pxname']].requestsDenied = row['dreq'] if 'dreq' in row.keys() and row['dreq'] != "" else 0
                pools[row['pxname']].returnCode400 = row['hrsp_4xx'] if 'hrsp_4xx' in row.keys() and row['hrsp_4xx'] != "" else 0
                pools[row['pxname']].returnCode500 = row['hrsp_5xx'] if 'hrsp_5xx' in row.keys() and row['hrsp_5xx'] != "" else 0
                pools[row['pxname']].bytesIn = row['bin'] if 'bin' in row.keys() and row['bin'] != "" else 0
                pools[row['pxname']].bytesOut = row['bout'] if 'bout' in row.keys() and row['bout'] != "" else 0

                ## calculate sessions utilization, if metrics available.
                if "scur" in row.keys() and row['scur'] != "" and "slim" in row.keys() and row['slim'] != "":
                    if row['scur'] > 0 and row['slim'] > 0:
                        pools[row['pxname']].sessionUtilization = (float(row['scur']) / float(row['slim'])) * 100
        ## END "for row in reader:"

        ## building output string
        perfData = ""
        warningData = ""
        criticalData = ""
        okData = ""
        for p in pools:
            if pools[p].isComplete():
                ## node/server/listener
                if pools[p].sessionUtilization > 0:
                    perfData += " " + pools[p].proxyName + "_sessionUtil=" + str(pools[p].sessionUtilization) + "%"
                perfData += " " + pools[p].proxyName + "_req_rate=" + str(pools[p].requestPerSec)
                perfData += " " + pools[p].proxyName + "_rate=" + str(pools[p].sessionPerSec)
                perfData += " " + pools[p].proxyName + "_ereq=" + str(pools[p].requestErrors)
                perfData += " " + pools[p].proxyName + "_dreq=" + str(pools[p].requestsDenied)
                perfData += " " + pools[p].proxyName + "_hsrp_4xx=" + str(pools[p].returnCode400)
                perfData += " " + pools[p].proxyName + "_hsrp_5xx=" + str(pools[p].returnCode500)
                perfData += " " + pools[p].proxyName + "_bin=" + str(pools[p].bytesIn) + "B"
                perfData += " " + pools[p].proxyName + "_bout=" + str(pools[p].bytesOut) + "B"
                ## BACKEND
                if pools[p].responseTimeMS > 0:
                    perfData += " " + pools[p].proxyName + "_rtime=" + str(pools[p].responseTimeMS) + "ms"
                if pools[p].avgReqWaitTimeMS > 0:
                    perfData += " " + pools[p].proxyName + "_qtime=" + str(pools[p].avgReqWaitTimeMS) + "ms"
                perfData += " " + pools[p].proxyName + "_econ=" + str(pools[p].errorConnAttempts)
                perfData += " " + pools[p].proxyName + "_dresp=" + str(pools[p].denyResponses)
                perfData += " " + pools[p].proxyName + "_eresp=" + str(pools[p].errorResponses)
                perfData += " " + pools[p].proxyName + "_qcur=" + str(pools[p].reqsWaitingInQueue)
                perfData += " " + pools[p].proxyName + "_wredis=" + str(pools[p].errorConnAttempts)
                perfData += " " + pools[p].proxyName + "_wretr=" + str(pools[p].reqConnRetried)
                ## Downed nodes
                if len(pools[p].downNodes) > 0:
                    criticalData += " " + pools[p].proxyName + "-pool NODES DOWN :"
                    for d in pools[p].downNodes:
                        criticalData += " " + d + ","
                else:
                    okData += " " + pools[p].proxyName + "-pool OK,"

        if criticalData == "":
            print("OK: " + okData[0:-1] + "|" + perfData)
            exit(0)
        else:
            print("CRITICAL: " + criticalData[0:-1] + "|" + perfData)
            exit(2)

    else: 
        print("CRITICAL: Received data, but misplaced it before parsing")
        exit(2)