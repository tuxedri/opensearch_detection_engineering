ARG LOGSTASH_VERSION=8.19.21
FROM docker.elastic.co/logstash/logstash:${LOGSTASH_VERSION}

RUN bin/logstash-plugin install --version 2.1.1 logstash-output-opensearch
