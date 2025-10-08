#!/bin/bash

#echo "${0}"
#echo "${1}"
#exit

# Check to make sure this script is running as root.
if [[ `id -u` -ne 0 ]]; then
    echo -e "\n${0##*/}: Error - This script must be run as root. Try again with 'sudo ${0}'."
    exit 1
fi

# reset CONTINUE before continuing, so that we have an easy way to see
# whether the Elasticsearch service startup timeout was already set to 600
# seconds but the user continued anyway.

# Check the /usr/lib/systemd/system/elasticsearch.service file to see if the
# Elasticsearch service startup timeout is already set to 600 seconds.
if [[ `grep -Po "(?<=^TimeoutStartSec=).*$" /usr/lib/systemd/system/elasticsearch.service` -eq 600 ]]; then

    while true; do
        read -r -p "The /usr/lib/systemd/system/elasticsearch.service setting for TimeoutStartSec is already 600 seconds. Continue anyway? (y/N) " CONTINUE

        if [[ "${CONTINUE}" =~ ^[yYnN]{0,1}$ ]]; then
            break
        else
            echo "Invalid input. Please use only 'y' or 'n'."
        fi
    done

    if [[ "${CONTINUE,,}" != "y" ]]; then
        exit 0
    fi
fi

# If the /usr/lib/systemd/system/elasticsearch.service setting for Elasticsearch
# service startup timeout isn't already 600 seconds (changed from the 75 seconds
# set in the CDNWv4 VM as distributed), then change it to 75 seconds and reload
# the service configuration.
if [[ "${CONTINUE,,}" != "y" ]]; then
    echo "Updating /usr/lib/systemd/system/elasticsearch.service ..."

    sed -i 's/^TimeoutStartSec=.*$/TimeoutStartSec=600/' /usr/lib/systemd/system/elasticsearch.service

    if [[ "${?}" -ne 0 ]]; then
        echo -e "Error updating update /usr/lib/systemd/system/elasticsearch.service."
        exit 2
    fi

    # Reload systemd services configuration.
    echo "Reloading systemd services configuration ..."

    systemctl daemon-reload

    if [[ "${?}" -ne 0 ]]; then
        echo -e "Error reloading systemd services configuration."
        exit 3
    fi
fi

# Restart the Elasticsearch service.
echo "Restarting the Elasticsearch service (this may take a minute) ..."

systemctl restart elasticsearch.service

if [[ "${?}" -ne 0 ]]; then
   echo -e "Error restarting elasticsearch.service."
   exit 4
fi

# Test to make sure Elasticsearch is running.
if [[ `ps -ef | grep -c "^elastic"` -eq 0 ]]; then
   echo -e "Error - No elastic processes found after restart."
   exit 5
fi

# Test to make sure Elasticsearch is responding.
ELASTIC_RESPONSE=$(curl -s -XGET http://localhost:9200)

if [[ "${ELASTIC_RESPONSE}" != '{"error":{"root_cause":[{"type":"security_exception","reason":"missing authentication credentials for REST request [/]","header":{"WWW-Authenticate":"Basic realm=\"security\" charset=\"UTF-8\""}}],"type":"security_exception","reason":"missing authentication credentials for REST request [/]","header":{"WWW-Authenticate":"Basic realm=\"security\" charset=\"UTF-8\""}},"status":401}' ]]; then

    echo -e "\n${0##*/}: After restart, Elasticsearch query didn't return expected response."
    echo -e "-----start-----\n${ELASTIC_RESPONSE}\n-----end-----"
    exit 6
fi

# Restart the Kibana service.
echo "Restarting the Kibana service (this may take a few seconds) ..."

systemctl restart kibana.service

if [[ "${?}" -ne 0 ]]; then
   echo -e "Error restarting kibana.service."
   exit 7
fi

# Test to make sure Kibana is running.
if [[ `ps -ef | grep -c "^kibana"` -eq 0 ]]; then
   echo -e "Error - No kibana processes found after restart."
   exit 8
fi

# Loop for 5 minutes max to test whether sure Kibana is responding.
MAX_TIME=$(( `date +%s` + 600 ))
KIBANA_RESPONSE=

while [ `date +%s` -lt "${MAX_TIME}" ]; do
    echo "Waiting on Kibana web service check ..."

    # retrieve the first line of output from Kibana's status page
    KIBANA_RESPONSE=$(curl -s -XGET --user elastic:NightGathers localhost/status | head -n 10)

    # if '-verbose' was used as an argument the display the output
    if [[ "${1}" == "-verbose" ]]; then
        echo -e "\n-----start-----\n${KIBANA_RESPONSE}\n-----end-----\n"
    fi

    # exit if the output matches what we expect
    if [[ `echo "${KIBANA_RESPONSE}" | head -n 1` == '<!DOCTYPE html><html lang="en"><head><meta charSet="utf-8"/><meta http-equiv="X-UA-Compatible" content="IE=edge,chrome=1"/><meta name="viewport" content="width=device-width"/><title>Elastic</title><style>' ]]; then
        KIBANA_RESPONSE="<the check cleared>"
        break
    fi

    # sleep for 5 seconds before trying again
    sleep 5
done

# did the Kibana web service check pass?
if [[ "${KIBANA_RESPONSE}" == "<the check cleared>" ]]; then
    echo -e "Kibana is ready!"
else
    echo -e "ERROR: Kibana is still not ready."
    exit 9
fi

exit
