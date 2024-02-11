#!/bin/bash
#delete evicted pods ALL PROJECTS
for i in $(oc get projects -o=name | awk -F '/' '{print $2}')
do
  oc project $i
  oc get pod | awk '{if ($3=="Evicted") print "oc delete pod " $1;}' | sh
done