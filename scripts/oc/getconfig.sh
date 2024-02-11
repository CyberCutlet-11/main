#!/bin/bash
#get configs of currents project
for n in $(oc get -o=name DaemonSet,Deployment,ReplicaSet,StatefulSet,CronJob,Job,NetworkPolicy,DeploymentConfig,Route,Gateway,VirtualService,DestinationRule,ServiceEntry,Sidecar,EnvoyFilter,ConfigMap,Service)
do
    project=$(oc project | awk -F '"' '{print $2}')
    dirname=$(dirname $n)
    mkdir -p $project/$dirname
    oc get -o=yaml $n > $project/$n.yaml
done