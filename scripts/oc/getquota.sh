#!/bin/bash
#get all projects quota
for i in $(oc get projects -o=name | awk -F '/' '{print $2}')
do
    oc project $i
    oc get resourcequotas
    echo -en '\n'
done