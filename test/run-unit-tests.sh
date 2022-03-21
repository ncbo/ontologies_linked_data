#!/bin/bash
# sample script to run unit tests with docker

# add config for unit testing
[ -f ../config/config.rb ] || cp ../config/config.rb.sample ../config/config.rb

#generate solr configsets for solr container
solr/generate_ncbo_configsets.sh

# build docker containers
docker-compose build

#docker-compose up --exit-code-from unit-test
docker-compose run --rm ld-unit-test wait-for-it ld-solr-ut:8983 -- bundle exec rake test TESTOPTS='-v'

