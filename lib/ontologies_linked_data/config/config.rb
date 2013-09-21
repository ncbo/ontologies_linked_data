require 'goo'
require 'ostruct'

module LinkedData
  extend self
  attr_reader :settings

  @settings = OpenStruct.new
  @settings_run = false

  def config(&block)
    return if @settings_run
    @settings_run = true

    overide_connect_goo = false

    yield @settings, overide_connect_goo if block_given?

    # Set defaults
    @settings.goo_port               ||= 9000
    @settings.goo_host               ||= "localhost"
    @settings.search_server_url      ||= "http://localhost:8983/solr"
    @settings.repository_folder      ||= "./test/data/ontology_files/repo"
    @settings.rest_url_prefix        ||= "http://data.bioontology.org/"
    @settings.enable_security        ||= false

    ### these params should be not ussed any more 
    # removed so that dependencies shout
    #
    # @settings.redis_host             ||= "localhost"
    # @settings.redis_port             ||= 6379
    # ###

    @settings.ui_host                ||= "bioportal.bioontology.org"
    @settings.replace_url_prefix     ||= false
    @settings.id_url_prefix          ||= "http://data.bioontology.org/"
    @settings.queries_debug          ||= false

    # Caching http
    @settings.enable_http_cache      ||= false
    @settings.http_cache_redis_host  ||= "localhost"
    @settings.http_cache_redis_port  ||= 6379

    #Caching goo
    @settings.goo_cache_redis_host  ||= "localhost"
    @settings.goo_cache_redis_port  ||= 6379

    #Caching mappings
    @settings.mappings_cache_redis_host  ||= "localhost"
    @settings.mappings_cache_redis_port  ||= 6379

    # PURL server config parameters
    @settings.enable_purl            ||= false
    @settings.purl_host              ||= "purl.bioontology.org"
    @settings.purl_port              ||= 80
    @settings.purl_username          ||= ""
    @settings.purl_password          ||= ""
    @settings.purl_maintainers       ||= ""
    @settings.purl_target_url_prefix ||= "http://bioportal.bioontology.org"

    # Email settings
    @settings.email_sender           ||= "admin@example.org" # Default sender for emails
    @settings.email_override         ||= "test.email@example.org" # By default, all email gets sent here. Disable with email_override_disable.
    @settings.email_disable_override ||= false
    @settings.smtp_host              ||= "localhost"
    @settings.smtp_port              ||= 25
    @settings.smtp_user              ||= "user"
    @settings.smtp_password          ||= "password"
    @settings.smtp_auth_type         ||= :plain # :plain, :login, :cram_md5
    @settings.smtp_domain            ||= "localhost.localhost"

    # Check to make sure url prefix has trailing slash
    @settings.rest_url_prefix = @settings.rest_url_prefix + "/" unless @settings.rest_url_prefix[-1].eql?("/")

    puts ">> Using rdf store #{@settings.goo_host}:#{@settings.goo_port}"
    puts ">> Using search server at #{@settings.search_server_url}"
    puts ">> Using HTTP  Redis instance at #{@settings.http_redis_host}:#{@settings.http_redis_port}"
    puts ">> Using Mappings Redis instance at #{@settings.mappings_redis_host}:#{@settings.mappings_redis_port}"
    puts ">> Using Goo Redis instance at #{@settings.goo_redis_host}:#{@settings.goo_redis_port}"


    connect_goo unless overide_connect_goo
  end

  ##
  # Connect to goo by configuring the store and search server
  def connect_goo
    port              ||= @settings.goo_port
    host              ||= @settings.goo_host

    begin
      Goo.configure do |conf|
        conf.queries_debug(@settings.queries_debug)
        conf.add_sparql_backend(:main, query: "http://#{host}:#{port}/sparql/",
                                data: "http://#{host}:#{port}/data/",
                                update: "http://#{host}:#{port}/update/",
                                options: { rules: :NONE })

        conf.add_search_backend(:main, service: @settings.search_server_url)
        conf.add_redis_backend(host: @settings.goo_cache_redis_host, 
                               port: @settings.goo_cache_redis_port)
      end
    rescue Exception => e
      abort("EXITING: Cannot connect to triplestore and/or search server:\n  #{e}\n#{e.backtrace.join("\n")}")
    end
  end

  ##
  # Configure ontologies_linked_data namespaces
  # We do this at initial runtime because goo needs namespaces for its DSL
  def goo_namespaces
    Goo.configure do |conf|
      conf.add_namespace(:omv, RDF::Vocabulary.new("http://omv.ontoware.org/2005/05/ontology#"))
      conf.add_namespace(:skos, RDF::Vocabulary.new("http://www.w3.org/2004/02/skos/core#"))
      conf.add_namespace(:owl, RDF::Vocabulary.new("http://www.w3.org/2002/07/owl#"))
      conf.add_namespace(:rdfs, RDF::Vocabulary.new("http://www.w3.org/2000/01/rdf-schema#"))
      conf.add_namespace(:metadata, RDF::Vocabulary.new("http://data.bioontology.org/metadata/"), default = true)
      conf.add_namespace(:metadata_def, RDF::Vocabulary.new("http://data.bioontology.org/metadata/def/"))
      conf.add_namespace(:dc, RDF::Vocabulary.new("http://purl.org/dc/elements/1.1/"))
      conf.add_namespace(:xsd, RDF::Vocabulary.new("http://www.w3.org/2001/XMLSchema#"))
      conf.add_namespace(:oboinowl_gen, RDF::Vocabulary.new("http://www.geneontology.org/formats/oboInOWL#"))
      conf.add_namespace(:obo_purl, RDF::Vocabulary.new("http://purl.obolibrary.org/obo/"))
      conf.add_namespace(:umls, RDF::Vocabulary.new("http://bioportal.bioontology.org/ontologies/umls/"))
      conf.id_prefix = "http://data.bioontology.org/"
      conf.pluralize_models(true)
    end
  end
  self.goo_namespaces

end
