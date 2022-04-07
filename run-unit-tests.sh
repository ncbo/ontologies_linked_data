#!/bin/bash
# sample script to run unit tests with docker

# unit test expects config file even though all settings are set via env vars.
[ -f config/config.rb ] || cp config/config.rb.sample config/config.rb

# generate solr configsets for solr container
test/solr/generate_ncbo_configsets.sh

# build docker containers
docker-compose build

#docker-compose up --exit-code-from test
#docker-compose run --rm test wait-for-it solr-ut:8983 -- bundle exec rake test TESTOPTS='-v'
docker-compose run --rm test wait-for-it solr-ut:8983 -- bundle exec rake test

docker-compose down
