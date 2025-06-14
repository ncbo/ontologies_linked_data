require_relative './test_ontology_common'
require 'logger'
require 'rack'

class TestOntologySubmission < LinkedData::TestOntologyCommon

  def before_suite
    submission_parse('SKOS-TEST',
                     'SKOS TEST Bla',
                     './test/data/ontology_files/efo_gwas.skos.owl', 987,
                     process_rdf: true, index_search: false,
                     run_metrics: false, reasoning: true)

    sub = LinkedData::Models::OntologySubmission.where(ontology: [acronym: 'SKOS-TEST'],
                                                       submissionId: 987)
                                                .first
    sub.bring_remaining
    sub.uri = 'http://www.ebi.ac.uk/efo/skos/EFO_GWAS_view'
    sub.save
    sub
  end

  def test_get_main_concept_scheme
    sub = before_suite
    assert_equal sub.uri, sub.get_main_concept_scheme.to_s
  end

  def test_roots_no_main_scheme

    sub = before_suite
    sub.uri = nil # no concept scheme as owl:ontology found
    sub.save
    assert_nil sub.get_main_concept_scheme
    # if no main scheme found get all roots (topConcepts)
    assert sub.roots.map { |x| x.id.to_s }.sort == ['http://www.ebi.ac.uk/efo/EFO_0000311',
                                                    'http://www.ebi.ac.uk/efo/EFO_0001444',
                                                    'http://www.ifomis.org/bfo/1.1/snap#Disposition',
                                                    'http://www.ebi.ac.uk/chebi/searchId.do?chebiId=CHEBI:37577',
                                                    'http://www.ebi.ac.uk/efo/EFO_0000635',
                                                    'http://www.ebi.ac.uk/efo/EFO_0000324'].sort
    roots = sub.roots
    LinkedData::Models::Class.in(sub).models(roots).include(:children).all
    roots.each do |root|
      q_broader = <<-eos
SELECT ?children WHERE {
  ?children #{RDF::SKOS[:broader].to_ntriples} #{root.id.to_ntriples} }
      eos
      children_query = []
      Goo.sparql_query_client.query(q_broader).each_solution do |sol|
        children_query << sol[:children].to_s
      end
      assert root.children.map { |x| x.id.to_s }.sort == children_query.sort
    end
  end

  def test_roots_main_scheme
    sub = before_suite

    roots = sub.roots
    assert_equal 4, roots.size
    roots.each do |r|
      assert_equal r.isInActiveScheme, [sub.get_main_concept_scheme.to_s]
      assert_equal r.isInActiveCollection, []
    end
    roots = roots.map { |r| r.id.to_s } unless roots.nil?
    refute_includes roots, 'http://www.ebi.ac.uk/efo/EFO_0000311'
    refute_includes roots, 'http://www.ebi.ac.uk/efo/EFO_0000324'
  end

  def test_roots_of_a_scheme
    sub = before_suite
    concept_schemes = ['http://www.ebi.ac.uk/efo/skos/EFO_GWAS_view_2']
    roots = sub.roots(concept_schemes: concept_schemes)
    assert_equal 2, roots.size
    roots.each do |r|
      assert_includes r.inScheme, concept_schemes.first
      assert_equal r.isInActiveScheme, concept_schemes
      assert_equal r.isInActiveCollection, []
    end
    roots = roots.map { |r| r.id.to_s } unless roots.nil?
    assert_includes roots, 'http://www.ebi.ac.uk/efo/EFO_0000311'
    assert_includes roots, 'http://www.ebi.ac.uk/efo/EFO_0000324'
  end

  def test_roots_of_multiple_scheme
    sub = before_suite

    concept_schemes = ['http://www.ebi.ac.uk/efo/skos/EFO_GWAS_view_2',
                       'http://www.ebi.ac.uk/efo/skos/EFO_GWAS_view']
    roots = sub.roots(concept_schemes: concept_schemes)
    assert_equal 6, roots.size
    roots.each do |r|
      selected_schemes = r.inScheme.select { |s| concept_schemes.include?(s) }
      refute_empty selected_schemes
      assert_equal r.isInActiveScheme, selected_schemes
      assert_equal r.isInActiveCollection, []
    end
    roots = roots.map { |r| r.id.to_s } unless roots.nil?
    assert roots.sort == ['http://www.ebi.ac.uk/efo/EFO_0000311',
                          'http://www.ebi.ac.uk/efo/EFO_0001444',
                          'http://www.ifomis.org/bfo/1.1/snap#Disposition',
                          'http://www.ebi.ac.uk/chebi/searchId.do?chebiId=CHEBI:37577',
                          'http://www.ebi.ac.uk/efo/EFO_0000635',
                          'http://www.ebi.ac.uk/efo/EFO_0000324'].sort
  end

  def test_roots_of_scheme_collection
    sub = before_suite

    concept_schemes = ['http://www.ebi.ac.uk/efo/skos/EFO_GWAS_view']
    concept_collection = ['http://www.ebi.ac.uk/efo/skos/collection_1']
    roots = sub.roots(concept_schemes: concept_schemes, concept_collections: concept_collection)
    assert_equal 4, roots.size

    roots.each do |r|
      assert_equal r.isInActiveCollection, concept_collection if r.memberOf.include?(concept_collection.first)
    end
  end

  def test_roots_of_scheme_collections
    sub = before_suite

    concept_schemes = ['http://www.ebi.ac.uk/efo/skos/EFO_GWAS_view']
    concept_collection = ['http://www.ebi.ac.uk/efo/skos/collection_1',
                          'http://www.ebi.ac.uk/efo/skos/collection_2']
    roots = sub.roots(concept_schemes: concept_schemes, concept_collections: concept_collection)
    assert_equal 4, roots.size

    roots.each do |r|
      selected_collections = r.memberOf.select { |c| concept_collection.include?(c)}
      assert_equal r.isInActiveCollection, selected_collections unless selected_collections.empty?
    end
  end
end

