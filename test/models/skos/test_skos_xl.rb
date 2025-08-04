require_relative '../test_ontology_common'
require 'logger'

class TestSkosXlLabel < LinkedData::TestOntologyCommon

  def self.before_suite
    LinkedData::TestCase.backend_4s_delete
    self.new('').submission_parse('INRAETHES', 'Testing skos',
                                  'test/data/ontology_files/thesaurusINRAE_nouv_structure.skos',
                                  1,
                                  process_rdf: true, index_search: false,
                                  run_metrics: false, reasoning: false)
  end

  def test_skos_xl_label_all
    ont = 'INRAETHES'
    sub = LinkedData::Models::Ontology.find(ont).first.latest_submission
    labels = LinkedData::Models::SKOS::Label.in(sub).include(:literalForm).all
    assert_equal 2, labels.size
    tests_labels = test_data
    labels.each do |label|
      test_label = tests_labels.select { |x| x[:id].eql?(label.id.to_s) }
      refute_nil test_label.first
      label_test(label, test_label.first)
    end
  end

  def test_class_skos_xl_label
    ont = 'INRAETHES'
    ont = LinkedData::Models::Ontology.find(ont).first
    sub = ont.latest_submission

    sub.bring_remaining
    sub.hasOntologyLanguage = LinkedData::Models::OntologyFormat.find('SKOS').first
    sub.save

    class_test = LinkedData::Models::Class.find('http://opendata.inrae.fr/thesaurusINRAE/c_16193')
                                          .in(sub).include(:prefLabel,
                                                           altLabelXl: [:literalForm],
                                                           prefLabelXl: [:literalForm],
                                                           hiddenLabelXl: [:literalForm]).first

    refute_nil class_test
    assert_equal 1, class_test.altLabelXl.size
    assert_equal 1, class_test.prefLabelXl.size
    assert_equal 1, class_test.hiddenLabelXl.size
    tests_labels = test_data

    label_test(class_test.altLabelXl.first, tests_labels[0])
    label_test(class_test.prefLabelXl.first, tests_labels[1])
    label_test(class_test.hiddenLabelXl.first, tests_labels[1])
  end

  private

  def test_data
    [
      { id: 'http://aims.fao.org/aos/agrovoc/xl_tr_1331561625299', literalForm: 'aktivite' },
      { id: 'http://aims.fao.org/aos/agrovoc/xl_en_668053a7', literalForm: 'air-water exchanges' }
    ]
  end

  def label_test(label, label_test)
    assert_equal label_test[:id], label.id.to_s
    assert_equal label_test[:literalForm], label.literalForm
  end
end