require 'benchmark'
require 'tmpdir'

module LinkedData
  module Mappings
    OUTSTANDING_LIMIT = 30

    extend LinkedData::Concerns::Mappings::Creator
    extend LinkedData::Concerns::Mappings::BulkLoad

    def self.mapping_predicates()
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

    def self.mapping_counts(enable_debug = false, logger = nil, reload_cache = false, arr_acronyms = [])
      logger = nil unless enable_debug
      t = Time.now
      latest = self.retrieve_latest_submissions(options = { acronyms: arr_acronyms })
      counts = {}
      # Counting for External mappings
      t0 = Time.now
      external_uri = LinkedData::Models::ExternalClass.graph_uri
      exter_counts = mapping_ontologies_count(external_uri, nil, reload_cache = reload_cache)
      exter_total = 0
      exter_counts.each do |k, v|
        exter_total += v
      end
      counts[external_uri.to_s] = exter_total
      if enable_debug
        logger.info("Time for External Mappings took #{Time.now - t0} sec. records #{exter_total}")
      end
      LinkedData.settings.interportal_hash ||= {}
      # Counting for Interportal mappings
      LinkedData.settings.interportal_hash.each_key do |acro|
        t0 = Time.now
        interportal_uri = LinkedData::Models::InterportalClass.graph_uri(acro)
        inter_counts = mapping_ontologies_count(interportal_uri, nil, reload_cache = reload_cache)
        inter_total = 0
        inter_counts.each do |k, v|
          inter_total += v
        end
        counts[interportal_uri.to_s] = inter_total
        if enable_debug
          logger.info("Time for #{interportal_uri.to_s} took #{Time.now - t0} sec. records #{inter_total}")
        end
      end
      # Counting for mappings between the ontologies hosted by the BioPortal appliance
      i = 0
      epr = Goo.sparql_query_client(:main)

      latest.each do |acro, sub|
        self.handle_triple_store_downtime(logger)
        t0 = Time.now
        s_counts = self.mapping_ontologies_count(sub, nil, reload_cache = reload_cache)
        s_total = 0

        s_counts.each do |k, v|
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

    def self.mapping_ontologies_count(sub1, sub2, reload_cache = false)
      sub1 = if sub1.instance_of?(LinkedData::Models::OntologySubmission)
               sub1.id
             else
               sub1
             end
      template = <<-eos
{
  GRAPH <#{sub1.to_s}> {
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
          if sub1.to_s != LinkedData::Models::ExternalClass.graph_uri.to_s
            ont_id = sub1.to_s.split("/")[0..-3].join("/")
            #STRSTARTS is used to not count older graphs
            filter += "\nFILTER (!STRSTARTS(str(?g),'#{ont_id}'))"
          end
          query = query.sub("graph", "?g")
          query = query.sub("filter", filter)
          query = query.sub("variables", "?g (count(?s1) as ?c)")
          query = query.sub("group", "GROUP BY ?g")
        else
          query = query.sub("graph", "<#{sub2.id.to_s}>")
          query = query.sub("filter", filter)
          query = query.sub("variables", "(count(?s1) as ?c)")
          query = query.sub("group", "")
        end

        graphs = [sub1, LinkedData::Models::MappingProcess.type_uri]
        graphs << sub2.id unless sub2.nil?

        if sub2.nil?
          solutions = epr.query(query, graphs: graphs, reload_cache: reload_cache)

          solutions.each do |sol|
            graph2 = sol[:g].to_s
            acr = ""
            if graph2.start_with?(LinkedData::Models::InterportalClass.graph_base_str) || graph2 == LinkedData::Models::ExternalClass.graph_uri.to_s
              acr = graph2
            else
              acr = graph2.to_s.split("/")[-3]
            end
            if group_count[acr].nil?
              group_count[acr] = 0
            end
            group_count[acr] += sol[:c].object
          end
        else
          solutions = epr.query(query,
                                graphs: graphs)
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

    def self.empty_page(page, size)
      p = Goo::Base::Page.new(page, size, nil, [])
      p.aggregate = 0
      return p
    end

    def self.mappings_ontologies(sub1, sub2, page, size, classId = nil, reload_cache = false)
      if sub1.respond_to?(:id)
        # Case where sub1 is a Submission
        sub1 = sub1.id
        acr1 = sub1.to_s.split("/")[-3]
      else
        acr1 = sub1.to_s
      end
      if sub2.nil?
        acr2 = nil
      elsif sub2.respond_to?(:id)
        # Case where sub2 is a Submission
        sub2 = sub2.id
        acr2 = sub2.to_s.split("/")[-3]
      else
        acr2 = sub2.to_s
      end

      union_template = <<-eos
{
  GRAPH <#{sub1.to_s}> {
      classId <predicate> ?o .
  }
  GRAPH graph {
      ?s2 <predicate> ?o .
  }
  bind
}
      eos
      blocks = []
      mappings = []
      persistent_count = 0

      if classId.nil?
        pcount = LinkedData::Models::MappingCount.where(ontologies: acr1)
        pcount = pcount.and(ontologies: acr2) unless acr2.nil?
        f = Goo::Filter.new(:pair_count) == (not acr2.nil?)
        pcount = pcount.filter(f)
        pcount = pcount.include(:count)
        pcount_arr = pcount.all
        persistent_count = pcount_arr.length == 0 ? 0 : pcount_arr.first.count

        return LinkedData::Mappings.empty_page(page, size) if persistent_count == 0
      end

      union_template = if classId.nil?
                         union_template.gsub("classId", "?s1")
                       else
                         union_template.gsub("classId", "<#{classId.to_s}>")
                       end
      # latest_sub_ids = self.retrieve_latest_submission_ids

      mapping_predicates().each do |_source, mapping_predicate|
        union_block = union_template.gsub("predicate", mapping_predicate[0])
        union_block = union_block.gsub("bind", "BIND ('#{_source}' AS ?source)")

        union_block = if sub2.nil?
                        union_block.gsub("graph", "?g")
                      else
                        union_block.gsub("graph", "<#{sub2.to_s}>")
                      end
        blocks << union_block
      end
      unions = blocks.join("\nUNION\n")

      mappings_in_ontology = <<-eos
SELECT DISTINCT variables
WHERE {
unions
filter
} page_group
      eos
      query = mappings_in_ontology.gsub("unions", unions)
      variables = "?s2 graph ?source ?o"
      variables = "?s1 " + variables if classId.nil?
      query = query.gsub("variables", variables)
      filter = classId.nil? ? "FILTER ((?s1 != ?s2) || (?source = 'SAME_URI'))" : ''

      if sub2.nil?
        query = query.gsub("graph", "?g")
        ont_id = sub1.to_s.split("/")[0..-3].join("/")
        #STRSTARTS is used to not count older graphs
        #no need since now we delete older graphs
        filter += "\nFILTER (!STRSTARTS(str(?g),'#{ont_id}'))"
      else
        query = query.gsub("graph", "")
      end
      query = query.gsub("filter", filter)

      if size > 0
        pagination = "OFFSET offset LIMIT limit"
        query = query.gsub("page_group", pagination)
        limit = size
        offset = (page - 1) * size
        query = query.gsub("limit", "#{limit}").gsub("offset", "#{offset}")
      else
        query = query.gsub("page_group", "")
      end
      epr = Goo.sparql_query_client(:main)
      graphs = [sub1]
      unless sub2.nil?
        graphs << sub2
      end
      solutions = epr.query(query, graphs: graphs, reload_cache: reload_cache)
      s1 = nil
      unless classId.nil?
        s1 = RDF::URI.new(classId.to_s)
      end
      solutions.each do |sol|
        graph2 = nil
        graph2 = if sub2.nil?
                   sol[:g]
                 else
                   sub2
                 end
        if classId.nil?
          s1 = sol[:s1]
        end

        backup_mapping = nil
        mapping = nil
        if sol[:source].to_s == "REST"
          backup_mapping = LinkedData::Models::RestBackupMapping
                             .find(sol[:o]).include(:process, :class_urns).first
          backup_mapping.process.bring_remaining
        end

        classes = get_mapping_classes_instance(s1.to_s, sub1.to_s, sol[:s2].to_s, graph2, backup_mapping)

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
      page = Goo::Base::Page.new(page, size, nil, mappings)
      page.aggregate = persistent_count
      return page
    end

    def self.mappings_ontology(sub, page, size, classId = nil, reload_cache = false)
      return self.mappings_ontologies(sub, nil, page, size, classId = classId,
                                      reload_cache = reload_cache)
    end

    def self.read_only_class(classId, submissionId)
      ontologyId = submissionId
      acronym = nil
      unless submissionId['submissions'].nil?
        ontologyId = submissionId.split('/')[0..-3]
        acronym = ontologyId.last
        ontologyId = ontologyId.join('/')
      else
        acronym = ontologyId.split('/')[-1]
      end
      ontology = LinkedData::Models::Ontology
                   .read_only(
                     id: RDF::IRI.new(ontologyId),
                     acronym: acronym)
      submission = LinkedData::Models::OntologySubmission
                     .read_only(
                       id: RDF::IRI.new(ontologyId + "/submissions/latest"),
                       # id: RDF::IRI.new(submissionId),
                       ontology: ontology)
      mappedClass = LinkedData::Models::Class
                      .read_only(
                        id: RDF::IRI.new(classId),
                        submission: submission,
                        urn_id: LinkedData::Models::Class.urn_id(acronym, classId))
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
        if c.respond_to?(:submission)
          sub = c.submission
          unless sub.id.to_s["latest"].nil?
            #the submission in the class might point to latest
            sub = LinkedData::Models::Ontology.find(c.submission.ontology.id)
                                              .first
                                              .latest_submission
          end
          del_from_graph = sub.id
        elsif c.respond_to?(:source)
          # If it is an InterportalClass
          del_from_graph = LinkedData::Models::InterportalClass.graph_uri(c.source)
        else
          # If it is an ExternalClass
          del_from_graph = LinkedData::Models::ExternalClass.graph_uri
        end
        graph_delete = RDF::Graph.new
        graph_delete << [c.id, RDF::URI.new(rest_predicate), mapping.id]
        Goo.sparql_update_client.delete_data(graph_delete, graph: del_from_graph)
      end
      mapping.process.delete
      backup = LinkedData::Models::RestBackupMapping.find(mapping_id).first
      unless backup.nil?
        backup.delete
      end
      return mapping
    end

    # A method that generate classes depending on the nature of the mapping : Internal, External or Interportal
    def self.get_mapping_classes_instance(c1, g1, c2, g2, backup)
      external_source = nil
      external_ontology = nil
      # Generate classes if g1 is interportal or external
      if g1.start_with?(LinkedData::Models::InterportalClass.graph_base_str)
        backup.class_urns.each do |class_urn|
          # get source and ontology from the backup URI from 4store (source(like urn):ontology(like STY):class)
          unless class_urn.start_with?("urn:")
            external_source = class_urn.split(":")[0]
            external_ontology = get_external_ont_from_urn(class_urn, prefix: external_source)
          end
        end
        classes = [LinkedData::Models::InterportalClass.new(c1, external_ontology, external_source),
                   read_only_class(c2, g2)]
      elsif g1 == LinkedData::Models::ExternalClass.graph_uri.to_s
        backup.class_urns.each do |class_urn|
          unless class_urn.start_with?("urn:")
            external_ontology = get_external_ont_from_urn(class_urn)
          end
        end
        classes = [LinkedData::Models::ExternalClass.new(c1, external_ontology),
                   read_only_class(c2, g2)]

        # Generate classes if g2 is interportal or external
      elsif g2.start_with?(LinkedData::Models::InterportalClass.graph_base_str)
        backup.class_urns.each do |class_urn|
          unless class_urn.start_with?("urn:")
            external_source = class_urn.split(':')[0]
            external_ontology = get_external_ont_from_urn(class_urn, prefix: external_source)
          end
        end
        classes = [read_only_class(c1, g1),
                   LinkedData::Models::InterportalClass.new(c2, external_ontology, external_source)]
      elsif g2 == LinkedData::Models::ExternalClass.graph_uri.to_s
        backup.class_urns.each do |class_urn|
          unless class_urn.start_with?("urn:")
            external_ontology = get_external_ont_from_urn(class_urn)
          end
        end
        classes = [read_only_class(c1, g1),
                   LinkedData::Models::ExternalClass.new(c2, external_ontology)]

      else
        classes = [read_only_class(c1, g1),
                   read_only_class(c2, g2)]
      end

      return classes
    end

    # A function only used in ncbo_cron. To make sure all triples that link mappings to class are well deleted (use of metadata/def/mappingRest predicate)
    def self.delete_all_rest_mappings_from_sparql
      rest_predicate = mapping_predicates()["REST"][0]
      actual_graph = ""
      count = 0
      qmappings = <<-eos
SELECT DISTINCT ?g ?class_uri ?backup_mapping
WHERE {
  GRAPH ?g {
    ?class_uri <#{rest_predicate}> ?backup_mapping .
  }
}
      eos
      epr = Goo.sparql_query_client(:main)
      epr.query(qmappings).each do |sol|
        if actual_graph == sol[:g].to_s && count < 4000
          # Trying to delete more than 4995 triples at the same time cause a memory error. So 4000 by 4000. Or until we met a new graph
          graph_delete << [RDF::URI.new(sol[:class_uri].to_s), RDF::URI.new(rest_predicate), RDF::URI.new(sol[:backup_mapping].to_s)]
        else
          if count == 0
          else
            Goo.sparql_update_client.delete_data(graph_delete, graph: RDF::URI.new(actual_graph))
          end
          graph_delete = RDF::Graph.new
          graph_delete << [RDF::URI.new(sol[:class_uri].to_s), RDF::URI.new(rest_predicate), RDF::URI.new(sol[:backup_mapping].to_s)]
          count = 0
          actual_graph = sol[:g].to_s
        end
        count = count + 1
      end
      if count > 0
        Goo.sparql_update_client.delete_data(graph_delete, graph: RDF::URI.new(actual_graph))
      end
    end

    def self.get_external_ont_from_urn(urn, prefix: 'ext')
      urn.to_s[/#{prefix}:(.*):(http.*)/, 1]
    end

    def self.get_rest_mapping(mapping_id)
      backup = LinkedData::Models::RestBackupMapping.find(mapping_id).include(:class_urns).first
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
        
        classes = get_mapping_classes_instance(sol[:c1].to_s, sol[:s1].to_s, sol[:c2].to_s, sol[:s2].to_s, backup)

        process = LinkedData::Models::MappingProcess.find(sol[:o]).first
        process.bring_remaining unless process.nil?
        mapping = LinkedData::Models::Mapping.new(classes, "REST",
                                                  process,
                                                  sol[:uuid])
      end
      mapping
    end

    def self.check_mapping_exist(cls, relations_array)
      class_urns = generate_class_urns(cls)
      mapping_exist = false
      qmappings = <<-eos
SELECT DISTINCT ?uuid ?urn1 ?urn2 ?p
WHERE {
  ?uuid <http://data.bioontology.org/metadata/class_urns> ?urn1 .
  ?uuid <http://data.bioontology.org/metadata/class_urns> ?urn2 .
  ?uuid <http://data.bioontology.org/metadata/process> ?p .
FILTER(?urn1 = <#{class_urns[0]}>)
FILTER(?urn2 = <#{class_urns[1]}>)
} LIMIT 10
      eos
      epr = Goo.sparql_query_client(:main)
      graphs = [LinkedData::Models::MappingProcess.type_uri]
      epr.query(qmappings,
                graphs: graphs).each do |sol|
        process = LinkedData::Models::MappingProcess.find(sol[:p]).include(:relation).first
        process_relations = process.relation.map { |r| r.to_s }
        relations_array = relations_array.map { |r| r.to_s }
        if process_relations.sort == relations_array.sort
          mapping_exist = true
          break
        end
      end
      return mapping_exist
    end

    def self.mappings_for_classids(class_ids, sources = ["REST", "CUI"])

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
                                 predicates.keys.map { |x| "?pred = <#{x}>" }.join(" || "))
      qmappings = qmappings.gsub("filter_classes",
                                 class_ids.map { |x| "?c1 = <#{x}>" }.join(" || "))
      epr = Goo.sparql_query_client(:main)
      graphs = [LinkedData::Models::MappingProcess.type_uri]
      mappings = []
      epr.query(qmappings,
                graphs: graphs).each do |sol|
        classes = [read_only_class(sol[:c1].to_s, sol[:s1].to_s),
                   read_only_class(sol[:c2].to_s, sol[:s2].to_s)]
        source = predicates[sol[:pred].to_s]
        mappings << LinkedData::Models::Mapping.new(classes, source)
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
      epr.query(qdate, graphs: graphs, query_options: { rules: :NONE }).each do |sol|
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
SELECT DISTINCT ?ont1 ?c1 ?s1 ?ont2 ?c2 ?s2 ?o ?uuid
WHERE {
  ?uuid <http://data.bioontology.org/metadata/process> ?o .
  OPTIONAL { ?s1 <http://data.bioontology.org/metadata/ontology> ?ont1 . }
  GRAPH ?s1 {
    ?c1 <#{rest_predicate}> ?uuid .
  }
  OPTIONAL { ?s2 <http://data.bioontology.org/metadata/ontology> ?ont2 . }
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
                graphs: graphs, query_options: { rules: :NONE }).each do |sol|

        if sol[:ont1].nil?
          # if the 1st class is from External or Interportal we don't want it to be in the list of recent, it has to be in 2nd
          next
        else
          ont1 = sol[:ont1].to_s
        end
        ont2 = if sol[:ont2].nil?
                 sol[:s2].to_s
               else
                 sol[:ont2].to_s
               end

        mapping_id = RDF::URI.new(sol[:uuid].to_s)
        backup = LinkedData::Models::RestBackupMapping.find(mapping_id).include(:class_urns).first
        classes = get_mapping_classes_instance(sol[:c1].to_s, ont1, sol[:c2].to_s, ont2, backup)

        process = proc_object[sol[:o].to_s]
        mapping = LinkedData::Models::Mapping.new(classes, "REST",
                                                  process,
                                                  sol[:uuid])
        mappings << mapping
      end
      mappings.sort_by { |x| x.process.date }.reverse[0..n - 1]
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

      submissions_query = if any
                            LinkedData::Models::OntologySubmission.where
                          else
                            LinkedData::Models::OntologySubmission.where(submissionStatus: [code: status])
                          end
      submissions_query = submissions_query.filter(Goo::Filter.new(ontology: [:viewOf]).unbound) unless include_views
      submissions = submissions_query.include(:submissionStatus, :submissionId, ontology: [:acronym]).to_a
      submissions.select! { |sub| acronyms.include?(sub.ontology.acronym) } unless acronyms.empty?
      latest_submissions = {}

      submissions.each do |sub|
        next if include_ready && !sub.ready?
        latest_submissions[sub.ontology.acronym] ||= sub
        latest_submissions[sub.ontology.acronym] = sub if sub.submissionId > latest_submissions[sub.ontology.acronym].submissionId
      end
      return latest_submissions
    end

    def self.create_mapping_counts(logger, arr_acronyms = [])
      ont_msg = arr_acronyms.empty? ? "all ontologies" : "ontologies [#{arr_acronyms.join(', ')}]"

      time = Benchmark.realtime do
        self.create_mapping_count_totals_for_ontologies(logger, arr_acronyms)
      end
      logger.info("Completed rebuilding total mapping counts for #{ont_msg} in #{(time / 60).round(1)} minutes.")

      time = Benchmark.realtime do
        self.create_mapping_count_pairs_for_ontologies(logger, arr_acronyms)
      end
      logger.info("Completed rebuilding mapping count pairs for #{ont_msg} in #{(time / 60).round(1)} minutes.")
    end

    def self.create_mapping_count_totals_for_ontologies(logger, arr_acronyms)
      new_counts = self.mapping_counts(enable_debug = true, logger = logger, reload_cache = true, arr_acronyms)
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
          if new_count == 0
            inst.delete
          elsif new_count != inst.count
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
      latest_submissions = self.retrieve_latest_submissions(options = { acronyms: arr_acronyms })
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
        self.handle_triple_store_downtime(logger)
        new_counts = nil
        time = Benchmark.realtime do
          new_counts = self.mapping_ontologies_count(sub, nil, reload_cache = true)
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
            if new_count == 0
              inst.delete
            elsif new_count != inst.count
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
            m.ontologies = [acr, other]
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

  end
end