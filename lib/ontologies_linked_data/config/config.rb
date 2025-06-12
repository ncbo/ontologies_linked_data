require 'goo'
require 'ostruct'

module LinkedData
  extend self
  attr_reader :settings

  @settings = OpenStruct.new
  @settings_run = false

  DEFAULT_PREFIX = 'http://data.bioontology.org/'.freeze

  def config(&block)
    return if @settings_run
    @settings_run = true

    overide_connect_goo = false

    # Set defaults
    @settings.goo_backend_name              ||= '4store'
    @settings.goo_port                      ||= 9000
    @settings.goo_host                      ||= 'localhost'
    @settings.goo_path_query                ||= '/sparql/'
    @settings.goo_path_data                 ||= '/data/'
    @settings.goo_path_update               ||= '/update/'
    @settings.search_server_url             ||= 'http://localhost:8983/solr/term_search_core1'
    @settings.property_search_server_url    ||= 'http://localhost:8983/solr/prop_search_core1'
    @settings.repository_folder             ||= './test/data/ontology_files/repo'
    @settings.rest_url_prefix               ||= DEFAULT_PREFIX
    @settings.enable_security               ||= false
    @settings.enable_slices                 ||= false

    # Java/JVM options
    @settings.java_max_heap_size            ||= '10240M'

    @settings.ui_name                       ||= 'Bioportal'
    @settings.ui_host                       ||= 'bioportal.bioontology.org'
    @settings.replace_url_prefix            ||= false
    @settings.id_url_prefix                 ||= DEFAULT_PREFIX

    @settings.queries_debug                 ||= false
    @settings.enable_monitoring             ||= false
    @settings.cube_host                     ||= 'localhost'
    @settings.cube_port                     ||= 1180

    # Caching http
    @settings.enable_http_cache             ||= false
    @settings.http_redis_host               ||= 'localhost'
    @settings.http_redis_port               ||= 6379

    # Caching goo
    @settings.goo_redis_host                ||= 'localhost'
    @settings.goo_redis_port                ||= 6379

    # Ontology Analytics Redis
    @settings.ontology_analytics_redis_host ||= 'localhost'
    @settings.ontology_analytics_redis_port ||= 6379

    # PURL server config parameters
    @settings.enable_purl                   ||= false
    @settings.purl_host                     ||= 'purl.bioontology.org'
    @settings.purl_port                     ||= 80
    @settings.purl_username                 ||= ''
    @settings.purl_password                 ||= ''
    @settings.purl_maintainers              ||= ''
    @settings.purl_target_url_prefix        ||= 'http://bioportal.bioontology.org'

    # Email settings
    @settings.enable_notifications          ||= false
    # Default sender From email address
    @settings.email_sender                  ||= 'ontoportal@example.org'
    @settings.email_override                ||= 'test.email@example.org' # By default, all email gets sent here. Disable with email_override_disable.
    @settings.email_disable_override        ||= false
    @settings.smtp_host                     ||= 'localhost'
    @settings.smtp_port                     ||= 25
    @settings.smtp_user                     ||= 'user'
    @settings.smtp_password                 ||= 'password'
    @settings.smtp_auth_type                ||= :none # :none, :plain, :login, :cram_md5
    @settings.smtp_domain                   ||= 'localhost.localhost'
    @settings.enable_starttls_auto          ||= false # set to true for use with gmail
    # Support contact email address used in email notification send to ontoportal users.
    @settings.support_contact_email         ||= 'support@example.org'
    # List of contact emails for OntoPortal site administrators
    @settings.ontoportal_admin_emails       ||= ['admin@example.org']
    # Send administrative notifications for events including new user and
    # ontology creation to OntoPortal site admins
    @settings.enable_administrative_notifications ||= true

    # number of times to retry a query when empty records are returned
    @settings.num_retries_4store            ||= 10

    # number of threads to use when indexing a single ontology for search
    @settings.indexing_num_threads          ||= 1

    # Override defaults
    yield @settings, overide_connect_goo if block_given?

    # Check to make sure url prefix has trailing slash
    @settings.rest_url_prefix = "#{@settings.rest_url_prefix}/" unless @settings.rest_url_prefix[-1].eql?('/')

    puts "(LD) >> Using rdf store #{@settings.goo_host}:#{@settings.goo_port}#{@settings.goo_path_query}"
    puts "(LD) >> Using term search server at #{@settings.search_server_url}"
    puts "(LD) >> Using property search server at #{@settings.property_search_server_url}"
    puts "(LD) >> Using HTTP Redis instance at #{@settings.http_redis_host}:#{@settings.http_redis_port}"
    puts "(LD) >> Using Goo Redis instance at #{@settings.goo_redis_host}:#{@settings.goo_redis_port}"

    connect_goo unless overide_connect_goo
  end

  ##
  # Connect to goo by configuring the store and search server
  def connect_goo
    backend_name      ||= @settings.goo_backend_name
    port              ||= @settings.goo_port
    host              ||= @settings.goo_host
    path_query        ||= @settings.goo_path_query
    path_data         ||= @settings.goo_path_data
    path_update       ||= @settings.goo_path_update

    begin
      Goo.configure do |conf|
        conf.queries_debug(@settings.queries_debug)
        conf.add_sparql_backend(:main,
                                backend_name: backend_name,
                                query: "http://#{host}:#{port}#{path_query}",
                                data: "http://#{host}:#{port}#{path_data}",
                                update: "http://#{host}:#{port}#{path_update}",
                                options: { rules: :NONE })
        conf.add_search_backend(:main, service: @settings.search_server_url)
        conf.add_search_backend(:property, service: @settings.property_search_server_url)
        conf.add_redis_backend(host: @settings.goo_redis_host,
                               port: @settings.goo_redis_port)

        if @settings.enable_monitoring
          puts "(LD) >> Enable SPARQL monitoring with cube #{@settings.cube_host}:#{@settings.cube_port}"
          conf.enable_cube do |opts|
            opts[:host] = @settings.cube_host
            opts[:port] = @settings.cube_port
          end
        end
      end
    rescue StandardError => e
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
      conf.add_namespace(:rdf, RDF::Vocabulary.new("http://www.w3.org/1999/02/22-rdf-syntax-ns#"))
      conf.add_namespace(:rdfs, RDF::Vocabulary.new("http://www.w3.org/2000/01/rdf-schema#"))
      conf.add_namespace(:metadata, RDF::Vocabulary.new("http://data.bioontology.org/metadata/"), default = true)
      conf.add_namespace(:metadata_def, RDF::Vocabulary.new("http://data.bioontology.org/metadata/def/"))
      conf.add_namespace(:dc, RDF::Vocabulary.new("http://purl.org/dc/elements/1.1/"))
      conf.add_namespace(:xsd, RDF::Vocabulary.new("http://www.w3.org/2001/XMLSchema#"))
      conf.add_namespace(:oboinowl_gen, RDF::Vocabulary.new("http://www.geneontology.org/formats/oboInOwl#"))
      conf.add_namespace(:obo_purl, RDF::Vocabulary.new("http://purl.obolibrary.org/obo/"))
      conf.add_namespace(:umls, RDF::Vocabulary.new("http://bioportal.bioontology.org/ontologies/umls/"))
      conf.add_namespace(:door, RDF::Vocabulary.new("http://kannel.open.ac.uk/ontology#"))
      conf.add_namespace(:dct, RDF::Vocabulary.new("http://purl.org/dc/terms/"))

      conf.add_namespace(:void, RDF::Vocabulary.new("http://rdfs.org/ns/void#"))
      conf.add_namespace(:foaf, RDF::Vocabulary.new("http://xmlns.com/foaf/0.1/"))
      conf.add_namespace(:vann, RDF::Vocabulary.new("http://purl.org/vocab/vann/"))
      conf.add_namespace(:adms, RDF::Vocabulary.new("http://www.w3.org/ns/adms#"))
      conf.add_namespace(:voaf, RDF::Vocabulary.new("http://purl.org/vocommons/voaf#"))
      conf.add_namespace(:dcat, RDF::Vocabulary.new("http://www.w3.org/ns/dcat#"))
      conf.add_namespace(:mod, RDF::Vocabulary.new("http://www.isibang.ac.in/ns/mod#"))
      conf.add_namespace(:prov, RDF::Vocabulary.new("http://www.w3.org/ns/prov#"))
      conf.add_namespace(:cc, RDF::Vocabulary.new("http://creativecommons.org/ns#"))
      conf.add_namespace(:schema, RDF::Vocabulary.new("http://schema.org/"))
      conf.add_namespace(:doap, RDF::Vocabulary.new("http://usefulinc.com/ns/doap#"))
      conf.add_namespace(:bibo, RDF::Vocabulary.new("http://purl.org/ontology/bibo/"))
      conf.add_namespace(:wdrs, RDF::Vocabulary.new("http://www.w3.org/2007/05/powder-s#"))
      conf.add_namespace(:cito, RDF::Vocabulary.new("http://purl.org/spar/cito/"))
      conf.add_namespace(:pav, RDF::Vocabulary.new("http://purl.org/pav/"))
      conf.add_namespace(:oboInOwl, RDF::Vocabulary.new("http://www.geneontology.org/formats/oboInOwl#"))
      conf.add_namespace(:idot, RDF::Vocabulary.new("http://identifiers.org/idot/"))
      conf.add_namespace(:sd, RDF::Vocabulary.new("http://www.w3.org/ns/sparql-service-description#"))
      conf.add_namespace(:org, RDF::Vocabulary.new("http://www.w3.org/ns/org#"))
      conf.add_namespace(:cclicense, RDF::Vocabulary.new("http://creativecommons.org/licenses/"))
      conf.add_namespace(:nkos, RDF::Vocabulary.new("http://w3id.org/nkos#"))
      conf.add_namespace(:skosxl, RDF::Vocabulary.new("http://www.w3.org/2008/05/skos-xl#"))
      conf.add_namespace(:dcterms, RDF::Vocabulary.new("http://purl.org/dc/terms/"))
      conf.add_namespace(:uneskos, RDF::Vocabulary.new("http://purl.org/umu/uneskos#"))


      conf.id_prefix = DEFAULT_PREFIX
      conf.pluralize_models(true)
    end
  end
  goo_namespaces

end
