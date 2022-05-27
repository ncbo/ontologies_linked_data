#!/bin/bash
# sample script to run unit tests with docker

#DC='docker-compose --profile 4store'
DC='docker-compose'

# unit test expects config file even though all settings are set via env vars.
[ -f config/config.rb ] || cp config/config.rb.sample config/config.rb

# generate solr configsets for solr container
test/solr/generate_ncbo_configsets.sh

# build docker containers
#$DC up --build -d
#$DC run --rm ruby wait-for-it solr-ut:8983 -- bundle exec rake test TESTOPTS='-v' TEST='./test/models/test_mappings.rb'
$DC run --rm ruby wait-for-it solr-ut:8983 -- bundle exec rake test TESTOPTS='-v'
#$DC down
