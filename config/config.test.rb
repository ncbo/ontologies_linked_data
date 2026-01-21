###
# This file is designed for use in docker based unit testing
#
# All the defaults are set in
# https://github.com/ncbo/ontologies_linked_data/blob/master/lib/ontologies_linked_data/config/config.rb
###

GOO_BACKEND_NAME = ENV.include?("GOO_BACKEND_NAME") ? ENV["GOO_BACKEND_NAME"] : "4store"
GOO_PATH_QUERY   = ENV.include?("GOO_PATH_QUERY")   ? ENV["GOO_PATH_QUERY"]   : "/sparql/"
GOO_PATH_DATA    = ENV.include?("GOO_PATH_DATA")    ? ENV["GOO_PATH_DATA"]    : "/data/"
GOO_PATH_UPDATE  = ENV.include?("GOO_PATH_UPDATE")  ? ENV["GOO_PATH_UPDATE"]  : "/update/"
GOO_PORT         = ENV.include?("GOO_PORT")         ? ENV["GOO_PORT"]         : 9000
GOO_HOST         = ENV.include?("GOO_HOST")         ? ENV["GOO_HOST"]         : "localhost"
REDIS_HOST       = ENV.include?("REDIS_HOST")       ? ENV["REDIS_HOST"]       : "localhost"
REDIS_PORT       = ENV.include?("REDIS_PORT")       ? ENV["REDIS_PORT"]       : 6379
SOLR_TERM_SEARCH_URL = ENV.include?("SOLR_TERM_SEARCH_URL") ? ENV["SOLR_TERM_SEARCH_URL"] : "http://localhost:8983/solr"
SOLR_PROP_SEARCH_URL = ENV.include?("SOLR_PROP_SEARCH_URL") ? ENV["SOLR_PROP_SEARCH_URL"] : "http://localhost:8983/solr"

LinkedData.config do |config|
  config.goo_backend_name              = GOO_BACKEND_NAME.to_s
  config.goo_host                      = GOO_HOST.to_s
  config.goo_port                      = GOO_PORT.to_i
  config.goo_path_query                = GOO_PATH_QUERY.to_s
  config.goo_path_data                 = GOO_PATH_DATA.to_s
  config.goo_path_update               = GOO_PATH_UPDATE.to_s
  config.goo_redis_host                = REDIS_HOST.to_s
  config.goo_redis_port                = REDIS_PORT.to_i
  config.http_redis_host               = REDIS_HOST.to_s
  config.http_redis_port               = REDIS_PORT.to_i
  config.ontology_analytics_redis_host = REDIS_HOST.to_s
  config.ontology_analytics_redis_port = REDIS_PORT.to_i
  config.search_server_url             = SOLR_TERM_SEARCH_URL.to_s
  config.property_search_server_url    = SOLR_PROP_SEARCH_URL.to_s
#  config.enable_notifications          = false
end
