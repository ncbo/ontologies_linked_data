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
      size_page = 2500
      paging = LinkedData::Models::Class.in(submission)
                                        .include(:children,:definition)
                                        .page(1,size_page)
      submission.ontology.bring(:flat) if submission.ontology.bring?(:flat)

      roots = submission.roots
      
      depths = []
      roots.each do |root|
        rdfsSC = Goo.namespaces[:rdfs][:subClassOf]
        ok = true
        n=1
        while ok
          ok = hierarchy_depth?(submission.id.to_s,root.id.to_s,n,rdfsSC)
          if ok
            n += 1
          end
        end
        n -= 1
        depths << n
      end
      max_dept = depths.max
      binding.pry
      is_flat = submission.ontology.flat
      cls_metrics = {}
      cls_metrics[:classes] = 0
      cls_metrics[:averageChildCount] = 0
      cls_metrics[:maxChildCount] = 0
      cls_metrics[:classesWithOneChild] = 0
      cls_metrics[:classesWithMoreThan25Children] = 0
      cls_metrics[:classesWithNoDefinition] = 0
      cls_metrics[:maxDepth] = 0
      page = 1
      children_counts = []
      classes_children = {}
      begin
        t0 = Time.now
        page_classes = paging.page(page).all
        logger.info("Metrics Classes Page #{page} of #{page_classes.total_pages}"+
                    " classes retrieved in #{Time.now - t0} sec.")
        logger.flush
        page_classes.each do |cls|
          cls_metrics[:classes] += 1
          #TODO: investigate
          #for some weird reason NIFSTD brings false:FalseClass here
          unless cls.definition.is_a?(Array) && cls.definition.length > 0
            cls_metrics[:classesWithNoDefinition] += 1
          end
          unless is_flat
            if cls.children.length > 24
              cls_metrics[:classesWithMoreThan25Children] += 1
            end
            if cls.children.length == 1
              cls_metrics[:classesWithOneChild] += 1
            end
            if cls.children.length > 0
              children_counts << cls.children.length
              classes_children[cls.id.to_s] = cls.children.map { |x| x.id.to_s}
            end
          end
        end
        page = page_classes.next? ? page + 1 : nil
      end while(!page.nil?)
      unless is_flat
        roots_depth = [0]
        visited = Set.new
        roots = submission.roots
        if roots.length > 0
          roots = roots.map { |x| x.id.to_s }
          roots.each do |root|
            next if classes_children[root].nil?
            roots_depth << recursive_depth(root,classes_children,1,visited)
            visited << root
          end
        end
        cls_metrics[:maxDepth]=roots_depth.max
        if children_counts.length > 0
          cls_metrics[:maxChildCount] = children_counts.max
          sum = 0
          children_counts.each do |x|
            sum += x
          end
          cls_metrics[:averageChildCount]  = (sum.to_f / children_counts.length).to_i
        end
      end
      logger.info("Class metrics finished in #{Time.now - t00} sec.")
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
      puts query
      rs = Goo.sparql_query_client.query(query)
      rs.each do |sol|
        return true
      end
      return false
    end

    def self.count_owl_type(graph,name)
      owl_type = Goo.namespaces[:owl][name]
      query = <<eof
SELECT (COUNT(?s) as ?count) WHERE {
  GRAPH #{graph.to_ntriples} {
    ?s a #{owl_type.to_ntriples}
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
