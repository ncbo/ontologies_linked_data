require_relative "batch"
require_relative "loom"
require_relative "cuis"
require_relative "same_uris"
require_relative "xref"

module LinkedData
module Mappings

  def self.create_term_mapping(term_uris,acronym,ontology=nil,batch_update_file=nil)
    id_term_mapping = LinkedData::Models::TermMapping.term_mapping_id_generator(term_uris,acronym)
    return id_term_mapping if exist_term_mapping?(term_uris,acronym)
    term = LinkedData::Models::TermMapping.new
    term.ontology = ontology ? ontology :
                      LinkedData::Models::Ontology.find(acronym).include(:acronym).first
    term.term = term_uris
    term.save(batch: batch_update_file)
    return id_term_mapping
  end

  def self.exist_term_mapping?(term_uris,ontology)
    id_term_mapping = LinkedData::Models::TermMapping.term_mapping_id_generator(term_uris,ontology)
    return LinkedData::Models::TermMapping.find(id_term_mapping).first
  end

  def self.create_mapping(term_mapping_ids,batch_update_file=nil)
    id_mapping = LinkedData::Models::Mapping.mapping_id_generator_iris(*term_mapping_ids)
    return id_mapping if exist_mapping?(term_mapping_ids)
    mapping = LinkedData::Models::Mapping.new
    term_mappings = term_mapping_ids.map { |x| LinkedData::Models::TermMapping.read_only(id: x) }
    mapping.terms = term_mappings
    mapping.save(batch: batch_update_file)
    return id_mapping
  end

  def self.exist_mapping?(term_mapping_ids)
    id_mapping = LinkedData::Models::Mapping.mapping_id_generator_iris(*term_mapping_ids)
    return LinkedData::Models::Mapping.find(id_mapping).first
  end

  def self.connect_mapping_process(mapping_id,process,batch_update_file=nil)
    mapping = LinkedData::Models::Mapping.find(mapping_id).include(:process).first
    unless mapping
      raise ArgumentError, "Mapping id #{mapping_id.to_ntriples} not found"
    end
    return if mapping.process.select { |p| p.id.tos == process.id.to_s }.length > 0
    if batch_update_file.nil?
      mapping = LinkedData::Models::Mapping.find(mapping_id)
                                              .include(:process)
                                              .include(:terms)
                                              .first
      map_procs = mapping.process.dup
      return if map_procs.map { |x| x.id.to_s }.index(process.id.to_s)
      map_procs << process
      mapping.process = map_procs
      mapping.save
    else
      triple =
      [mapping_id.to_ntriples,
       LinkedData::Models::Mapping.attribute_uri(:process).to_ntriples,
       process.id.to_ntriples ].join(" ") + " .\n"
      batch_update_file.write(triple)
      batch_update_file.flush()
    end
    nil
  end

  def self.disconnect_mapping_process(mapping_id,process)
    mapping = LinkedData::Models::Mapping.find(id_mapping)
                  .include(:process)
                  .incude(:terms)
                  .first
    unless mapping
      raise ArgumentError, "Mapping id #{mapping_id.to_ntriples} not found"
    end
    return if mapping.process.select { |p| p.id.tos == process.id.to_s }.length > 0
    map_procs = mapping.process.dup
    new_procs = map_procs.select { |x| x.id.to_s != process.id.to_s }
    mapping.process = new_procs
    mapping.save
  end

  def self.delete_mapping(mapping)
    mapping.bring(:terms) if mapping.bring?(:terms)
    mapping.terms.each do |t|
      t.bring(:mappings)
      #only this mapping pointing to the termmapping
      if t.mappings.length == 1
        delete_term_mapping(t)
      end
    end
    mapping.delete
  end

  def self.delete_term_mapping(tm)
    tm.delete
  end

  def self.mapping_counts_for_ontology(ont)
    graphs = [LinkedData::Models::TermMapping.type_uri,LinkedData::Models::Mapping.type_uri]
    sparql_query = <<-eos
    SELECT (strbefore(substr(str(?tid), 50),'/') as ?acr)
  FROM <#{LinkedData::Models::Mapping.type_uri}>
  FROM <#{LinkedData::Models::TermMapping.type_uri}>
  WHERE {
  ?id <http://data.bioontology.org/metadata/terms> [
    <http://data.bioontology.org/metadata/ontology> #{ont.id.to_ntriples}  ] .
  ?id <http://data.bioontology.org/metadata/terms> ?tid . }
eos
    result = {}
    epr = Goo.sparql_query_client(:main)
    this_acr = ont.id.split("/")[-1]
    sols = epr.query(sparql_query, graphs: graphs)
    sols.delete(this_acr)
    return sols
  end

  def self.mapping_counts_per_ontology()
    graphs = [LinkedData::Models::TermMapping.type_uri]
    ontologies = LinkedData::Models::Ontology.where.all
    result = {}
    ontologies.each do |ont|
      sparql_query = <<-eos
  SELECT  (COUNT(?id) AS ?count_var )
  FROM <#{LinkedData::Models::TermMapping.type_uri}>
  WHERE {
      ?id  <http://data.bioontology.org/metadata/ontology>  #{ont.id.to_ntriples} . }
  eos
      epr = Goo.sparql_query_client(:main)
      solutions = epr.query(sparql_query, graphs: graphs).each do |sol|
          result[ont.id.to_s.split("/")[-1]] = sol[:count_var].object
      end
    end
    return result
  end

  def self.recent_user_mappings(n)
    graphs = [LinkedData::Models::MappingProcess.type_uri]
    qdate = <<-eos
SELECT ?s
FROM <#{LinkedData::Models::MappingProcess.type_uri}>
WHERE { ?s <http://data.bioontology.org/metadata/date> ?o } ORDER BY DESC(?o) LIMIT #{n}
eos
    epr = Goo.sparql_query_client(:main)
    procs = []
    epr.query(qdate, graphs: graphs).each do |sol|
      procs << sol[:s]
    end
    graphs = [LinkedData::Models::MappingProcess.type_uri]
    procs = procs.map { |x| "?o = #{x.to_ntriples}" }.join " || "
    qmappings = <<-eos
SELECT ?s
FROM <#{LinkedData::Models::Mapping.type_uri}>
WHERE { ?s <http://data.bioontology.org/metadata/process> ?o .
FILTER (#{procs})
}
eos
    epr = Goo.sparql_query_client(:main)
    mapping_ids = []
    epr.query(qmappings, graphs: graphs).each do |sol|
      mapping_ids << sol[:s]
    end
    mappings = mapping_ids.map { |x| LinkedData::Models::Mapping.find(x)
                                     .include(terms: [ :term, ontology: [ :acronym ] ])
                                     .include(process: [:name, :creator, :date ])
                                     .first 
                               }
    return mappings.sort_by { |x| x.process.first.date }.reverse[0..n-1]
  end

end
end
