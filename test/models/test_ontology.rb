require_relative "./test_ontology_common"
require_relative "../../lib/ontologies_linked_data/purl/purl_client"

class TestOntology < LinkedData::TestOntologyCommon

  def self.before_suite
    _, @@thread, @@port = self.new('').start_server
  end

  def self.after_suite
    @@thread[:webrick]&.shutdown
    Thread.kill(@@thread)
  end

  def setup
    @acronym = "ONT-FOR-TEST"
    @name = "TestOntology TEST"
    _delete_objects

    @user = LinkedData::Models::User.find("tim").first ||
               LinkedData::Models::User.new(username: "tim", email: "tim@example.org", password: "password").save

    @of = LinkedData::Models::OntologyFormat.find("OWL").first ||
            LinkedData::Models::OntologyFormat.new(acronym: "OWL").save

    cname = "Jeff Baines"
    cemail = "jeff@example.org"
    @contact = LinkedData::Models::Contact.where(name: cname, email: cemail).to_a[0]
    @contact = LinkedData::Models::Contact.new(name: cname, email: cemail).save if @contact.nil?
  end

  def teardown
    super
    _delete_objects
    delete_ontologies_and_submissions
  end

  def _create_ontology_with_submissions
    _delete_objects

    o = LinkedData::Models::Ontology.new({
      acronym: @acronym,
      administeredBy: [@user],
      name: @name
    })
    o.save

    os = LinkedData::Models::OntologySubmission.new({
      ontology: o,
      hasOntologyLanguage: @of,
      pullLocation: RDF::IRI.new("http://localhost:#{@@port}/"),
      submissionId: o.next_submission_id,
      contact: [@contact],
      released: DateTime.now - 5,
      description: 'description example',
      uri: RDF::URI.new('https://test.com'),
      status: 'beta'
    })
    os.save
  end

  def _delete_objects
    o = LinkedData::Models::Ontology.find(@acronym).first
    o.delete unless o.nil?
  end

  def _add_statuses(ont, submission_id, codes)
    sub = LinkedData::Models::OntologySubmission.where(ontology: ont, submissionId: submission_id).first
    sub.bring(*LinkedData::Models::OntologySubmission.attributes)
    codes.each do |code|
      sub.add_submission_status(LinkedData::Models::SubmissionStatus.find(code).include(:code).first)
    end
    sub.save
  end

  def test_ontology_acronym_existence
    o = LinkedData::Models::Ontology.new
    o.name = @name
    o.administeredBy = [@user]
    # acronym is not set yet, should be detected exception thrown
    assert_raises Goo::Base::IDGenerationError do
      o.valid?
    end
    _delete_objects
  end

  def test_ontology_acronym_unique
    _create_ontology_with_submissions
    o1 = LinkedData::Models::Ontology.find(@acronym).first
    assert(!o1.nil?, "Failed to create/save/read #{@acronym}.")
    o1.bring_remaining
    o2 = LinkedData::Models::Ontology.new
    o2.name = @name
    o2.administeredBy = [@user]
    o2.acronym = @acronym
    assert_equal(o1.acronym, o2.acronym, "Failed to set same acronym on o1 and o2")
    # o1 and o2 have the same acronym, should be detected and reported in o2.errors:
    assert(!o2.valid?, "Failed to invalidate duplicate ontology acronym.")
    assert(!o2.errors[:acronym].nil? && !o2.errors[:acronym][:duplicate].nil?,
      "Failed to invalidate duplicate ontology acronym.")
    _delete_objects
  end

  def test_ontology_acronym_validity
    too_long = %w("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", "WAY_TOO_LONG_WAY_TOO_LONG")
    disallowed_chars = %w(TEST$#@ONT, X^MEN)
    lowercase = %w(aaaaa AAaa aaAA)
    starts_with_num = %w(99BOTTLES, 100PERCENT)
    all_bad = "99TEST$$$$$$$$$ONTaaONTaa"

    ont = LinkedData::Models::Ontology.new

    too_long.each do |a|
      ont.acronym = a
      assert _acronym_validation_failed_with_error?(ont, :length)
    end

    disallowed_chars.each do |a|
      ont.acronym = a
      assert _acronym_validation_failed_with_error?(ont, :special_characters)
    end

    lowercase.each do |a|
      ont.acronym = a
      assert _acronym_validation_failed_with_error?(ont, :capital_letters)
    end

    starts_with_num.each do |a|
      ont.acronym = a
      assert _acronym_validation_failed_with_error?(ont, :start_with_letter)
    end

    ont.acronym = all_bad
    ont.valid?
    errors = ont.errors[:acronym]
    assert errors.key? :length
    assert errors.key? :special_characters
    assert errors.key? :capital_letters
    assert errors.key? :start_with_letter

    o = LinkedData::Models::Ontology.new
    o.acronym = "A"  # must begin with at least 1 char in A-Z
    o.valid?
    assert !o.errors[:acronym]
    o.acronym = "ABCDEFGHIJKLMNOP"  # up to 16 chars OK
    o.valid?
    assert !o.errors[:acronym]
  end

  def _acronym_validation_failed_with_error?(ont, error)
    ont.valid?
    errors = (ont.errors || {})[:acronym] || {}
    errors.keys.include?(error)
  end

  def test_ontology_properties
    submission_parse("BRO35", "BRO3.5",
                     "./test/data/ontology_files/BRO_v3.5.owl", 1,
                     process_rdf: true, index_search: false,
                     run_metrics: false, reasoning: false)
    ont = LinkedData::Models::Ontology.find('BRO35').first
    ont.bring(:submissions)
    sub = ont.submissions[0]
    props = ont.properties()
    assert_equal 86, props.length

    # verify sorting
    assert_equal "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#AlgorithmPurpose", props[0].id.to_s
    assert_equal "http://www.w3.org/2004/02/skos/core#altLabel", props[1].id.to_s

    props[2].bring(*[:domain,:range])
    props[2].bring(:unmapped)

    assert_equal "http://bioontology.org/ontologies/biositemap.owl#biositemap_author", props[2].id.to_s
    assert_equal "http://bioontology.org/ontologies/biositemap.owl#Resource_Description", props[2].domain
    assert_equal "http://www.w3.org/2001/XMLSchema#string", props[2].range
    refute_empty props[2].properties

    p = ont.property(props[2].id.to_s, display_all_attributes: true)
    assert_equal "http://bioontology.org/ontologies/biositemap.owl#biositemap_author", p.id.to_s
    assert_equal "http://bioontology.org/ontologies/biositemap.owl#Resource_Description", p.domain
    assert_equal "http://www.w3.org/2001/XMLSchema#string", p.range
    refute_empty p.properties

    datatype_props = []
    object_props = []
    annotation_props = []

    props.each do |prop|
      if prop.class == LinkedData::Models::DatatypeProperty
        datatype_props << prop
      elsif prop.class == LinkedData::Models::ObjectProperty
        object_props << prop
      elsif prop.class == LinkedData::Models::AnnotationProperty
        annotation_props << prop
      end
    end

    assert_equal props.length, datatype_props.length + object_props.length + annotation_props.length

    protein_type_prop = LinkedData::Models::DatatypeProperty.find(RDF::URI.new("http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#ProteinType")).in(sub).include(:label, :definition).first()
    assert_equal "ProteinType", protein_type_prop.label[0]
    assert_equal "broad classification of protein type based on structure or function", protein_type_prop.definition[0]

    measurement_type_prop = LinkedData::Models::ObjectProperty.find(RDF::URI.new("http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#MeasurementType")).in(sub).include(:label, :definition).first()
    assert_equal "MeasurementType", measurement_type_prop.label[0]
    assert_equal "what kind of information is being capture in this measurement?", measurement_type_prop.definition[0]

    broader_transitive_prop = LinkedData::Models::ObjectProperty.find(RDF::URI.new("http://www.w3.org/2004/02/skos/core#broaderTransitive")).in(sub).include(:parents).first()
    assert_equal 1, broader_transitive_prop.parents.length

    history_note_prop = LinkedData::Models::AnnotationProperty.find(RDF::URI.new("http://www.w3.org/2004/02/skos/core#historyNote")).in(sub).include(:label, :definition, :parents).first()
    assert_equal 1, history_note_prop.parents.length
    assert_equal "A note about the past state/use/meaning of a concept.", history_note_prop.definition[0]

    # test property roots
    pr = ont.property_roots(sub, extra_include=[:hasChildren, :children])
    assert_equal 65, pr.length

    # verify sorting
    assert_equal "http://bioontology.org/ontologies/BiomedicalResourceOntology.owl#AlgorithmPurpose", pr[0].id.to_s
    assert_equal "http://bioontology.org/ontologies/biositemap.owl#biositemap_author", pr[1].id.to_s

    # count object properties
    opr = pr.select { |p| p.class == LinkedData::Models::ObjectProperty }
    assert_equal 18, opr.length
    # count datatype properties
    dpr = pr.select { |p| p.class == LinkedData::Models::DatatypeProperty }
    assert_equal 33, dpr.length
    # count annotation properties
    apr = pr.select { |p| p.class == LinkedData::Models::AnnotationProperty }
    assert_equal 14, apr.length
    # check for non-root properties
    assert_empty pr.select { |p| ["http://www.w3.org/2004/02/skos/core#broaderTransitive",
                                  "http://www.w3.org/2004/02/skos/core#topConceptOf",
                                  "http://www.w3.org/2004/02/skos/core#relatedMatch",
                                  "http://www.w3.org/2004/02/skos/core#exactMatch",
                                  "http://www.w3.org/2004/02/skos/core#narrowMatch"].include?(p.id.to_s) },
                 "Non-root nodes found where roots are expected"

    # test property trees
    close_match_prop = LinkedData::Models::ObjectProperty.find(RDF::URI.new("http://www.w3.org/2004/02/skos/core#closeMatch")).in(sub).include(:parents).first()
    tree = close_match_prop.tree
    assert_equal "http://www.w3.org/2004/02/skos/core#semanticRelation", tree.id.to_s
    assert_equal 4, tree.children.length
    both_found = 0

    tree.children.each do |node|
      if node.id.to_s == "http://www.w3.org/2004/02/skos/core#broaderTransitive"
        both_found += 1
        assert node.hasChildren
        assert_empty node.children
      end

      if node.id.to_s == "http://www.w3.org/2004/02/skos/core#mappingRelation"
        both_found += 1
        assert node.hasChildren
        assert_equal 4, node.children.length
        has_source_child = node.children.select { |ch| ch.id.to_s == close_match_prop.id.to_s }
        assert has_source_child.length == 1
      end

      break if both_found == 2
    end

    assert_equal 2, both_found

    # test ancestors
    has_exact_match_prop = LinkedData::Models::ObjectProperty.find(RDF::URI.new("http://www.w3.org/2004/02/skos/core#exactMatch")).in(sub).first()
    ancestors = has_exact_match_prop.ancestors
    assert_equal 3, ancestors.length
    assert_equal ["http://www.w3.org/2004/02/skos/core#closeMatch",
                  "http://www.w3.org/2004/02/skos/core#mappingRelation",
                  "http://www.w3.org/2004/02/skos/core#semanticRelation"].sort, ancestors.map { |a| a.id.to_s }.sort


    # verify sorting
    assert_equal "http://www.w3.org/2004/02/skos/core#closeMatch", ancestors[0].id.to_s
    assert_equal "http://www.w3.org/2004/02/skos/core#mappingRelation", ancestors[1].id.to_s

    # test descendants
    lang_prop = LinkedData::Models::DatatypeProperty.find(RDF::URI.new("http://bioontology.org/ontologies/biositemap.owl#language")).in(sub).first()
    descendants = lang_prop.descendants
    assert_empty descendants

    sem_rel_prop = LinkedData::Models::ObjectProperty.find(RDF::URI.new("http://www.w3.org/2004/02/skos/core#semanticRelation")).in(sub).first()
    descendants = sem_rel_prop.descendants
    assert_equal 11, descendants.length
    assert_equal ["http://www.w3.org/2004/02/skos/core#broaderTransitive",
                  "http://www.w3.org/2004/02/skos/core#narrowerTransitive",
                  "http://www.w3.org/2004/02/skos/core#related",
                  "http://www.w3.org/2004/02/skos/core#mappingRelation",
                  "http://www.w3.org/2004/02/skos/core#broader",
                  "http://www.w3.org/2004/02/skos/core#narrower",
                  "http://www.w3.org/2004/02/skos/core#relatedMatch",
                  "http://www.w3.org/2004/02/skos/core#narrowMatch",
                  "http://www.w3.org/2004/02/skos/core#broadMatch",
                  "http://www.w3.org/2004/02/skos/core#closeMatch",
                  "http://www.w3.org/2004/02/skos/core#exactMatch"].sort, descendants.map { |d| d.id.to_s }.sort

    # verify sorting
    assert_equal "http://www.w3.org/2004/02/skos/core#broader", descendants[0].id.to_s
    assert_equal "http://www.w3.org/2004/02/skos/core#broadMatch", descendants[1].id.to_s
  end

  def test_valid_ontology
    o = LinkedData::Models::Ontology.new
    assert (not o.valid?)
    o.acronym = @acronym
    o.name = @name
    u = LinkedData::Models::User.new(username: "tim")
    o.administeredBy = [@user]
    assert o.valid?

    o.name = "This name has\u200Bhidden content"
    refute o.valid?

    o.name = "This ontology price is < than $1!"
    refute o.valid?

    o.name = "This ontology looks like 🌍"
    refute o.valid?

    o.name = "Ontology for the Comprehensive Integration of Multimodal Biomedical Research Data Covering Genomics, Proteomics, Transcriptomics, Metabolomics, Pharmacogenomics, and Clinical Trial Metadata in Global Health and Disease Surveillance Systems for Pandemic Preparedness and Precision Medicine Applications"
    refute o.valid?
  end

  def test_ontology_delete
    count, acronyms, ontologies = create_ontologies_and_submissions(ont_count: 2, submission_count: 1, process_submission: false)
    u, of, contact = ontology_objects()
    o1 = ontologies[0]
    o2 = ontologies[1]
    pc = LinkedData::Models::ProvisionalClass.new({label: "Test Provisional Class", creator: u, ontology: o1})
    pc.save
    n = LinkedData::Models::Note.new({
                                         creator: u,
                                         relatedOntology: [o1]
                                     })
    assert pc.valid?
    pc.save
    assert_equal true, pc.exist?

    assert n.valid?
    n.save()
    assert_equal true, n.exist?

    review_params = {
        :creator => u,
        :created => DateTime.now,
        :body => "This is a test review.",
        :ontologyReviewed => o1,
        :usabilityRating => 0,
        :coverageRating => 0,
        :qualityRating => 0,
        :formalityRating => 0,
        :correctnessRating => 0,
        :documentationRating => 0
    }

    r = LinkedData::Models::Review.new(review_params)
    r.save()
    assert_equal true, r.exist?

    o1.delete()
    assert_equal false, n.exist?
    assert_equal false, r.exist?
    assert_equal false, o1.exist?
    o2.delete()
  end

  def test_ontology_lifecycle
    o = LinkedData::Models::Ontology.new({
      acronym: @acronym,
      name: @name,
      administeredBy: [@user]
    })

    # Create
    assert_equal false, o.exist?(reload=true)
    o.save
    assert_equal true, o.exist?(reload=true)

    # Delete
    o.delete
    assert_equal false, o.exist?(reload=true)
  end

  def test_next_submission_id
    _create_ontology_with_submissions
    ss = LinkedData::Models::Ontology.find(@acronym).to_a[0]
    assert(ss.next_submission_id == 2)
  end

  def test_ontology_deletes_submissions
    _create_ontology_with_submissions
    ont = LinkedData::Models::Ontology.find(@acronym).first
    ont.delete
    submissions = LinkedData::Models::OntologySubmission.where(ontology: [acronym: @acronym])
    assert submissions.empty?
  end

  def test_latest_any_submission
    count, acronyms, ont = create_ontologies_and_submissions(ont_count: 1, submission_count: 3)
    ont = ont.first
    latest = ont.latest_submission(status: :any)
    assert_equal 3, latest.submissionId
  end

  def test_purl_creation
    return unless LinkedData.settings.enable_purl
    count, acronyms, ont = create_ontologies_and_submissions(ont_count: 3, submission_count: 1)
    purl_client = LinkedData::Purl::Client.new

    acronyms.each do |acronym|
      assert purl_client.purl_exists(acronym)
    end
  end

  def test_latest_parsed_submission
    count, acronyms, ont = create_ontologies_and_submissions(ont_count: 1, submission_count: 3)
    ont = ont.first
    ont.bring(submissions: [:submissionId])
    sub = ont.submissions.sort_by(&:id)[1]
    sub.bring(*LinkedData::Models::OntologySubmission.attributes)
    sub.set_ready
    sub.save
    latest = ont.latest_submission
    assert_equal 2, latest.submissionId
  end

  def test_submission_retrieval
    count, acronyms, ont = create_ontologies_and_submissions(ont_count: 1, submission_count: 3)
    middle_submission = ont.first.submission(2)
    assert_equal 2, middle_submission.submissionId
  end

  def test_all_submission_retrieval
    count, acronyms, ont = create_ontologies_and_submissions(ont_count: 1, submission_count: 3)
    ont = ont.first
    ont.bring(:submissions)
    all_submissions = ont.submissions
    assert_equal 3, all_submissions.length
  end

  def test_latest_submission_by_status
    _, acronyms, onts = create_ontologies_and_submissions(ont_count: 1, submission_count: 4)
    _add_statuses(onts.first, 1, %w[RDF METRICS])
    _add_statuses(onts.first, 2, %w[RDF])
    _add_statuses(onts.first, 3, %w[ERROR_RDF])

    ont = LinkedData::Models::Ontology.find(acronyms.first).first
    assert_equal 2, ont.latest_submission.submissionId
    assert_equal 2, ont.latest_submission(status: :rdf).submissionId
    assert_equal 2, ont.latest_submission(status: [:RDF]).submissionId
    assert_equal 1, ont.latest_submission(status: [:rdf, :metrics]).submissionId
    assert_equal 3, ont.latest_submission(status: :error_rdf).submissionId
    assert_equal 4, ont.latest_submission(status: :any).submissionId
    assert_nil ont.latest_submission(status: :indexed)

    # Found with pattern queries, without loading every submission of the ontology
    refute_includes ont.loaded_attributes, :submissions
  end

  def test_highest_submission_id
    o = LinkedData::Models::Ontology.new(acronym: @acronym, administeredBy: [@user], name: @name).save
    assert_equal 0, o.highest_submission_id(status: :any)
    assert_equal 0, o.highest_submission_id
    assert_equal 1, o.next_submission_id

    _, _, onts = create_ontologies_and_submissions(ont_count: 1, submission_count: 2)
    ont = onts.first
    assert_equal 2, ont.highest_submission_id(status: :any)
    assert_equal 3, ont.next_submission_id
    # Has submissions but none parsed: nil, not 0
    assert_nil ont.highest_submission_id
    _add_statuses(ont, 1, %w[RDF])
    assert_equal 1, ont.highest_submission_id
  end

  def test_submission_lookup_include
    _, acronyms, onts = create_ontologies_and_submissions(ont_count: 1, submission_count: 3)
    _add_statuses(onts.first, 3, %w[RDF])
    ont = LinkedData::Models::Ontology.find(acronyms.first).first

    latest = ont.latest_submission(status: :rdf, include: [ontology: [:acronym], hasOntologyLanguage: [:acronym]])
    assert_equal 3, latest.submissionId
    assert_equal acronyms.first, latest.ontology.acronym
    assert_equal "OWL", latest.hasOntologyLanguage.acronym
    assert_includes latest.loaded_attributes, :submissionStatus
    assert latest.ready?(status: :rdf)

    sub = ont.submission("2", include: :description)
    assert_equal 2, sub.submissionId
    assert_equal "Description 2", sub.description
    # Linked back to this ontology object, unmodified, also when include: asks for :ontology
    assert_same ont, sub.ontology
    refute_includes sub.modified_attributes, :ontology
    assert_same ont, latest.ontology
    refute_includes latest.modified_attributes, :ontology
    assert_nil ont.submission(99)
    assert_nil ont.submission("not-a-number")
  end

  def test_latest_submission_from_loaded_submissions
    _, acronyms, _ = create_ontologies_and_submissions(ont_count: 1, submission_count: 3)

    # The instance from the caller's list is returned, with the attributes they loaded
    ont = LinkedData::Models::Ontology.find(acronyms.first).include(submissions: [:submissionId, :description]).first
    latest = ont.latest_submission(status: :any)
    assert_same ont.submissions.find { |s| s.submissionId == 3 }, latest
    assert_equal "Description 3", latest.description
    assert_includes latest.loaded_attributes, :submissionStatus

    # Submissions loaded without attributes get their submissionIds filled in
    ont = LinkedData::Models::Ontology.find(acronyms.first).first
    ont.bring(:submissions)
    assert_equal 2, ont.submission(2).submissionId
    assert ont.submissions.all? { |s| s.loaded_attributes.include?(:submissionId) }
  end

  def test_loaded_submissions_bring_nested_include
    _, acronyms, _ = create_ontologies_and_submissions(ont_count: 1, submission_count: 2)

    # hasOntologyLanguage is loaded on the caller's list, but its acronym is not
    ont = LinkedData::Models::Ontology.find(acronyms.first)
                                      .include(submissions: [:submissionId, :hasOntologyLanguage]).first
    latest = ont.latest_submission(status: :any, include: [hasOntologyLanguage: [:acronym]])
    assert_same ont.submissions.find { |s| s.submissionId == 2 }, latest
    assert_equal "OWL", latest.hasOntologyLanguage.acronym
  end

  def test_loaded_submissions_bring_nested_list_include
    _, acronyms, onts = create_ontologies_and_submissions(ont_count: 1, submission_count: 1)
    _add_statuses(onts.first, 1, %w[RDF METRICS])

    # The statuses are loaded on the caller's list, but not their codes
    ont = LinkedData::Models::Ontology.find(acronyms.first)
                                      .include(submissions: [:submissionId, :submissionStatus]).first
    latest = ont.latest_submission(status: :any, include: [submissionStatus: [:code]])
    assert_operator latest.submissionStatus.length, :>=, 2
    assert latest.submissionStatus.all? { |s| s.loaded_attributes.include?(:code) }
    assert_includes latest.submissionStatus.map(&:code), "METRICS"
  end

  def test_loaded_submissions_fill_ids_by_iri
    _, acronyms, _ = create_ontologies_and_submissions(ont_count: 1, submission_count: 3)
    ont = LinkedData::Models::Ontology.find(acronyms.first).first
    ont.bring(:submissions)

    # Deleted after the list was loaded: it stays on the list, without an id
    deleted = LinkedData::Models::OntologySubmission.where(ontology: ont, submissionId: 1).first
    deleted.delete
    stale = ont.submissions.find { |s| s.id == deleted.id }

    assert_equal 3, ont.latest_submission(status: :any).submissionId
    assert_nil stale.submissionId
    assert_equal [2, 3], ont.submissions.reject { |s| s.equal?(stale) }.map(&:submissionId).sort
  end

  def test_highest_submission_id_sorts_numerically
    _, _, onts = create_ontologies_and_submissions(ont_count: 1, submission_count: 11,
                                                     submissions_to_process: [])
    ont = onts.first
    _add_statuses(ont, 9, %w[RDF])
    _add_statuses(ont, 10, %w[RDF])

    # As strings, "9" would sort above "10" and "11"
    assert_equal 11, ont.highest_submission_id(status: :any)
    assert_equal 10, ont.highest_submission_id(status: :rdf)
    assert_equal 12, ont.next_submission_id
  end

  # Saving a submission embeds its ontology in the metadata index
  def test_saved_submission_keeps_ontology_metadata_indexed
    _, acronyms, _ = create_ontologies_and_submissions(ont_count: 1, submission_count: 1)
    [nil, [ontology: [:acronym]]].each_with_index do |include, i|
      ont = LinkedData::Models::Ontology.find(acronyms.first).include(LinkedData::Models::Ontology.attributes).first
      ont.name = "Renamed ontology #{i}"
      ont.save

      sub = ont.latest_submission(status: :any, include: include).bring_remaining
      sub.description = "Saved after lookup #{i}"
      sub.save

      doc = LinkedData::Models::OntologySubmission.search('*:*', fq: "id:\"#{sub.id}\"")['response']['docs'].first
      assert_equal "Renamed ontology #{i}", doc['ontology_name_text'], "include: #{include.inspect}"
    end
  end

  def test_status_codes_for
    status = LinkedData::Models::SubmissionStatus
    assert_nil status.status_codes_for(:any)
    assert_nil status.status_codes_for([])
    assert_nil status.status_codes_for([:rdf, :any])
    assert_equal ["RDF"], status.status_codes_for(:ready)
    assert_equal ["RDF"], status.status_codes_for(:rdf)
    assert_equal ["RDF"], status.status_codes_for("RDF")
    assert_equal ["RDF", "METRICS"], status.status_codes_for([:rdf, :metrics])
  end

  def test_duplicate_contacts
    _create_ontology_with_submissions
    ont = LinkedData::Models::Ontology.find(@acronym).first
    ont.bring(submissions: [:contact])
    sub = ont.submissions.first
    assert sub.contact.length == 1
  end

  # A test to benchmark the time taken by bring_remaining (query not optimized, can take a long time if a lot of value in the list attributes)
  def test_ontology_bring_remaining
    # Creating the users
    user1 = LinkedData::Models::User.new(:username => "user1", :email => "some1@email.org" )
    user1.passwordHash = "some random pass hash"
    user1.save
    user2 = LinkedData::Models::User.new(:username => "user2", :email => "some2@email.org" )
    user2.passwordHash = "some random pass hash"
    user2.save
    user3 = LinkedData::Models::User.new(:username => "user3", :email => "some3@email.org" )
    user3.passwordHash = "some random pass hash"
    user3.save
    user4 = LinkedData::Models::User.new(:username => "user4", :email => "some4@email.org" )
    user4.passwordHash = "some random pass hash"
    user4.save
    user5 = LinkedData::Models::User.new(:username => "user5", :email => "some5@email.org" )
    user5.passwordHash = "some random pass hash"
    user5.save
    user6 = LinkedData::Models::User.new(:username => "user6", :email => "some6@email.org" )
    user6.passwordHash = "some random pass hash"
    user6.save
    user7 = LinkedData::Models::User.new(:username => "user7", :email => "some7@email.org" )
    user7.passwordHash = "some random pass hash"
    user7.save

    # Creating the categories
    category1 = LinkedData::Models::Category.new({:name => "Test Category", :description => "This is a test category", :acronym => "TCG"})
    category1.save
    category2 = LinkedData::Models::Category.new({:name => "Test2 Category", :description => "This is a test category", :acronym => "TCG2"})
    category2.save
    category3 = LinkedData::Models::Category.new({:name => "Test2 Category", :description => "This is a test category", :acronym => "TCG3"})
    category3.save
    category4 = LinkedData::Models::Category.new({:name => "Test2 Category", :description => "This is a test category", :acronym => "TCG4"})
    category4.save
    category5 = LinkedData::Models::Category.new({:name => "Test2 Category", :description => "This is a test category", :acronym => "TCG5"})
    category5.save
    category6 = LinkedData::Models::Category.new({:name => "Test2 Category", :description => "This is a test category", :acronym => "TCG6"})
    category6.save

    # Creating the groups
    group1 = LinkedData::Models::Group.new({:name => "Test1 Group", :description => "This is a test group", :acronym => "TESTG1"})
    group1.save
    group2 = LinkedData::Models::Group.new({:name => "Test2 Group", :description => "This is a test group", :acronym => "TESTG2"})
    group2.save
    o = LinkedData::Models::Ontology.new({
                                           acronym: "TEST1",
                                           administeredBy: [user1, user2, user3, user4, user5, user6, user7],
                                           name: "test 1",
                                           hasDomain: [category1, category2, category3, category4, category5, category6],
                                           group: [group1, group2]
                                         })
    o.save

    otest = LinkedData::Models::Ontology.find("TEST1").first

    Benchmark.bm do |x|
      x.report { otest.bring_remaining }
    end

    assert_equal "test 1", otest.name
  end

end
