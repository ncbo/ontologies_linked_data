require_relative "../../test_case"

class TestNote < LinkedData::TestCase
  def self.before_suite
    self.new("before_suite").delete_ontologies_and_submissions
    @@ontology, @@cls = self.new("before_suite")._ontology_and_class
    @@note_user = "test_note_user"
    @@user = LinkedData::Models::User.new(
      username: @@note_user,
      email: "note_user@example.org",
      password: "note_user_pass"
    )
    @@user.save
  end

  def self.after_suite
    self.new("after_suite").delete_ontologies_and_submissions
    @@user.delete
  end

  def _ontology_and_class
    count, acronyms, ontologies = create_ontologies_and_submissions(ont_count: 1, submission_count: 1,
                                                                    process_submission: true,
                                                                    process_options: {process_rdf: true, extract_metadata: false})
    ontology = ontologies.first
    cls = LinkedData::Models::Class.where.include(:prefLabel).in(ontology.latest_submission).read_only.first
    return ontology, cls
  end

  def setup
    _variables
    _delete
    @note = LinkedData::Models::Note.new({
      creator: @@user,
      relatedOntology: [@@ontology]
    })
    assert @note.valid?
    @note.save
  end

  def teardown
    _delete
  end

  def _variables
    @noteId = "Note_UUID_TESTING1"
  end

  def _delete
    note = LinkedData::Models::Note.where(noteId: @noteId).first
    note.delete unless note.nil?
    user = LinkedData::Models::User.find(@@note_user).first
    user.delete unless user.nil?
  end

  def test_valid_note
    note = LinkedData::Models::Note.new
    assert (not note.valid?)

    note.creator = @@user
    note.relatedOntology = [@@ontology]
    assert note.valid?
  end

  def test_note_lifecycle
    begin
      n = LinkedData::Models::Note.new({
        creator: @@user,
        relatedOntology: [@@ontology],
      })

      assert_equal false, n.exist?
      n.save
      assert_equal true, n.exist?
      n.delete
      assert_equal false, n.exist?
    ensure
      n.delete if !n.nil? && n.persistent?
    end
  end

  def test_note_class_proposal
    begin
      proposal = LinkedData::Models::Notes::Proposal.new
      proposal.label = "New Label"
      proposal.classId = "http://example.org/new/id"
      proposal.type = LinkedData::Models::Notes::ProposalType.find("ProposalNewClass").first
      proposal.reasonForChange = "Need new term"
      proposal.save

      @note.proposal = proposal
      assert @note.valid?
    ensure
      proposal.delete if !proposal.nil? && proposal.persistent?
    end
  end

  def test_note_change_hierarchy_proposal
    begin
      proposal = LinkedData::Models::Notes::Proposal.new
      proposal.newTarget = "http://example.org/new/class"
      proposal.type = LinkedData::Models::Notes::ProposalType.find("ProposalChangeHierarchy").first
      proposal.reasonForChange = "Need new hierarchy"
      proposal.save

      @note.proposal = proposal
      assert @note.valid?
    ensure
      proposal.delete if !proposal.nil? && proposal.persistent?
    end
  end

  def test_note_change_property
    begin
      proposal = LinkedData::Models::Notes::Proposal.new
      proposal.propertyId = "http://example.org/property1"
      proposal.newValue = "My great value"
      proposal.type = LinkedData::Models::Notes::ProposalType.find("ProposalChangeProperty").first
      proposal.reasonForChange = "Need new property value"
      proposal.save

      @note.proposal = proposal
      assert @note.valid?
    ensure
      proposal.delete if !proposal.nil? && proposal.persistent?
    end
  end

  def test_note_related_resource_delete
    begin
      note = LinkedData::Models::Note.new({
        creator: @@user,
        relatedOntology: [@@ontology],
      })

      proposal = LinkedData::Models::Notes::Proposal.new
      proposal.propertyId = "http://example.org/property1"
      proposal.newValue = "My great value"
      proposal.type = LinkedData::Models::Notes::ProposalType.find("ProposalChangeProperty").first
      proposal.reasonForChange = "Need new property value"
      proposal.save

      note.proposal = proposal
      note.save

      proposal_id = proposal.id
      note.delete
      retrieved_proposal = LinkedData::Models::Notes::Proposal.find(proposal_id)
      assert_nil retrieved_proposal
    ensure
      proposal.delete if !proposal.nil? && proposal.persistent?
      note.delete if !note.nil? && note.persistent?
    end
  end

  def test_reply
    begin
      n = LinkedData::Models::Notes::Reply.new({
        creator: @@user,
        body: "This is my reply",
      })
      n.save

      @note.reply = [n]
      assert @note.valid?
    ensure
      n.delete if !n.nil? && n.persistent?
    end
  end


end
