require_relative '../test_ontology_common'
require 'logger'

class TestSchemes < LinkedData::TestOntologyCommon

  def self.before_suite
    LinkedData::TestCase.backend_4s_delete
    self.new('').submission_parse('INRAETHES', 'Testing skos',
                                  'test/data/ontology_files/thesaurusINRAE_nouv_structure.skos',
                                  1,
                                  process_rdf: true, extract_metadata: false,
                                  generate_missing_labels: false)
  end

  def test_schemes_all
    ont = 'INRAETHES'
    sub = LinkedData::Models::Ontology.find(ont).first.latest_submission
    schemes = LinkedData::Models::SKOS::Scheme.in(sub).include(:prefLabel).all

    assert_equal 66, schemes.size
    schemes_test = test_data
    schemes_test = schemes_test.sort_by { |x| x[:id] }
    schemes = schemes.sort_by { |x| x.id.to_s }

    schemes.each_with_index do |x, i|
      scheme_test = schemes_test[i]
      assert_equal scheme_test[:id], x.id.to_s
      assert_equal scheme_test[:prefLabel], x.prefLabel
    end
  end

  private

  def test_data
    [
      {
        "prefLabel": 'BIO neurosciences',
        "id": 'http://opendata.inrae.fr/thesaurusINRAE/mt_74',
        "type": 'http://www.w3.org/2004/02/skos/core#ConceptScheme'
      },
      {
        "prefLabel": 'INRAE domains',
        "id": 'http://opendata.inrae.fr/thesaurusINRAE/domainesINRAE',
        "type": 'http://www.w3.org/2004/02/skos/core#ConceptScheme'
      },
      {
        "prefLabel": 'EAR meteorology and climatology',
        "id": 'http://opendata.inrae.fr/thesaurusINRAE/mt_107',
        "type": 'http://www.w3.org/2004/02/skos/core#ConceptScheme'
      },
      {
        "prefLabel": 'HEA prevention and therapy',
        "id": 'http://opendata.inrae.fr/thesaurusINRAE/mt_77',
        "type": 'http://www.w3.org/2004/02/skos/core#ConceptScheme'
      },
      {
        "prefLabel": 'PHY materials sciences',
        "id": 'http://opendata.inrae.fr/thesaurusINRAE/mt_85',
        "type": 'http://www.w3.org/2004/02/skos/core#ConceptScheme'
      },
      {
        "prefLabel": 'BIO cell biology',
        "id": 'http://opendata.inrae.fr/thesaurusINRAE/mt_64',
        "type": 'http://www.w3.org/2004/02/skos/core#ConceptScheme'
      },
      {
        "prefLabel": 'SSH human geography',
        "id": 'http://opendata.inrae.fr/thesaurusINRAE/mt_20661',
        "type": 'http://www.w3.org/2004/02/skos/core#ConceptScheme'
      },
      {
        "prefLabel": 'BIO immunology',
        "id": 'http://opendata.inrae.fr/thesaurusINRAE/mt_75',
        "type": 'http://www.w3.org/2004/02/skos/core#ConceptScheme'
      },
      {
        "prefLabel": 'APP variables, parameters and data',
        "id": 'http://opendata.inrae.fr/thesaurusINRAE/mt_23256',
        "type": 'http://www.w3.org/2004/02/skos/core#ConceptScheme'
      },
      {
        "prefLabel": 'SSH information and communication',
        "id": 'http://opendata.inrae.fr/thesaurusINRAE/mt_20962',
        "type": 'http://www.w3.org/2004/02/skos/core#ConceptScheme'
      },
      {
        "prefLabel": 'BIO diet and nutrition',
        "id": 'http://opendata.inrae.fr/thesaurusINRAE/mt_23276',
        "type": 'http://www.w3.org/2004/02/skos/core#ConceptScheme'
      },
      {
        "prefLabel": 'SSH research and education',
        "id": 'http://opendata.inrae.fr/thesaurusINRAE/mt_20150',
        "type": 'http://www.w3.org/2004/02/skos/core#ConceptScheme'
      },
      {
        "prefLabel": 'CON processing technology and equipment',
        "id": 'http://opendata.inrae.fr/thesaurusINRAE/mt_54',
        "type": 'http://www.w3.org/2004/02/skos/core#ConceptScheme'
      },
      {
        "prefLabel": 'BIO molecular biology and biochemistry',
        "id": 'http://opendata.inrae.fr/thesaurusINRAE/mt_65',
        "type": 'http://www.w3.org/2004/02/skos/core#ConceptScheme'
      },
      {
        "prefLabel": 'EAR soil sciences',
        "id": 'http://opendata.inrae.fr/thesaurusINRAE/mt_105',
        "type": 'http://www.w3.org/2004/02/skos/core#ConceptScheme'
      },
      {
        "prefLabel": 'BIO toxicology and ecotoxicology',
        "id": 'http://opendata.inrae.fr/thesaurusINRAE/mt_68',
        "type": 'http://www.w3.org/2004/02/skos/core#ConceptScheme'
      },
      {
        "prefLabel": 'AGR farms and farming systems',
        "id": 'http://opendata.inrae.fr/thesaurusINRAE/mt_44',
        "type": 'http://www.w3.org/2004/02/skos/core#ConceptScheme'
      },
      {
        "prefLabel": 'AGR plant cultural practices and experimentations',
        "id": 'http://opendata.inrae.fr/thesaurusINRAE/mt_47',
        "type": 'http://www.w3.org/2004/02/skos/core#ConceptScheme'
      },
      {
        "prefLabel": 'CHE chemical and physicochemical analysis',
        "id": 'http://opendata.inrae.fr/thesaurusINRAE/mt_23260',
        "type": 'http://www.w3.org/2004/02/skos/core#ConceptScheme'
      },
      {
        "prefLabel": 'CON quality of processed products',
        "id": 'http://opendata.inrae.fr/thesaurusINRAE/mt_55',
        "type": 'http://www.w3.org/2004/02/skos/core#ConceptScheme'
      },
      {
        "prefLabel": 'EAR geology and geomorphology',
        "id": 'http://opendata.inrae.fr/thesaurusINRAE/mt_104',
        "type": 'http://www.w3.org/2004/02/skos/core#ConceptScheme'
      },
      {
        "prefLabel": 'APP research methods',
        "id": 'http://opendata.inrae.fr/thesaurusINRAE/mt_98',
        "type": 'http://www.w3.org/2004/02/skos/core#ConceptScheme'
      },
      {
        "prefLabel": 'SSH laws and standards',
        "id": 'http://opendata.inrae.fr/thesaurusINRAE/mt_21670',
        "type": 'http://www.w3.org/2004/02/skos/core#ConceptScheme'
      },
      {
        "prefLabel": 'BIO general biology',
        "id": 'http://opendata.inrae.fr/thesaurusINRAE/mt_26224',
        "type": 'http://www.w3.org/2004/02/skos/core#ConceptScheme'
      },
      {
        "prefLabel": 'BIO ethology',
        "id": 'http://opendata.inrae.fr/thesaurusINRAE/mt_69',
        "type": 'http://www.w3.org/2004/02/skos/core#ConceptScheme'
      },
      {
        "prefLabel": 'PHY energy and thermodynamics',
        "id": 'http://opendata.inrae.fr/thesaurusINRAE/mt_86',
        "type": 'http://www.w3.org/2004/02/skos/core#ConceptScheme'
      },
      {
        "prefLabel": 'PHY mechanics and robotics',
        "id": 'http://opendata.inrae.fr/thesaurusINRAE/mt_88',
        "type": 'http://www.w3.org/2004/02/skos/core#ConceptScheme'
      },
      {
        "prefLabel": 'HEA health and welfare',
        "id": 'http://opendata.inrae.fr/thesaurusINRAE/mt_78',
        "type": 'http://www.w3.org/2004/02/skos/core#ConceptScheme'
      },
      {
        "prefLabel": 'ENV environment and natural resources',
        "id": 'http://opendata.inrae.fr/thesaurusINRAE/mt_14',
        "type": 'http://www.w3.org/2004/02/skos/core#ConceptScheme'
      },
      {
        "prefLabel": 'PHY civil engineering',
        "id": 'http://opendata.inrae.fr/thesaurusINRAE/mt_89',
        "type": 'http://www.w3.org/2004/02/skos/core#ConceptScheme'
      },
      {
        "prefLabel": 'HEA diseases, disorders and symptoms',
        "id": 'http://opendata.inrae.fr/thesaurusINRAE/mt_76',
        "type": 'http://www.w3.org/2004/02/skos/core#ConceptScheme'
      },
      {
        "prefLabel": 'HEA disease vectors',
        "id": 'http://opendata.inrae.fr/thesaurusINRAE/mt_79',
        "type": 'http://www.w3.org/2004/02/skos/core#ConceptScheme'
      },
      {
        "prefLabel": 'ENV natural and technological hazards',
        "id": 'http://opendata.inrae.fr/thesaurusINRAE/mt_17',
        "type": 'http://www.w3.org/2004/02/skos/core#ConceptScheme'
      },
      {
        "prefLabel": 'CHE chemical compounds and elements',
        "id": 'http://opendata.inrae.fr/thesaurusINRAE/mt_100',
        "type": 'http://www.w3.org/2004/02/skos/core#ConceptScheme'
      },
      {
        "prefLabel": 'ENV waste',
        "id": 'http://opendata.inrae.fr/thesaurusINRAE/mt_15',
        "type": 'http://www.w3.org/2004/02/skos/core#ConceptScheme'
      },
      {
        "prefLabel": 'CON supply chain management',
        "id": 'http://opendata.inrae.fr/thesaurusINRAE/mt_56',
        "type": 'http://www.w3.org/2004/02/skos/core#ConceptScheme'
      },
      {
        "prefLabel": 'AGR animal husbandry and breeding',
        "id": 'http://opendata.inrae.fr/thesaurusINRAE/mt_48',
        "type": 'http://www.w3.org/2004/02/skos/core#ConceptScheme'
      },
      {
        "prefLabel": 'ENV water management',
        "id": 'http://opendata.inrae.fr/thesaurusINRAE/mt_18',
        "type": 'http://www.w3.org/2004/02/skos/core#ConceptScheme'
      },
      {
        "prefLabel": 'AGR agricultural products',
        "id": 'http://opendata.inrae.fr/thesaurusINRAE/mt_46',
        "type": 'http://www.w3.org/2004/02/skos/core#ConceptScheme'
      },
      {
        "prefLabel": 'MAT computer sciences and artificial intelligence',
        "id": 'http://opendata.inrae.fr/thesaurusINRAE/mt_91',
        "type": 'http://www.w3.org/2004/02/skos/core#ConceptScheme'
      },
      {
        "prefLabel": 'AGR agricultural machinery and equipment',
        "id": 'http://opendata.inrae.fr/thesaurusINRAE/mt_49',
        "type": 'http://www.w3.org/2004/02/skos/core#ConceptScheme'
      },
      {
        "prefLabel": 'BIO microbiology',
        "id": 'http://opendata.inrae.fr/thesaurusINRAE/mt_71',
        "type": 'http://www.w3.org/2004/02/skos/core#ConceptScheme'
      },
      {
        "prefLabel": 'ENV pollution',
        "id": 'http://opendata.inrae.fr/thesaurusINRAE/mt_16',
        "type": 'http://www.w3.org/2004/02/skos/core#ConceptScheme'
      },
      {
        "prefLabel": 'BIO physiology',
        "id": 'http://opendata.inrae.fr/thesaurusINRAE/mt_72',
        "type": 'http://www.w3.org/2004/02/skos/core#ConceptScheme'
      },
      {
        "prefLabel": 'SSH culture and humanities',
        "id": 'http://opendata.inrae.fr/thesaurusINRAE/mt_26297',
        "type": 'http://www.w3.org/2004/02/skos/core#ConceptScheme'
      },
      {
        "prefLabel": 'MAT mathematics and statistics',
        "id": 'http://opendata.inrae.fr/thesaurusINRAE/mt_90',
        "type": 'http://www.w3.org/2004/02/skos/core#ConceptScheme'
      },
      {
        "prefLabel": nil,
        "id": 'http://opendata.inrae.fr/thesaurusINRAE/thesaurusINRAE',
        "type": 'http://www.w3.org/2004/02/skos/core#ConceptScheme'
      },
      {
        "prefLabel": 'SSH politics and administration',
        "id": 'http://opendata.inrae.fr/thesaurusINRAE/mt_22445',
        "type": 'http://www.w3.org/2004/02/skos/core#ConceptScheme'
      },
      {
        "prefLabel": 'EAR hydrology',
        "id": 'http://opendata.inrae.fr/thesaurusINRAE/mt_106',
        "type": 'http://www.w3.org/2004/02/skos/core#ConceptScheme'
      },
      {
        "prefLabel": 'AGR agricultural management',
        "id": 'http://opendata.inrae.fr/thesaurusINRAE/mt_26298',
        "type": 'http://www.w3.org/2004/02/skos/core#ConceptScheme'
      },
      {
        "prefLabel": 'SSH management sciences',
        "id": 'http://opendata.inrae.fr/thesaurusINRAE/mt_21074',
        "type": 'http://www.w3.org/2004/02/skos/core#ConceptScheme'
      },
      {
        "prefLabel": 'SSH economics',
        "id": 'http://opendata.inrae.fr/thesaurusINRAE/mt_20544',
        "type": 'http://www.w3.org/2004/02/skos/core#ConceptScheme'
      },
      {
        "prefLabel": 'BIO anatomy and body fluids',
        "id": 'http://opendata.inrae.fr/thesaurusINRAE/mt_63',
        "type": 'http://www.w3.org/2004/02/skos/core#ConceptScheme'
      },
      {
        "prefLabel": 'ORG taxonomic classification of organisms',
        "id": 'http://opendata.inrae.fr/thesaurusINRAE/mt_26190',
        "type": 'http://www.w3.org/2004/02/skos/core#ConceptScheme'
      },
      {
        "prefLabel": 'CHE chemical reactions and physicochemical phenomena',
        "id": 'http://opendata.inrae.fr/thesaurusINRAE/mt_102',
        "type": 'http://www.w3.org/2004/02/skos/core#ConceptScheme'
      },
      {
        "prefLabel": 'AGR hunting and fishing',
        "id": 'http://opendata.inrae.fr/thesaurusINRAE/mt_50',
        "type": 'http://www.w3.org/2004/02/skos/core#ConceptScheme'
      },
      {
        "prefLabel": 'CON processed biobased products',
        "id": 'http://opendata.inrae.fr/thesaurusINRAE/mt_53',
        "type": 'http://www.w3.org/2004/02/skos/core#ConceptScheme'
      },
      {
        "prefLabel": 'BIO genetics',
        "id": 'http://opendata.inrae.fr/thesaurusINRAE/mt_70',
        "type": 'http://www.w3.org/2004/02/skos/core#ConceptScheme'
      },
      {
        "prefLabel": 'ORG organisms related notions',
        "id": 'http://opendata.inrae.fr/thesaurusINRAE/mt_26191',
        "type": 'http://www.w3.org/2004/02/skos/core#ConceptScheme'
      },
      {
        "prefLabel": 'SSH sociology and psychology',
        "id": 'http://opendata.inrae.fr/thesaurusINRAE/mt_20262',
        "type": 'http://www.w3.org/2004/02/skos/core#ConceptScheme'
      },
      {
        "prefLabel": 'APP research equipment',
        "id": 'http://opendata.inrae.fr/thesaurusINRAE/mt_97',
        "type": 'http://www.w3.org/2004/02/skos/core#ConceptScheme'
      },
      {
        "prefLabel": 'CHE chemical and physicochemical properties',
        "id": 'http://opendata.inrae.fr/thesaurusINRAE/mt_101',
        "type": 'http://www.w3.org/2004/02/skos/core#ConceptScheme'
      },
      {
        "prefLabel": 'BIO ecology',
        "id": 'http://opendata.inrae.fr/thesaurusINRAE/mt_67',
        "type": 'http://www.w3.org/2004/02/skos/core#ConceptScheme'
      },
      {
        "prefLabel": 'PHY physical properties of matter',
        "id": 'http://opendata.inrae.fr/thesaurusINRAE/mt_84',
        "type": 'http://www.w3.org/2004/02/skos/core#ConceptScheme'
      },
      {
        "prefLabel": 'EAR physical geography',
        "id": 'http://opendata.inrae.fr/thesaurusINRAE/mt_103',
        "type": 'http://www.w3.org/2004/02/skos/core#ConceptScheme'
      },
      {
        "prefLabel": 'PHY hydraulics and aeraulics',
        "id": 'http://opendata.inrae.fr/thesaurusINRAE/mt_87',
        "type": 'http://www.w3.org/2004/02/skos/core#ConceptScheme'
      }
    ]
  end
end
