module LinkedData
module Mappings

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

  def self.retrieve_latest_submissions()
    status = "RDF"
    include_ready = status.eql?("READY") ? true : false
    status = "RDF" if status.eql?("READY")
    includes = []
    includes << :submissionStatus
    includes << :submissionId
    includes << { ontology: [:acronym, :viewOf] }
    submissions_query = LinkedData::Models::OntologySubmission
                          .where(submissionStatus: [ code: status])

    filter = Goo::Filter.new(ontology: [:viewOf]).unbound
    submissions_query = submissions_query.filter(filter)
    submissions = submissions_query.include(includes).to_a

    # Figure out latest parsed submissions using all submissions
    latest_submissions = {}
    submissions.each do |sub|
      next if include_ready && !sub.ready?
      latest_submissions[sub.ontology.acronym] ||= sub
      otherId = latest_submissions[sub.ontology.acronym].submissionId
      if sub.submissionId > otherId
        latest_submissions[sub.ontology.acronym] = sub
      end
    end
    return latest_submissions
  end

  def self.mapping_counts(enable_debug=false,logger=nil,reload_cache=false)
    if enable_debug and logger.nil?
      logger = Logger.new($stdout)
    end
    t = Time.now
    latest = retrieve_latest_submissions()
    counts = {}
    i = 0
    latest.each do |acro,sub|
      t0 = Time.now
      s_counts = mapping_ontologies_count(sub,nil,reload_cache=reload_cache)
      s_total = 0
      s_counts.each do |k,v|
        s_total += v
      end
      counts[acro] = s_total
      i += 1
      if enable_debug
        puts "#{i}/#{latest.count} " +
            "Time for #{acro} took #{Time.now - t0} sec. records #{s_total}"
      end
    end
    if enable_debug
      puts "Total time #{Time.now - t} sec."
    end
    return counts
  end

  def self.mapping_ontologies_count(sub1,sub2,reload_cache=false)
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
    group_count = nil
    count = 0
    if sub2.nil?
      group_count = {}
    end
    mapping_predicates().each do |_source,mapping_predicate| 
      block = template.gsub("predicate", mapping_predicate[0])
      if sub2.nil?
      else
      end
      query_template = <<-eos
      SELECT variables 
      WHERE {
      block
      filter
      } group
eos
      query = query_template.sub("block", block)
      filter = ""
      if _source != "SAME_URI"
        filter += "FILTER (?s1 != ?s2)"
      end
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
      epr = Goo.sparql_query_client(:main)
      graphs = [sub1.id, LinkedData::Models::MappingProcess.type_uri]
      unless sub2.nil?
        graphs << sub2.id
      end
      solutions = nil
      if sub2.nil?
        solutions = epr.query(query,
                              graphs: graphs, reload_cache: reload_cache)
        solutions.each do |sol|
          acr = sol[:g].to_s.split("/")[-3]
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

  def self.mappings_ontologies(sub1,sub2,page,size,classId=nil,reload_cache=false)
    persistent_count = 0
    pcount = LinkedData::Models::MappingCount.where(
        ontologies: [sub1.ontology.acronym]
    ).and(pair_count: false)
    if not sub2.nil?
      pcount = pcount.and(ontologies: [sub2.ontology.acronym])
    end
    pcount = pcount.all
    if pcount.length == 0
      persistent_count = 0
    else
      persistent_count = pcount.first
    end
    if persistent_count == 0
        p = Goo::Base::Page.new(page,size,nil,[])
        p.aggregate = 0
        return p
    end
    mappings = []
    union_template = <<-eos
{
  GRAPH <#{sub1.id.to_s}> {
      classId <predicate> ?o .
  }
  GRAPH graph {
      ?s2 <predicate> ?o .
  }
  bind 
}
eos

    if classId.nil?
      union_template = union_template.sub("classId", "?s1")
    else
      union_template = union_template.sub("classId", "<#{classId.to_s}>")
    end

    blocks = []
    mapping_predicates().each do |_source,mapping_predicate| 
      union_block = union_template.gsub("predicate", mapping_predicate[0])
      union_block = union_block.sub("bind","BIND ('#{_source}' AS ?source)")
      if sub2.nil?
        union_block = union_block.sub("graph","?g")
      else
        union_block = union_block.sub("graph","<#{sub2.id.to_s}>")
      end
      blocks << union_block
    end
    unions = blocks.join("\nUNION\n")

    mappings_in_ontology = <<-eos
SELECT variables 
WHERE {
unions
filter
} page_group 
eos
    query = mappings_in_ontology.sub( "unions", unions)
    variables = "?s2 graph ?source ?o"
    if classId.nil?
      variables = "?s1 " + variables
    end
    query = query.sub("variables", variables)
    filter = ""
    if classId.nil?
      filter = "FILTER ((?s1 != ?s2) || (?source = 'SAME_URI'))"
    else
      filter = ""
    end
    if sub2.nil?
      query = query.sub("graph","?g")
      ont_id = sub1.id.to_s.split("/")[0..-3].join("/")
      #STRSTARTS is used to not count older graphs
      filter += "\nFILTER (!STRSTARTS(str(?g),'#{ont_id}'))"
      query = query.sub("filter",filter)
    else
      query = query.sub("graph","")
      query = query.sub("filter",filter)
    end
    if size > 0
      pagination = "OFFSET offset LIMIT limit"
      query = query.sub("page_group",pagination)
      limit = size
      offset = (page-1) * size
      query = query.sub("limit", "#{limit}").sub("offset", "#{offset}")
    else
      query = query.sub("page_group","")
    end
    epr = Goo.sparql_query_client(:main)
    graphs = [sub1.id]
    unless sub2.nil?
      graphs << sub2.id
    end
    solutions = epr.query(query,
                          graphs: graphs, reload_cache: reload_cache)
    s1 = nil
    unless classId.nil?
      s1 = RDF::URI.new(classId.to_s)
    end
    solutions.each do |sol|
      graph2 = nil
      if sub2.nil?
        graph2 = sol[:g]
      else
        graph2 = sub2.id
      end
      if classId.nil?
        s1 = sol[:s1]
      end
      classes = [ read_only_class(s1.to_s,sub1.id.to_s),
                read_only_class(sol[:s2].to_s,graph2.to_s) ]

      backup_mapping = nil
      mapping = nil
      if sol[:source].to_s == "REST"
        backup_mapping = LinkedData::Models::RestBackupMapping
                      .find(sol[:o]).include(:process).first
        backup_mapping.process.bring_remaining
      end
      if backup_mapping.nil?
        mapping = LinkedData::Models::Mapping.new(
                    classes,sol[:source].to_s)
      else
        mapping = LinkedData::Models::Mapping.new(
                    classes,sol[:source].to_s,
                    backup_mapping.process,backup_mapping.id)
      end
      mappings << mapping
    end
    if size == 0
      return mappings
    end
    page = Goo::Base::Page.new(page,size,nil,mappings)
    page.aggregate = persistent_count
    return page
  end

  def self.mappings_ontology(sub,page,size,classId=nil,reload_cache=false)
    return self.mappings_ontologies(sub,nil,page,size,classId=classId,
                                    reload_cache=reload_cache)
  end

  def self.read_only_class(classId,submissionId)
      ontologyId = submissionId.split("/")[0..-3]
      acronym = ontologyId.last
      ontologyId = ontologyId.join("/")
      ontology = LinkedData::Models::Ontology
            .read_only(
              id: RDF::IRI.new(ontologyId),
              acronym: acronym)
      submission = LinkedData::Models::OntologySubmission
            .read_only(
              id: RDF::IRI.new(ontologyId+"/submissions/latest"),
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
SELECT ?s1 ?c1 ?s2 ?c2 ?uuid ?o
WHERE { 
  ?uuid <http://data.bioontology.org/metadata/process> ?o .

  GRAPH ?s1 {
    ?c1 <#{rest_predicate}> ?uuid .
  }
  GRAPH ?s2 {
    ?c2 <#{rest_predicate}> ?uuid .
  }
FILTER(?uuid = <#{mapping_id}>)
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
        sub = LinkedData::Models::Ontology.find(c.submission.ontology.id)
                .first
                .latest_submission
      end
      graph_insert = RDF::Graph.new
      graph_insert << [c.id, RDF::URI.new(rest_predicate), backup_mapping.id]
      Goo.sparql_update_client.insert_data(graph_insert, graph: sub.id)
    end
    mapping = LinkedData::Models::Mapping.new(classes,"REST",process)
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
SELECT ?s
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
SELECT ?s1 ?c1 ?s2 ?c2 ?o ?uuid
WHERE { 
  ?uuid <http://data.bioontology.org/metadata/process> ?o .

  GRAPH ?s1 {
    ?c1 <#{rest_predicate}> ?uuid .
  }
  GRAPH ?s2 {
    ?c2 <#{rest_predicate}> ?uuid .
  }
FILTER (#{procs})
}
eos
    epr = Goo.sparql_query_client(:main)
    mappings = []
    epr.query(qmappings, 
              graphs: graphs,query_options: {rules: :NONE}).each do |sol|
      classes = [ read_only_class(sol[:c1].to_s,sol[:s1].to_s),
                read_only_class(sol[:c2].to_s,sol[:s2].to_s) ]
      process = proc_object[sol[:o].to_s]
      mapping = LinkedData::Models::Mapping.new(classes,"REST",
                                                process,
                                                sol[:uuid])
      mappings << mapping
    end
    return mappings.sort_by { |x| x.process.date }.reverse[0..n-1]
  end

end
end
