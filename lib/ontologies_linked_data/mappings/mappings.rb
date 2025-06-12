require 'benchmark'
require 'tmpdir'

module LinkedData
module Mappings
  OUTSTANDING_LIMIT = 30

    def self.mapping_predicates
      predicates = {}
      predicates["CUI"] = ["http://bioportal.bioontology.org/ontologies/umls/cui"]
      predicates["SAME_URI"] =
        ["http://data.bioontology.org/metadata/def/mappingSameURI"]
      predicates["LOOM"] =
        ["http://data.bioontology.org/metadata/def/mappingLoom"]
      predicates["REST"] =
        ["http://data.bioontology.org/metadata/def/mappingRest"]
      return predicates
    end

    def self.internal_mapping_predicates
      predicates = {}
      predicates["SKOS:EXACT_MATCH"] = ["http://www.w3.org/2004/02/skos/core#exactMatch"]
      predicates["SKOS:CLOSE_MATCH"] = ["http://www.w3.org/2004/02/skos/core#closeMatch"]
      predicates["SKOS:BROAD_MATH"] = ["http://www.w3.org/2004/02/skos/core#broadMatch"]
      predicates["SKOS:NARROW_MATH"] = ["http://www.w3.org/2004/02/skos/core#narrowMatch"]
      predicates["SKOS:RELATED_MATH"] = ["http://www.w3.org/2004/02/skos/core#relatedMatch"]

      return predicates
    end

    def self.handle_triple_store_downtime(logger = nil)
      epr = Goo.sparql_query_client(:main)
      status = epr.status

    if status[:exception]
      logger.info(status[:exception]) if logger
      exit(1)
    end

    if status[:outstanding] > OUTSTANDING_LIMIT
      logger.info("The triple store number of outstanding queries exceeded #{OUTSTANDING_LIMIT}. Exiting...") if logger
      exit(1)
    end
  end

  def self.mapping_counts(enable_debug=false, logger=nil, reload_cache=false, arr_acronyms=[])
    logger = nil unless enable_debug
    t = Time.now
    latest = self.retrieve_latest_submissions(options={ acronyms:arr_acronyms })
    counts = {}
    i = 0
    epr = Goo.sparql_query_client(:main)

    latest.each do |acro, sub|
      self.handle_triple_store_downtime(logger) if LinkedData.settings.goo_backend_name === '4store'
      t0 = Time.now
      s_counts = self.mapping_ontologies_count(sub, nil, reload_cache=reload_cache)
      s_total = 0

      s_counts.each do |k,v|
        s_total += v
      end
      counts[acro] = s_total
      i += 1

      if enable_debug
        logger.info("#{i}/#{latest.count} " +
            "Retrieved #{s_total} records for #{acro} in #{Time.now - t0} seconds.")
        logger.flush
      end
      sleep(5)
    end

    if enable_debug
      logger.info("Total time #{Time.now - t} sec.")
      logger.flush
    end
    return counts
  end

  def self.mapping_ontologies_count(sub1, sub2, reload_cache=false)
    template = <<-eos
{
  GRAPH <#{sub1.id.to_s}> {
      ?s1 <predicate> ?o .
  }
  GRAPH graph {
      ?s2 <predicate> ?o .
  }
}
eos
    group_count = sub2.nil? ? {} : nil
    count = 0
    latest_sub_ids = self.retrieve_latest_submission_ids
    epr = Goo.sparql_query_client(:main)

    mapping_predicates().each do |_source, mapping_predicate|
      block = template.gsub("predicate", mapping_predicate[0])
      query_template = <<-eos
      SELECT variables
      WHERE {
      block
      filter
      } group
      eos
      query = query_template.sub("block", block)
      filter = _source == "SAME_URI" ? '' : 'FILTER (?s1 != ?s2)'

      if sub2.nil?
        ont_id = sub1.id.to_s.split("/")[0..-3].join("/")
        #STRSTARTS is used to not count older graphs
        filter += "\nFILTER (!STRSTARTS(str(?g),'#{ont_id}'))"
        query = query.sub("graph","?g")
        query = query.sub("filter",filter)
        query = query.sub("variables","?g (count(?s1) as ?c)")
        query = query.sub("group","GROUP BY ?g")
      else
        query = query.sub("graph","<#{sub2.id.to_s}>")
        query = query.sub("filter",filter)
        query = query.sub("variables","(count(?s1) as ?c)")
        query = query.sub("group","")
      end
      graphs = [sub1.id, LinkedData::Models::MappingProcess.type_uri]
      graphs << sub2.id unless sub2.nil?

      if sub2.nil?
        solutions = epr.query(query, graphs: graphs, reload_cache: reload_cache)

        solutions.each do |sol|
          acr = sol[:g].to_s.split("/")[-3]
          next unless latest_sub_ids[acr] == sol[:g].to_s

          if group_count[acr].nil?
            group_count[acr] = 0
          end
          group_count[acr] += sol[:c].object
        end
      else
        solutions = epr.query(query,
                              graphs: graphs )
        solutions.each do |sol|
          count += sol[:c].object
        end
      end
    end #per predicate query

    if sub2.nil?
      return group_count
    end
    return count
  end

  def self.empty_page(page,size)
      p = Goo::Base::Page.new(page,size,nil,[])
      p.aggregate = 0
      return p
  end

    def self.mappings_ontologies(sub1, sub2, page, size, classId = nil, reload_cache = false)
      sub1, acr1 = extract_acronym(sub1)
      sub2, acr2 = extract_acronym(sub2)

      mappings = []
      persistent_count = 0

      if classId.nil?
        persistent_count = count_mappings(acr1, acr2)
        return LinkedData::Mappings.empty_page(page, size) if persistent_count == 0
      end

      query = mappings_ont_build_query(classId, page, size, sub1, sub2)
      epr = Goo.sparql_query_client(:main)
      graphs = [sub1]
      unless sub2.nil?
        graphs << sub2
      end
      solutions = epr.query(query, graphs: graphs, reload_cache: reload_cache)
      s1 = nil
      s1 = RDF::URI.new(classId.to_s) unless classId.nil?

      solutions.each do |sol|
        graph2 = sub2.nil? ? sol[:g] : sub2
        s1 = sol[:s1] if classId.nil?
        backup_mapping = nil

        if sol[:source].to_s == "REST"
          backup_mapping = LinkedData::Models::RestBackupMapping
                             .find(sol[:o]).include(:process, :class_urns).first
          backup_mapping.process.bring_remaining
        end

        classes = get_mapping_classes_instance(s1, sub1, sol[:s2], graph2)

        mapping = if backup_mapping.nil?
                    LinkedData::Models::Mapping.new(classes, sol[:source].to_s)
                  else
                    LinkedData::Models::Mapping.new(
                      classes, sol[:source].to_s,
                      backup_mapping.process, backup_mapping.id)
                  end

        mappings << mapping
      end

      if size == 0
        return mappings
      end

      page = Goo::Base::Page.new(page, size, persistent_count, mappings)
      return page
    end

  def self.mappings_ontology(sub,page,size,classId=nil,reload_cache=false)
    return self.mappings_ontologies(sub,nil,page,size,classId=classId,
                                    reload_cache=reload_cache)
  end

  def self.read_only_class(classId,submissionId)
      ontologyId = submissionId
      acronym = nil
      unless submissionId["submissions"].nil?
        ontologyId = submissionId.split("/")[0..-3]
        acronym = ontologyId.last
        ontologyId = ontologyId.join("/")
      else
        acronym = ontologyId.split("/")[-1]
      end
      ontology = LinkedData::Models::Ontology
            .read_only(
              id: RDF::IRI.new(ontologyId),
              acronym: acronym)
      submission = LinkedData::Models::OntologySubmission
            .read_only(
              id: RDF::IRI.new(ontologyId+"/submissions/latest"),
              # id: RDF::IRI.new(submissionId),
              ontology: ontology)
      mappedClass = LinkedData::Models::Class
            .read_only(
              id: RDF::IRI.new(classId),
              submission: submission,
              urn_id: LinkedData::Models::Class.urn_id(acronym,classId) )
      return mappedClass
  end

  def self.migrate_rest_mappings(acronym)
    mappings = LinkedData::Models::RestBackupMapping
                .where.include(:uuid, :class_urns, :process).all
    if mappings.length == 0
      return []
    end
    triples = []

    rest_predicate = mapping_predicates()["REST"][0]
    mappings.each do |m|
      m.class_urns.each do |u|
        u = u.to_s
        if u.start_with?("urn:#{acronym}")
          class_id = u.split(":")[2..-1].join(":")
          triples <<
            " <#{class_id}> <#{rest_predicate}> <#{m.id}> . "
        end
      end
    end
    return triples
  end

  def self.delete_rest_mapping(mapping_id)
    mapping = get_rest_mapping(mapping_id)
    if mapping.nil?
      return nil
    end
    rest_predicate = mapping_predicates()["REST"][0]
    classes = mapping.classes
    classes.each do |c|
      sub = c.submission
      unless sub.id.to_s["latest"].nil?
        #the submission in the class might point to latest
        sub = LinkedData::Models::Ontology.find(c.submission.ontology.id)
                .first
                .latest_submission
      end
      graph_delete = RDF::Graph.new
      graph_delete << [c.id, RDF::URI.new(rest_predicate), mapping.id]
      Goo.sparql_update_client.delete_data(graph_delete, graph: sub.id)
    end
    mapping.process.delete
    backup = LinkedData::Models::RestBackupMapping.find(mapping_id).first
    unless backup.nil?
      backup.delete
    end
    return mapping
  end

  def self.get_rest_mapping(mapping_id)
    backup = LinkedData::Models::RestBackupMapping.find(mapping_id).first
    if backup.nil?
      return nil
    end
    rest_predicate = mapping_predicates()["REST"][0]
    qmappings = <<-eos
SELECT DISTINCT ?s1 ?c1 ?s2 ?c2 ?uuid ?o
WHERE {
  ?uuid <http://data.bioontology.org/metadata/process> ?o .

  GRAPH ?s1 {
    ?c1 <#{rest_predicate}> ?uuid .
  }
  GRAPH ?s2 {
    ?c2 <#{rest_predicate}> ?uuid .
  }
FILTER(?uuid = <#{LinkedData::Models::Base.replace_url_prefix_to_id(mapping_id)}>)
FILTER(?s1 != ?s2)
} LIMIT 1
eos
    epr = Goo.sparql_query_client(:main)
    graphs = [LinkedData::Models::MappingProcess.type_uri]
    mapping = nil
    epr.query(qmappings,
              graphs: graphs).each do |sol|
      classes = [ read_only_class(sol[:c1].to_s,sol[:s1].to_s),
                read_only_class(sol[:c2].to_s,sol[:s2].to_s) ]
      process = LinkedData::Models::MappingProcess.find(sol[:o]).first
      mapping = LinkedData::Models::Mapping.new(classes,"REST",
                                                process,
                                                sol[:uuid])
    end
    return mapping
  end

  def self.create_rest_mapping(classes,process)
    unless process.instance_of? LinkedData::Models::MappingProcess
      raise ArgumentError, "Process should be instance of MappingProcess"
    end
    if classes.length != 2
      raise ArgumentError, "Create REST is avalaible for two classes. " +
                           "Request contains #{classes.length} classes."
    end
    #first create back up mapping that lives across submissions
    backup_mapping = LinkedData::Models::RestBackupMapping.new
    backup_mapping.uuid = UUID.new.generate
    backup_mapping.process = process
    class_urns = []
    classes.each do |c|
      if c.instance_of?LinkedData::Models::Class
        acronym = c.submission.id.to_s.split("/")[-3]
        class_urns << RDF::URI.new(
          LinkedData::Models::Class.urn_id(acronym,c.id.to_s))

      else
        class_urns << RDF::URI.new(c.urn_id())
      end
    end
    backup_mapping.class_urns = class_urns
    backup_mapping.save

    #second add the mapping id to current submission graphs
    rest_predicate = mapping_predicates()["REST"][0]
    classes.each do |c|
      sub = c.submission
      unless sub.id.to_s["latest"].nil?
        #the submission in the class might point to latest
        sub = LinkedData::Models::Ontology.find(c.submission.ontology.id).first.latest_submission
      end
      graph_insert = RDF::Graph.new
      graph_insert << [c.id, RDF::URI.new(rest_predicate), backup_mapping.id]
      Goo.sparql_update_client.insert_data(graph_insert, graph: sub.id)
    end
    mapping = LinkedData::Models::Mapping.new(classes,"REST", process, backup_mapping.id)
    return mapping
  end

  def self.mappings_for_classids(class_ids,sources=["REST","CUI"])
    class_ids = class_ids.uniq
    predicates = {}
    sources.each do |t|
      predicates[mapping_predicates()[t][0]] = t
    end
    qmappings = <<-eos
SELECT DISTINCT ?s1 ?c1 ?s2 ?c2 ?pred
WHERE {
  GRAPH ?s1 {
    ?c1 ?pred ?o .
  }
  GRAPH ?s2 {
    ?c2 ?pred ?o .
  }
FILTER(?s1 != ?s2)
FILTER(filter_pred)
FILTER(filter_classes)
}
eos
    qmappings = qmappings.gsub("filter_pred",
                    predicates.keys.map { |x| "?pred = <#{x}>"}.join(" || "))
    qmappings = qmappings.gsub("filter_classes",
                      class_ids.map { |x| "?c1 = <#{x}>" }.join(" || "))
    epr = Goo.sparql_query_client(:main)
    graphs = [LinkedData::Models::MappingProcess.type_uri]
    mappings = []
    epr.query(qmappings,
              graphs: graphs).each do |sol|
      classes = [ read_only_class(sol[:c1].to_s,sol[:s1].to_s),
                read_only_class(sol[:c2].to_s,sol[:s2].to_s) ]
      source = predicates[sol[:pred].to_s]
      mappings << LinkedData::Models::Mapping.new(classes,source)
    end
    return mappings
  end

  def self.recent_rest_mappings(n)
    graphs = [LinkedData::Models::MappingProcess.type_uri]
    qdate = <<-eos
SELECT DISTINCT ?s
FROM <#{LinkedData::Models::MappingProcess.type_uri}>
WHERE { ?s <http://data.bioontology.org/metadata/date> ?o }
ORDER BY DESC(?o) LIMIT #{n}
eos
    epr = Goo.sparql_query_client(:main)
    procs = []
    epr.query(qdate, graphs: graphs,query_options: {rules: :NONE}).each do |sol|
      procs << sol[:s]
    end
    if procs.length == 0
      return []
    end
    graphs = [LinkedData::Models::MappingProcess.type_uri]
    proc_object = Hash.new
    LinkedData::Models::MappingProcess.where
        .include(LinkedData::Models::MappingProcess.attributes)
        .all.each do |obj|
          #highly cached query
          proc_object[obj.id.to_s] = obj
    end
    procs = procs.map { |x| "?o = #{x.to_ntriples}" }.join " || "
    rest_predicate = mapping_predicates()["REST"][0]
    qmappings = <<-eos
SELECT DISTINCT ?ont1 ?c1 ?ont2 ?c2 ?o ?uuid
WHERE {
  ?uuid <http://data.bioontology.org/metadata/process> ?o .

  ?s1 <http://data.bioontology.org/metadata/ontology> ?ont1 .
  GRAPH ?s1 {
    ?c1 <#{rest_predicate}> ?uuid .
  }
  ?s2 <http://data.bioontology.org/metadata/ontology> ?ont2 .
  GRAPH ?s2 {
    ?c2 <#{rest_predicate}> ?uuid .
  }
FILTER(?ont1 != ?ont2)
FILTER(?c1 != ?c2)
FILTER (#{procs})
}
eos
    epr = Goo.sparql_query_client(:main)
    mappings = []
    epr.query(qmappings,
              graphs: graphs,query_options: {rules: :NONE}).each do |sol|
      classes = [ read_only_class(sol[:c1].to_s,sol[:ont1].to_s),
                read_only_class(sol[:c2].to_s,sol[:ont2].to_s) ]
      process = proc_object[sol[:o].to_s]
      mapping = LinkedData::Models::Mapping.new(classes,"REST",
                                                process,
                                                sol[:uuid])
      mappings << mapping
    end
    return mappings.sort_by { |x| x.process.date }.reverse[0..n-1]
  end

  def self.retrieve_latest_submission_ids(options = {})
    include_views = options[:include_views] || false
    ids_query = <<-eos
PREFIX xsd: <http://www.w3.org/2001/XMLSchema#>
SELECT (CONCAT(xsd:string(?ontology), "/submissions/", xsd:string(MAX(?submissionId))) as ?id)
WHERE { 
	?id <http://data.bioontology.org/metadata/ontology> ?ontology .
	?id <http://data.bioontology.org/metadata/submissionId> ?submissionId .
	?id <http://data.bioontology.org/metadata/submissionStatus> ?submissionStatus .
	?submissionStatus <http://data.bioontology.org/metadata/code> "RDF" . 
	include_views_filter 
}
GROUP BY ?ontology
    eos
    include_views_filter = include_views ? '' : <<-eos
	OPTIONAL { 
		?id <http://data.bioontology.org/metadata/ontology> ?ontJoin .  
	} 
	OPTIONAL { 
		?ontJoin <http://data.bioontology.org/metadata/viewOf> ?viewOf .  
	} 
	FILTER(!BOUND(?viewOf))
    eos
    ids_query.gsub!("include_views_filter", include_views_filter)
    epr = Goo.sparql_query_client(:main)
    solutions = epr.query(ids_query)
    latest_ids = {}

    solutions.each do |sol|
      acr = sol[:id].to_s.split("/")[-3]
      latest_ids[acr] = sol[:id].object
    end

    latest_ids
  end

  def self.retrieve_latest_submissions(options = {})
    acronyms = (options[:acronyms] || [])
    status = (options[:status] || "RDF").to_s.upcase
    include_ready = status.eql?("READY") ? true : false
    status = "RDF" if status.eql?("READY")
    any = status.eql?("ANY")
    include_views = options[:include_views] || false

    if any
      submissions_query = LinkedData::Models::OntologySubmission.where
    else
      submissions_query = LinkedData::Models::OntologySubmission.where(submissionStatus: [code: status])
    end
    submissions_query = submissions_query.filter(Goo::Filter.new(ontology: [:viewOf]).unbound) unless include_views
    submissions = submissions_query.include(:submissionStatus,:submissionId, ontology: [:acronym]).to_a
    submissions.select! { |sub| acronyms.include?(sub.ontology.acronym) } unless acronyms.empty?
    latest_submissions = {}

    submissions.each do |sub|
      next if include_ready && !sub.ready?
      latest_submissions[sub.ontology.acronym] ||= sub
      latest_submissions[sub.ontology.acronym] = sub if sub.submissionId > latest_submissions[sub.ontology.acronym].submissionId
    end
    return latest_submissions
  end

  def self.create_mapping_counts(logger, arr_acronyms=[])
    ont_msg = arr_acronyms.empty? ? "all ontologies" : "ontologies [#{arr_acronyms.join(', ')}]"

    time = Benchmark.realtime do
      self.create_mapping_count_totals_for_ontologies(logger, arr_acronyms)
    end
    logger.info("Completed rebuilding total mapping counts for #{ont_msg} in #{(time/60).round(1)} minutes.")

    time = Benchmark.realtime do
      self.create_mapping_count_pairs_for_ontologies(logger, arr_acronyms)
    end
    logger.info("Completed rebuilding mapping count pairs for #{ont_msg} in #{(time/60).round(1)} minutes.")
  end

  def self.create_mapping_count_totals_for_ontologies(logger, arr_acronyms)
    new_counts = self.mapping_counts(enable_debug=true, logger=logger, reload_cache=true, arr_acronyms)
    persistent_counts = {}
    f = Goo::Filter.new(:pair_count) == false
    LinkedData::Models::MappingCount.where.filter(f)
      .include(:ontologies, :count)
    .include(:all)
    .all
    .each do |m|
      persistent_counts[m.ontologies.first] = m
    end

    num_counts = new_counts.keys.length
    ctr = 0

    new_counts.each_key do |acr|
      new_count = new_counts[acr]
      ctr += 1

      if persistent_counts.include?(acr)
        inst = persistent_counts[acr]

        if new_count != inst.count
          inst.bring_remaining
          inst.count = new_count

          begin
            if inst.valid?
              inst.save
            else
              logger.error("Error updating mapping count for #{acr}: #{inst.id.to_s}. #{inst.errors}")
              next
            end
          rescue Exception => e
            logger.error("Exception updating mapping count for #{acr}: #{inst.id.to_s}. #{e.class}: #{e.message}\n#{e.backtrace.join("\n")}")
            next
          end
        end
      else
        m = LinkedData::Models::MappingCount.new
        m.ontologies = [acr]
        m.pair_count = false
        m.count = new_count

        begin
          if m.valid?
            m.save
          else
            logger.error("Error saving new mapping count for #{acr}. #{m.errors}")
            next
          end
        rescue Exception => e
          logger.error("Exception saving new mapping count for #{acr}. #{e.class}: #{e.message}\n#{e.backtrace.join("\n")}")
          next
        end
      end
      remaining = num_counts - ctr
      logger.info("Total mapping count saved for #{acr}: #{new_count}. " << ((remaining > 0) ? "#{remaining} counts remaining..." : "All done!"))
    end
  end

  # This generates pair mapping counts for the given
  # ontologies to ALL other ontologies in the system
  def self.create_mapping_count_pairs_for_ontologies(logger, arr_acronyms)
    latest_submissions = self.retrieve_latest_submissions(options={acronyms:arr_acronyms})
    ont_total = latest_submissions.length
    logger.info("There is a total of #{ont_total} ontologies to process...")
    ont_ctr = 0
    # filename = 'mapping_pairs.ttl'
    # temp_dir = Dir.tmpdir
    # temp_file_path = File.join(temp_dir, filename)
    # temp_dir = '/Users/mdorf/Downloads/test/'
    # temp_file_path = File.join(File.dirname(file_path), "test.ttl")
    # fsave = File.open(temp_file_path, "a")

    latest_submissions.each do |acr, sub|
      self.handle_triple_store_downtime(logger) if LinkedData.settings.goo_backend_name === '4store'
      new_counts = nil
      time = Benchmark.realtime do
        new_counts = self.mapping_ontologies_count(sub, nil, reload_cache=true)
      end
      logger.info("Retrieved new mapping pair counts for #{acr} in #{time} seconds.")
      ont_ctr += 1
      persistent_counts = {}
      LinkedData::Models::MappingCount.where(pair_count: true).and(ontologies: acr)
                                      .include(:ontologies, :count).all.each do |m|
        other = m.ontologies.first

        if other == acr
          other = m.ontologies[1]
        end
        persistent_counts[other] = m
      end

      num_counts = new_counts.keys.length
      logger.info("Ontology: #{acr}. #{num_counts} mapping pair counts to record...")
      logger.info("------------------------------------------------")
      ctr = 0

      new_counts.each_key do |other|
        new_count = new_counts[other]
        ctr += 1

        if persistent_counts.include?(other)
          inst = persistent_counts[other]

          if new_count != inst.count
            inst.bring_remaining
            inst.pair_count = true
            inst.count = new_count

            begin
              if inst.valid?
                inst.save()
                # inst.save({ batch: fsave })
              else
                logger.error("Error updating mapping count for the pair [#{acr}, #{other}]: #{inst.id.to_s}. #{inst.errors}")
                next
              end
            rescue Exception => e
              logger.error("Exception updating mapping count for the pair [#{acr}, #{other}]: #{inst.id.to_s}. #{e.class}: #{e.message}\n#{e.backtrace.join("\n")}")
              next
            end
          end
        else
          m = LinkedData::Models::MappingCount.new
          m.count = new_count
          m.ontologies = [acr,other]
          m.pair_count = true

          begin
            if m.valid?
              m.save()
              # m.save({ batch: fsave })
            else
              logger.error("Error saving new mapping count for the pair [#{acr}, #{other}]. #{m.errors}")
              next
            end
          rescue Exception => e
            logger.error("Exception saving new mapping count for the pair [#{acr}, #{other}]. #{e.class}: #{e.message}\n#{e.backtrace.join("\n")}")
            next
          end
        end
        remaining = num_counts - ctr
        logger.info("Mapping count saved for the pair [#{acr}, #{other}]: #{new_count}. " << ((remaining > 0) ? "#{remaining} counts remaining for #{acr}..." : "All done!"))
        wait_interval = 250

        if ctr % wait_interval == 0
          sec_to_wait = 1
          logger.info("Waiting #{sec_to_wait} second" << ((sec_to_wait > 1) ? 's' : '') << '...')
          sleep(sec_to_wait)
        end
      end
      remaining_ont = ont_total - ont_ctr
      logger.info("Completed processing pair mapping counts for #{acr}. " << ((remaining_ont > 0) ? "#{remaining_ont} ontologies remaining..." : "All ontologies processed!"))
      sleep(5)
    end
    # fsave.close
  end

    private

    def self.get_mapping_classes_instance(s1, graph1, s2, graph2)
      [read_only_class(s1.to_s, graph1.to_s),
       read_only_class(s2.to_s, graph2.to_s)]
    end

    def self.mappings_ont_build_query(class_id, page, size, sub1, sub2)
      blocks = []
      mapping_predicates.each do |_source, mapping_predicate|
        blocks << mappings_union_template(class_id, sub1, sub2,
                                          mapping_predicate[0],
                                          "BIND ('#{_source}' AS ?source)")
      end






      filter = class_id.nil? ? "FILTER ((?s1 != ?s2) || (?source = 'SAME_URI'))" : ''
      if sub2.nil?
        
        class_id_subject = class_id.nil? ? '?s1' :  "<#{class_id.to_s}>"
        source_graph = sub1.nil? ? '?g' :  "<#{sub1.to_s}>"
        internal_mapping_predicates.each do |_source, predicate|
          blocks << <<-eos
        {
          GRAPH #{source_graph} {
            #{class_id_subject} <#{predicate[0]}> ?s2 .
          }
          BIND(<http://data.bioontology.org/metadata/ExternalMappings> AS ?g)
          BIND(?s2 AS ?o)
          BIND ('#{_source}' AS ?source)
        }
          eos
        end

        ont_id = sub1.to_s.split("/")[0..-3].join("/")
        #STRSTARTS is used to not count older graphs
        #no need since now we delete older graphs

        filter += "\nFILTER (!STRSTARTS(str(?g),'#{ont_id}')"
        filter += " || " + internal_mapping_predicates.keys.map{|x| "(?source = '#{x}')"}.join('||')
        filter += ")"
      end

      variables = "?s2 #{sub2.nil? ? '?g' : ''} ?source ?o"
      variables = "?s1 " + variables if class_id.nil?

      pagination = ''
      if size > 0
        limit = size
        offset = (page - 1) * size
        pagination = "OFFSET #{offset} LIMIT #{limit}"
      end

      query = <<-eos
SELECT DISTINCT #{variables}
WHERE {
   #{blocks.join("\nUNION\n")}
   #{filter}
} #{pagination}
      eos

      query
    end

    def self.mappings_union_template(class_id, sub1, sub2, predicate, bind)
      class_id_subject = class_id.nil? ? '?s1' : "<#{class_id.to_s}>"
      target_graph = sub2.nil? ? '?g' : "<#{sub2.to_s}>"
      union_template = <<-eos
{
  GRAPH <#{sub1.to_s}> {
      #{class_id_subject} <#{predicate}> ?o .
  }
  GRAPH #{target_graph} {
      ?s2 <#{predicate}> ?o .
  }
  #{bind}
}
      eos
    end

    def self.count_mappings(acr1, acr2)
      count = LinkedData::Models::MappingCount.where(ontologies: acr1)
      count = count.and(ontologies: acr2) unless acr2.nil?
      f = Goo::Filter.new(:pair_count) == (not acr2.nil?)
      count = count.filter(f)
      count = count.include(:count)
      pcount_arr = count.all
      pcount_arr.length == 0 ? 0 : pcount_arr.first.count
    end

    def self.extract_acronym(submission)
      sub = submission
      if submission.nil?
        acr = nil
      elsif submission.respond_to?(:id)
        # Case where sub2 is a Submission
        sub = submission.id
        acr = sub.to_s.split("/")[-3]
      else
        acr = sub.to_s
      end

      return sub, acr
    end

  end
end

