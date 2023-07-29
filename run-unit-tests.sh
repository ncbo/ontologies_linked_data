#!/bin/bash
# sample script to run unit tests with docker

#DC='docker-compose --profile 4store'
DC='docker compose'

# unit test expects config file even though all settings are set via env vars.
[ -f config/config.rb ] || cp config/config.test.rb config/config.rb

# generate solr configsets for solr container
test/solr/generate_ncbo_configsets.sh

# build docker containers
$DC run --rm ruby bundle exec rake test TESTOPTS='-v'
# run unit test with AG backend
#$DC run --rm ruby-agraph bundle exec rake test TESTOPTS='-v'
$DC stop
