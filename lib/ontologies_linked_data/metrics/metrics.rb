module LinkedData
  module Metrics
    def self.metrics_for_submission(submission,logger)
      logger.info("metrics_for_submission start")
      logger.flush
      begin
        submission.bring(:submissionStatus) if submission.bring?(:submissionStatus)

        cls_metrics = class_metrics(submission,logger)
        logger.info("class_metrics finished")
        logger.flush

        metrics = LinkedData::Models::Metric.new
        cls_metrics.each do |k,v|
          unless v.instance_of?(Integer)
            begin
              v = Integer(v)
            rescue ArgumentError
              v = 0
            end
          end
          metrics.send("#{k}=",v)
        end
        metrics.individuals = number_individuals(submission)
        logger.info("individuals finished")
        logger.flush
        metrics.properties = number_properties(submission)
        logger.info("properties finished")
        logger.flush
        return metrics
      rescue Exception => e
        logger.error(e.message)
        logger.error(e)
        logger.flush
      end
      return nil
    end

    def self.class_metrics(submission,logger)
      t00 = Time.now
      submission.ontology.bring(:flat) if submission.ontology.bring?(:flat)

      is_flat = submission.ontology.flat
      roots = submission.roots
      
      max_depth = 0
      unless is_flat
        depths = []
        rdfsSC = Goo.namespaces[:rdfs][:subClassOf]
        roots.each do |root|
          ok = true
          n=1
          while ok
            ok = hierarchy_depth?(submission.id.to_s,root.id.to_s,n,rdfsSC)
            if ok
              n += 1
            end
            if n > 40
              #safe guard
              ok = false
            end
          end
          n -= 1
          depths << n
        end
        max_depth = depths.max
      end
      cls_metrics = {}
      cls_metrics[:classes] = 0
      cls_metrics[:averageChildCount] = 0
      cls_metrics[:maxChildCount] = 0
      cls_metrics[:classesWithOneChild] = 0
      cls_metrics[:classesWithMoreThan25Children] = 0
      cls_metrics[:classesWithNoDefinition] = 0
      cls_metrics[:maxDepth] = max_depth
      definitionP = [Goo.namespaces[:skos][:definition],
                     LinkedData::Utils::Triples.obo_definition_standard(), 
                     Goo.namespaces[:rdfs][:comment] ]
      submission.bring(:definitionProperty)
      unless submission.definitionProperty.nil?
        definitionP << submission.definitionProperty
      end
      t0 = Time.now
      groupby_children = query_groupby_classes(submission.id,rdfsSC)
      logger.info("Metrics groupby_children retrieved #{groupby_children.length}" +
                  " in #{Time.now - t0} sec.")
      logger.flush
      children_counts = []
      groupby_children.each do |cls,count|
        unless cls.start_with?("http")
          next
        end
        unless is_flat
          if count > 24
            cls_metrics[:classesWithMoreThan25Children] += 1
          end
          if count == 1
            cls_metrics[:classesWithOneChild] += 1
          end
          if count > 0
            children_counts << count
          end
          if count > cls_metrics[:maxChildCount]
            cls_metrics[:maxChildCount] = count
          end
        end
      end
      t0 = Time.now
      count_classes = query_count_classes(submission.id)
      cls_metrics[:classes] = count_classes
      logger.info("Metrics count_classes retrieved #{count_classes}"+
                  " in #{Time.now - t0} sec.")
      logger.flush
      t0 = Time.now
      withDef =  query_count_definitions(submission.id,definitionP)
      logger.info("Metrics count cls with def #{withDef}" +
                  " in #{Time.now - t0} sec.")
      logger.flush
      cls_metrics[:classesWithNoDefinition] = cls_metrics[:classes] - withDef
      sum = 0
      children_counts.each do |c|
        sum += c
      end
      if children_counts.length > 0
        cls_metrics[:averageChildCount]  = (sum.to_f / children_counts.length.to_f).to_i
      end
      logger.info("Class metrics finished in #{Time.now - t00} sec.")
      logger.flush
      return cls_metrics
    end

    def self.recursive_depth(cls,classes,depth,visited)
      if depth > 60
        #safety for cycles.
        return depth
      end
      children = classes[cls]
      branch_depts = [depth+1]
      children.each do |ch|
        if classes[ch] && !visited.include?(ch)
          visited << ch
          branch_depts << recursive_depth(ch,classes,depth+1,visited)
        end
      end
      return branch_depts.max
    end

    def self.number_individuals(submission)
      return count_owl_type(submission.id,"NamedIndividual")
    end

    def self.number_properties(submission)
      props = count_owl_type(submission.id,"DatatypeProperty")
      props += count_owl_type(submission.id,"ObjectProperty")
      return props
    end

    def self.hierarchy_depth?(graph,root,n,treeProp)
      sTemplate = "children <#{treeProp.to_s}> parent"
      hops = []
      n.times do |i|
        hop = sTemplate.sub("children","?x#{i}")
        if i == 0
          hop = hop.sub("parent", "<#{root.to_s}>")
        else
          hop = hop.sub("parent", "?x#{i-1}")
        end
        hops << hop
      end
      joins = hops.join(".\n")
      query = <<eof
SELECT ?x0 WHERE {
  GRAPH <#{graph.to_s}> {
    #{joins}
  } } LIMIT 1
eof
      rs = Goo.sparql_query_client.query(query)
      rs.each do |sol|
        return true
      end
      return false
    end
    
    def self.query_count_definitions(subId,defProps)
      propFilter = defProps.map { |x| "?p = <#{x.to_s}>" }
      propFilter = propFilter.join " || "
      query = <<-eos
SELECT (count(?s) as ?c) WHERE { 
    GRAPH <#{subId.to_s}> {
          ?s a <#{Goo.namespaces[:owl][:Class]}> .
            ?s ?p ?o .
          FILTER ( properties )
          FILTER ( !isBlank(?s) )
          FILTER (?s != <#{Goo.namespaces[:owl][:Thing]}>)
}}
eos
      query = query.sub("properties", propFilter)
      rs = Goo.sparql_query_client.query(query)
      rs.each do |sol|
        return sol[:c].object
      end
      return 0
    end

    def self.query_groupby_classes(subId,treeProp)
      query = <<-eos
SELECT ?o (count(?s) as ?c) WHERE { 
    GRAPH <#{subId.to_s}> {
          ?s <#{treeProp.to_s}> ?o .
    FILTER (?s != <#{Goo.namespaces[:owl][:Thing]}>)
    }}
GROUP BY ?o
eos
      rs = Goo.sparql_query_client.query(query)
      groupby_counts = {}
      rs.each do |sol|
        groupby_counts[sol[:o].to_s] = sol[:c].object
      end
      return groupby_counts
    end

    def self.query_count_classes(subId)
      query = <<-eos
SELECT (count(?s) as ?c) WHERE {
    GRAPH <#{subId.to_s}> {
      ?s a <#{Goo.namespaces[:owl][:Class]}> .
      FILTER(!isBlank(?s))
      FILTER (?s != <#{Goo.namespaces[:owl][:Thing]}>)
    }
}
eos
      rs = Goo.sparql_query_client.query(query)
      rs.each do |sol|
        return sol[:c].object
      end
      return 0
    end

    def self.count_owl_type(graph,name)
      owl_type = Goo.namespaces[:owl][name]
      query = <<eof
SELECT (COUNT(?s) as ?count) WHERE {
  GRAPH #{graph.to_ntriples} {
    ?s a #{owl_type.to_ntriples}
    FILTER (?s != <#{Goo.namespaces[:owl][:Thing]}>)
  } }
eof
      rs = Goo.sparql_query_client.query(query)
      rs.each do |sol|
        return sol[:count].object
      end
      return 0
    end

  end
end
