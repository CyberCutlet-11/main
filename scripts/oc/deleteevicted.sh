#!/bin/bash
#delete evicted pods current project
for n in $(oc get pod | grep Evicted | awk '{print $1}')
do
    oc delete pod $n
done