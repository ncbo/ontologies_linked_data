#!/bin/bash
# generates solr configsets by merging _default configset with config files in config/solr
# _default is copied from sorl distribuion solr-8.10.1/server/solr/configsets/_default/

#cd solr/configsets
ld_config='../config/solr'
[ -d solr/configsets/property_search ] && rm -Rf solr/configsets/property_search
[ -d solr/configsets/term_search ] && rm -Rf solr/configsets/term_search
if [[ ! -d ${ld_config}/property_search ]]; then
  echo 'cant find ld solr config sets'
  exit 1
fi
if [[ ! -d solr/configsets/_default/conf ]]; then
  echo 'cant find default solr configset' 
  exit 1
fi
mkdir -p solr/configsets/property_search/conf
mkdir -p solr/configsets/term_search/conf
cp -a solr/configsets/_default/conf/* solr/configsets/property_search/conf/
cp -a solr/configsets/_default/conf/* solr/configsets/term_search/conf/
cp -a $ld_config/property_search/* solr/configsets/property_search/conf
cp -a $ld_config/term_search/* solr/configsets/term_search/conf

