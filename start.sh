#!/bin/bash
shopt -s expand_aliases
set -E

# Variables
docker_ip=$(docker-machine ip default)
kibana=http://$docker_ip:9200/.kibana

logstash_version=2.1.0
logstash_name=logstash-$logstash_version
logstash_url=https://download.elastic.co/logstash/logstash/$logstash_name.tar.gz 

apache_logs=https://s3-eu-west-1.amazonaws.com/skyscanner-recruitement-resources/devops/access-log-example/c930ecf4b0a4426e619bddd8752c475ea772427db13eb92ee6a1a79b248ec0dc/access.log
docker rm -f elk > /dev/null

# Start ELK stack first so that it's ready for us
echo "Downloading ELK docker image"
docker pull sebp/elk > /dev/null

echo "Starting ELK stack..."
docker run -p 5601:5601 -p 9200:9200 -p 5000:5000 --name elk -d sebp/elk > /dev/null

echo "Waiting for elastic search to start up"
until $(curl --output /dev/null --silent --head --fail http://$docker_ip:9200); do
printf '.'
   sleep 5
done


echo "Creating folder logs (if it doesn't exist"
if [ ! -d logs ]; then mkdir logs; fi

if [ ! -f ./logs/access.log ]
then
    curl -L --silent $apache_logs > ./logs/access.log
fi

if [ -f $logstash_name.tar.gz ];
then 
    echo "Logstash already downloaded"
else
    echo "Download Logstash locally from $logstash_url"
    # curl -LO $logstash_url
fi

alias qcurl="curl --silent --output /dev/null"

echo "Extracting logstash"
tar xf $logstash_name.tar.gz

echo "[Kibana] Configuring default index pattern in kibana"
qcurl -X PUT $kibana/config/4.3.0 -d '{ "defaultIndex": "logstash-*" }'

echo "[Kibana] Uploading index pattern"
qcurl -X POST $kibana/index-pattern/logstash-* -d @kibana-configuration/index-pattern.json

echo "[Kibana] Uploading configuration that allows exports"
qcurl -X PUT $kibana/settigs < kibana-configuration/settings.json

echo "[Kibana] Uploading visualisations"
qcurl -X POST $kibana/visualization/Bytes-per-minute -d @kibana-configuration/bytes-per-minute.json
qcurl -X POST $kibana/visualization/Mean-response-time-per-minute -d @kibana-configuration/mean-response-time.json
qcurl -X POST $kibana/visualization/Success-vs-Error-over-time -d @kibana-configuration/success-vs-error.json

echo "[Kibana] Uploading searches"
qcurl -X POST $kibana/search/Requests -d @kibana-configuration/requests-table.json

echo "[Kibana] Uploading Dashboards"
qcurl -X POST $kibana/dashboard/Sky-Dashboard -d @kibana-configuration/dashboard.json

echo "Will upload logstash results in the background and open Kibana dashboard in your default browser in 5 seconds"
./logstash-$logstash_version/bin/logstash -f logstash.conf < logs/access.log 2>&1 /dev/null &
sleep 5

open "http://$docker_ip:5601/app/kibana#/dashboard/Sky-Dashboard?_g=(refreshInterval:(display:'5%20seconds',pause:!f,section:1,value:5000))"


