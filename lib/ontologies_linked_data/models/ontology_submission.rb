require 'net/ftp'
require 'net/http'
require 'uri'
require 'open-uri'
require 'cgi'
require 'benchmark'
require 'csv'
require 'fileutils'

require 'ontologies_linked_data/models/skos/skos_submission_schemes'
require 'ontologies_linked_data/models/skos/skos_submission_roots'

module LinkedData
  module Models

    class OntologySubmission < LinkedData::Models::Base

      include LinkedData::Concerns::OntologySubmission::MetadataExtractor

      include SKOS::ConceptSchemes
      include SKOS::RootsFetcher

      FILES_TO_DELETE = ['labels.ttl', 'mappings.ttl', 'obsolete.ttl', 'owlapi.xrdf', 'errors.log']
      FLAT_ROOTS_LIMIT = 1000

      model :ontology_submission, name_with: lambda { |s| submission_id_generator(s) }
      attribute :submissionId, enforce: [:integer, :existence]

      # Configurable properties for processing
      attribute :prefLabelProperty, enforce: [:uri]
      attribute :definitionProperty, enforce: [:uri]
      attribute :synonymProperty, enforce: [:uri]
      attribute :authorProperty, enforce: [:uri]
      attribute :classType, enforce: [:uri]
      attribute :hierarchyProperty, enforce: [:uri]
      attribute :obsoleteProperty, enforce: [:uri]
      attribute :obsoleteParent, enforce: [:uri]

      # Ontology metadata
      attribute :hasOntologyLanguage, namespace: :omv, enforce: [:existence, :ontology_format]

      attribute :homepage, namespace: :foaf, extractedMetadata: true, metadataMappings: ["cc:attributionURL", "mod:homepage", "doap:blog", "schema:mainEntityOfPage"],
                helpText: "The URL of the homepage for the ontology."

      # TODO: change default attribute name
      attribute :publication, extractedMetadata: true, helpText: "The URL of bibliographic reference for the ontology.",
                metadataMappings: ["omv:reference", "dct:bibliographicCitation", "foaf:isPrimaryTopicOf", "schema:citation", "cito:citesAsAuthority", "schema:citation"] # TODO: change default attribute name

      # attention, attribute particulier. Je le récupère proprement via OWLAPI
      # TODO: careful in bioportal_web_ui (submissions_helper.rb) @submission.send("URI") causes a bug! Didn't get why
      attribute :URI, namespace: :omv, extractedMetadata: true, label: "URI", helpText: "The URI of the ontology which is described by this metadata."

      attribute :naturalLanguage, namespace: :omv, enforce: [:list], extractedMetadata: true,
                metadataMappings: ["dc:language", "dct:language", "doap:language", "schema:inLanguage"],
                helpText: "The language of the content of the ontology.&lt;br&gt;Consider using a &lt;a target=&quot;_blank&quot; href=&quot;http://www.lexvo.org/&quot;&gt;Lexvo URI&lt;/a&gt; with ISO639-3 code.&lt;br&gt;e.g.: http://lexvo.org/id/iso639-3/eng",
                enforcedValues: {
                  "http://lexvo.org/id/iso639-3/eng" => "English",
                  "http://lexvo.org/id/iso639-3/fra" => "French",
                  "http://lexvo.org/id/iso639-3/spa" => "Spanish",
                  "http://lexvo.org/id/iso639-3/por" => "Portuguese",
                  "http://lexvo.org/id/iso639-3/ita" => "Italian",
                  "http://lexvo.org/id/iso639-3/deu" => "German"
                }

      attribute :documentation, namespace: :omv, extractedMetadata: true,
                metadataMappings: ["rdfs:seeAlso", "foaf:page", "vann:usageNote", "mod:document", "dcat:landingPage", "doap:wiki"],
                helpText: "URL for further documentation."

      attribute :version, namespace: :omv, extractedMetadata: true, helpText: "The version of the released ontology",
                metadataMappings: ["owl:versionInfo", "mod:version", "doap:release", "pav:version", "schema:version", "oboInOwl:data-version", "oboInOwl:version", "adms:last"]

      attribute :description, namespace: :omv, enforce: [:concatenate], extractedMetadata: true, helpText: "Free text description of the ontology.",
                metadataMappings: ["dc:description", "dct:description", "doap:description", "schema:description", "oboInOwl:remark"]

      attribute :status, namespace: :omv, extractedMetadata: true, metadataMappings: ["adms:status", "idot:state"],
                helpText: "Information about the ontology status (alpha, beta, production, retired)."
      # Pas de limitation ici, mais seulement 4 possibilité dans l'UI (alpha, beta, production, retired)

      attribute :contact, enforce: [:existence, :contact, :list], # Careful its special
                helpText: "The people to contact when questions about the ontology. Composed of the contacts name and email."

      attribute :creationDate, namespace: :omv, enforce: [:date_time], metadataMappings: ["dct:dateSubmitted", "schema:datePublished"],
                default: lambda { |record| DateTime.now } # Attention c'est généré automatiquement, quand la submission est créée
      attribute :released, enforce: [:date_time, :existence], extractedMetadata: true, label: "Release date", helpText: "Date of the ontology release.",
                metadataMappings: ["omv:creationDate", "dc:date", "dct:date", "dct:issued", "mod:creationDate", "doap:created", "schema:dateCreated",
                                   "prov:generatedAtTime", "pav:createdOn", "pav:authoredOn", "pav:contributedOn", "oboInOwl:date", "oboInOwl:hasDate"]
      # date de release de l'ontologie par ses développeurs

      # Metrics metadata
      # LES metrics sont auto calculés par BioPortal (utilisant OWLAPI)
      attribute :numberOfClasses, namespace: :omv, enforce: [:integer], metadataMappings: ["void:classes", "voaf:classNumber", "mod:noOfClasses"], display: "metrics",
                helpText: "Number of classes in this ontology. Automatically computed by OWLAPI."
      attribute :numberOfIndividuals, namespace: :omv, enforce: [:integer], metadataMappings: ["mod:noOfIndividuals"], display: "metrics",
                helpText: "Number of individuals in this ontology. Automatically computed by OWLAPI."
      attribute :numberOfProperties, namespace: :omv, enforce: [:integer], metadataMappings: ["void:properties", "voaf:propertyNumber", "mod:noOfProperties"], display: "metrics",
                helpText: "Number of properties in this ontology. Automatically computed by OWLAPI."
      attribute :maxDepth, enforce: [:integer]
      attribute :maxChildCount, enforce: [:integer]
      attribute :averageChildCount, enforce: [:integer]
      attribute :classesWithOneChild, enforce: [:integer]
      attribute :classesWithMoreThan25Children, enforce: [:integer]
      attribute :classesWithNoDefinition, enforce: [:integer]

      # Complementary omv metadata
      attribute :modificationDate, namespace: :omv, enforce: [:date_time], extractedMetadata: true,
                metadataMappings: ["dct:modified", "schema:dateModified", "pav:lastUpdateOn", "mod:updated"], helpText: "Date of the last modification made to the ontology"

      attribute :entities, namespace: :void, enforce: [:integer], extractedMetadata: true, label: "Number of entities", display: "metrics",
                helpText: "Number of entities in this ontology."

      attribute :numberOfAxioms, namespace: :omv, enforce: [:integer], extractedMetadata: true, metadataMappings: ["mod:noOfAxioms", "void:triples"],
                display: "metrics", helpText: "Number of axioms in this ontology."

      attribute :keyClasses, namespace: :omv, enforce: [:concatenate], extractedMetadata: true, display: "content",
                metadataMappings: ["foaf:primaryTopic", "void:exampleResource", "schema:mainEntity"], helptext: "Representative classes in the ontology."

      attribute :keywords, namespace: :omv, enforce: [:concatenate], extractedMetadata: true, helpText: "List of keywords related to the ontology.",
                metadataMappings: ["mod:keyword", "dcat:keyword", "schema:keywords"] # Attention particulier, ça peut être un simple string avec des virgules

      attribute :knownUsage, namespace: :omv, enforce: [:concatenate, :textarea], extractedMetadata: true, display: "usage",
                helpText: "The applications where the ontology is being used."

      attribute :notes, namespace: :omv, enforce: [:concatenate, :textarea], extractedMetadata: true, metadataMappings: ["rdfs:comment", "adms:versionNotes"],
                helpText: "Additional information about the ontology that is not included somewhere else (e.g. information that you do not want to include in the documentation)."

      attribute :conformsToKnowledgeRepresentationParadigm, namespace: :omv, extractedMetadata: true,
                metadataMappings: ["mod:KnowledgeRepresentationFormalism", "dct:conformsTo"], display: "methodology",
                helptext: "A representation formalism that is followed to describe knowledge in an ontology. Example includes description logics, first order logic, etc."

      attribute :hasContributor, namespace: :omv, enforce: [:concatenate], extractedMetadata: true, label: "Contributors",
                metadataMappings: ["dc:contributor", "dct:contributor", "doap:helper", "schema:contributor", "pav:contributedBy"],
                helpText: "Contributors to the creation of the ontology."

      attribute :hasCreator, namespace: :omv, enforce: [:concatenate], extractedMetadata: true, label: "Creators",
                metadataMappings: ["dc:creator", "dct:creator", "foaf:maker", "prov:wasAttributedTo", "doap:maintainer", "pav:authoredBy", "pav:createdBy", "schema:author", "schema:creator"],
                helpText: "Main responsible for the creation of the ontology."

      attribute :designedForOntologyTask, namespace: :omv, enforce: [:list], extractedMetadata: true, display: "usage",
                helpText: "The purpose for which the ontology was originally designed.", enforcedValues: {
          "http://omv.ontoware.org/2005/05/ontology#AnnotationTask" => "Annotation Task",
          "http://omv.ontoware.org/2005/05/ontology#ConfigurationTask" => "Configuration Task",
          "http://omv.ontoware.org/2005/05/ontology#FilteringTask" => "Filtering Task",
          "http://omv.ontoware.org/2005/05/ontology#IndexingTask" => "Indexing Task",
          "http://omv.ontoware.org/2005/05/ontology#IntegrationTask" => "Integration Task",
          "http://omv.ontoware.org/2005/05/ontology#MatchingTask" => "Matching Task",
          "http://omv.ontoware.org/2005/05/ontology#MediationTask" => "Mediation Task",
          "http://omv.ontoware.org/2005/05/ontology#PersonalizationTask" => "Personalization Task",
          "http://omv.ontoware.org/2005/05/ontology#QueryFormulationTask" => "Query Formulation Task",
          "http://omv.ontoware.org/2005/05/ontology#QueryRewritingTask" => "Query Rewriting Task",
          "http://omv.ontoware.org/2005/05/ontology#SearchTask" => "Search Task"
        }

      attribute :wasGeneratedBy, namespace: :prov, enforce: [:concatenate], extractedMetadata: true, display: "people",
                helpText: "People who generated the ontology."

      attribute :wasInvalidatedBy, namespace: :prov, enforce: [:concatenate], extractedMetadata: true, display: "people",
                helpText: "People who invalidated the ontology."

      attribute :curatedBy, namespace: :pav, enforce: [:concatenate], extractedMetadata: true, display: "people",
                metadataMappings: ["mod:evaluatedBy"], helpText: "People who curated the ontology."

      attribute :endorsedBy, namespace: :omv, enforce: [:list], extractedMetadata: true, metadataMappings: ["mod:endorsedBy"],
                helpText: "The parties that have expressed support or approval to this ontology", display: "people"

      attribute :fundedBy, namespace: :foaf, extractedMetadata: true, metadataMappings: ["mod:sponsoredBy", "schema:sourceOrganization"], display: "people",
                helpText: "The organization funding the ontology development."

      attribute :translator, namespace: :schema, extractedMetadata: true, metadataMappings: ["doap:translator"], display: "people",
                helpText: "Organization or person who adapted the ontology to different languages, regional differences and technical requirements"

      attribute :hasDomain, namespace: :omv, enforce: [:concatenate], extractedMetadata: true,
                helpText: "Typically, the domain can refer to established topic hierarchies such as the general purpose topic hierarchy DMOZ or the domain specific topic hierarchy ACM for the computer science domain",
                metadataMappings: ["dc:subject", "dct:subject", "foaf:topic", "dcat:theme", "schema:about"], display: "usage"

      attribute :hasFormalityLevel, namespace: :omv, extractedMetadata: true, metadataMappings: ["mod:ontologyFormalityLevel"],
                helpText: "Level of formality of the ontology.", enforcedValues: {
          "http://w3id.org/nkos/nkostype#classification_schema" => "Classification scheme",
          "http://w3id.org/nkos/nkostype#dictionary" => "Dictionary",
          "http://w3id.org/nkos/nkostype#gazetteer" => "Gazetteer",
          "http://w3id.org/nkos/nkostype#glossary" => "Glossary",
          "http://w3id.org/nkos/nkostype#list" => "List",
          "http://w3id.org/nkos/nkostype#name_authority_list" => "Name authority list",
          "http://w3id.org/nkos/nkostype#ontology" => "Ontology",
          "http://w3id.org/nkos/nkostype#semantic_network" => "Semantic network",
          "http://w3id.org/nkos/nkostype#subject_heading_scheme" => "Subject heading scheme",
          "http://w3id.org/nkos/nkostype#synonym_ring" => "Synonym ring",
          "http://w3id.org/nkos/nkostype#taxonomy" => "Taxonomy",
          "http://w3id.org/nkos/nkostype#terminology" => "Terminology",
          "http://w3id.org/nkos/nkostype#thesaurus" => "Thesaurus"
        }

      attribute :hasLicense, namespace: :omv, extractedMetadata: true,
                metadataMappings: ["dc:rights", "dct:rights", "dct:license", "cc:license", "schema:license"],
                helpText: "Underlying license model.&lt;br&gt;Consider using a &lt;a target=&quot;_blank&quot; href=&quot;http://rdflicense.appspot.com/&quot;&gt;URI to describe your License&lt;/a&gt;&lt;br&gt;Consider using a &lt;a target=&quot;_blank&quot; href=&quot;http://licentia.inria.fr/&quot;&gt;INRIA licentia&lt;/a&gt; to choose your license",
                enforcedValues: {
                  "https://creativecommons.org/licenses/by/4.0/" => "CC Attribution 4.0 International",
                  "https://creativecommons.org/licenses/by/3.0/" => "CC Attribution 3.0",
                  "https://creativecommons.org/publicdomain/zero/1.0/" => "CC Public Domain Dedication",
                  "http://www.gnu.org/licenses/gpl-3.0" => "GNU General Public License 3.0",
                  "http://www.gnu.org/licenses/gpl-2.0" => "GNU General Public License 2.0",
                  "https://opensource.org/licenses/Artistic-2.0" => "Open Source Artistic license 2.0",
                  "https://opensource.org/licenses/MIT" => "MIT License",
                  "https://opensource.org/licenses/BSD-3-Clause" => "BSD 3-Clause License",
                  "http://www.apache.org/licenses/LICENSE-2.0" => "Apache License 2.0"
                }

      attribute :hasOntologySyntax, namespace: :omv, extractedMetadata: true, metadataMappings: ["mod:syntax", "dc:format", "dct:format"], label: "Ontology Syntax",
                helpText: "The presentation syntax for the ontology langage.&lt;br&gt;Properties taken from &lt;a target=&quot;_blank&quot; href=&quot;https://www.w3.org/ns/formats/&quot;&gt;W3C URIs for file format&lt;/a&gt;",
                enforcedValues: {
                  "http://www.w3.org/ns/formats/JSON-LD" => "JSON-LD",
                  "http://www.w3.org/ns/formats/N3" => "N3",
                  "http://www.w3.org/ns/formats/N-Quads" => "N-Quads",
                  "http://www.w3.org/ns/formats/LD_Patch" => "LD Patch",
                  "http://www.w3.org/ns/formats/microdata" => "Microdata",
                  "http://www.w3.org/ns/formats/OWL_XML" => "OWL XML Serialization",
                  "http://www.w3.org/ns/formats/OWL_Functional" => "OWL Functional Syntax",
                  "http://www.w3.org/ns/formats/OWL_Manchester" => "OWL Manchester Syntax",
                  "http://www.w3.org/ns/formats/POWDER" => "POWDER",
                  "http://www.w3.org/ns/formats/POWDER-S" => "POWDER-S",
                  "http://www.w3.org/ns/formats/PROV-N" => "PROV-N",
                  "http://www.w3.org/ns/formats/PROV-XML" => "PROV-XML",
                  "http://www.w3.org/ns/formats/RDFa" => "RDFa",
                  "http://www.w3.org/ns/formats/RDF_JSON" => "RDF/JSON",
                  "http://www.w3.org/ns/formats/RDF_XML" => "RDF/XML",
                  "http://www.w3.org/ns/formats/RIF_XML" => "RIF XML Syntax",
                  "http://www.w3.org/ns/formats/Turtle" => "Turtle",
                  "http://www.w3.org/ns/formats/TriG" => "TriG",
                  "http://purl.obolibrary.org/obo/oboformat/spec.html" => "OBO"
                }

      attribute :isOfType, namespace: :omv, extractedMetadata: true, metadataMappings: ["dc:type", "dct:type"],
                helpText: "The nature of the content of the ontology.&lt;br&gt;Properties taken from &lt;a target=&quot;_blank&quot; href=&quot;http://wiki.dublincore.org/index.php/NKOS_Vocabularies#KOS_Types_Vocabulary&quot;&gt;DCMI KOS type vocabularies&lt;/a&gt;",
                enforcedValues: {
                  "http://omv.ontoware.org/2005/05/ontology#ApplicationOntology" => "Application Ontology",
                  "http://omv.ontoware.org/2005/05/ontology#CoreOntology" => "Core Ontology",
                  "http://omv.ontoware.org/2005/05/ontology#DomainOntology" => "Domain Ontology",
                  "http://omv.ontoware.org/2005/05/ontology#TaskOntology" => "Task Ontology",
                  "http://omv.ontoware.org/2005/05/ontology#UpperLevelOntology" => "Upper Level Ontology",
                  "http://omv.ontoware.org/2005/05/ontology#Vocabulary" => "Vocabulary"
                }

      attribute :usedOntologyEngineeringMethodology, namespace: :omv, enforce: [:concatenate], extractedMetadata: true,
                metadataMappings: ["mod:methodologyUsed", "adms:representationTechnique", "schema:publishingPrinciples"], display: "methodology",
                helpText: "Information about the method model used to create the ontology"

      attribute :usedOntologyEngineeringTool, namespace: :omv, extractedMetadata: true,
                metadataMappings: ["mod:toolUsed", "pav:createdWith", "oboInOwl:auto-generated-by"],
                helpText: "Information about the tool used to create the ontology", enforcedValues: {
          "http://protege.stanford.edu" => "Protégé",
          "OWL API" => "OWL API",
          "http://oboedit.org/" => "OBO-Edit",
          "SWOOP" => "SWOOP",
          "OntoStudio" => "OntoStudio",
          "Altova" => "Altova",
          "SemanticWorks" => "SemanticWorks",
          "OilEd" => "OilEd",
          "IsaViz" => "IsaViz",
          "WebODE" => "WebODE",
          "OntoBuilder" => "OntoBuilder",
          "WSMO Studio" => "WSMO Studio",
          "VocBench" => "VocBench",
          "TopBraid" => "TopBraid",
          "NeOn-Toolkit" => "NeOn-Toolkit"
        }

      attribute :useImports, namespace: :omv, enforce: [:list, :uri], extractedMetadata: true,
                metadataMappings: ["owl:imports", "door:imports", "void:vocabulary", "voaf:extends", "dct:requires", "oboInOwl:import"],
                helpText: "References another ontology metadata instance that describes an ontology containing definitions, whose meaning is considered to be part of the meaning of the ontology described by this ontology metadata instance"

      attribute :hasPriorVersion, namespace: :omv, enforce: [:uri], extractedMetadata: true,
                metadataMappings: ["owl:priorVersion", "dct:isVersionOf", "door:priorVersion", "prov:wasRevisionOf", "adms:prev", "pav:previousVersion", "pav:hasEarlierVersion"],
                helpText: "An URI to the prior version of the ontology"

      attribute :isBackwardCompatibleWith, namespace: :omv, enforce: [:list, :uri, :isOntology], extractedMetadata: true,
                metadataMappings: ["owl:backwardCompatibleWith", "door:backwardCompatibleWith"], display: "relations",
                helpText: "URI of an ontology that has its prior version compatible with the described ontology"

      attribute :isIncompatibleWith, namespace: :omv, enforce: [:list, :uri, :isOntology], extractedMetadata: true,
                metadataMappings: ["owl:incompatibleWith", "door:owlIncompatibleWith"], display: "relations",
                helpText: "URI of an ontology that is a prior version of this ontology, but not compatible"

      # New metadata to BioPortal
      attribute :deprecated, namespace: :owl, enforce: [:boolean], extractedMetadata: true, metadataMappings: ["idot:obsolete"],
                helpText: "To specify if the ontology IRI is deprecated"

      attribute :versionIRI, namespace: :owl, enforce: [:uri], extractedMetadata: true, display: "links", label: "Version IRI",
                helpText: "Identifies the version IRI of an ontology."

      # New metadata from DOOR
      attribute :ontologyRelatedTo, namespace: :door, enforce: [:list, :uri, :isOntology], extractedMetadata: true,
                metadataMappings: ["dc:relation", "dct:relation", "voaf:reliesOn"],
                helpText: "An ontology that uses or extends some class or property of the described ontology"

      attribute :comesFromTheSameDomain, namespace: :door, enforce: [:list, :uri, :isOntology], extractedMetadata: true, display: "relations",
                helpText: "Ontologies that come from the same domain", label: "From the same domain than"

      attribute :similarTo, namespace: :door, enforce: [:list, :uri, :isOntology], extractedMetadata: true, metadataMappings: ["voaf:similar"], display: "relations",
                helpText: "Vocabularies that are similar in scope and objectives, independently of the fact that they otherwise refer to each other."

      attribute :isAlignedTo, namespace: :door, enforce: [:list, :uri, :isOntology], extractedMetadata: true, metadataMappings: ["voaf:hasEquivalencesWith", "nkos:alignedWith"],
                helpText: "Ontologies that have an alignment which covers a substantial part of the described ontology"

      attribute :explanationEvolution, namespace: :door, enforce: [:uri, :isOntology], extractedMetadata: true, metadataMappings: ["voaf:specializes", "prov:specializationOf"],
                display: "relations", label: "Specialization of", helpText: "If the ontology is a latter version that is semantically equivalent to another ontology."

      attribute :generalizes, namespace: :voaf, enforce: [:uri, :isOntology], extractedMetadata: true, display: "relations", label: "Generalization of",
                helpText: "Vocabulary that is generalized by some superclasses or superproperties by the described ontology"

      attribute :hasDisparateModelling, namespace: :door, enforce: [:uri, :isOntology], extractedMetadata: true, display: "relations", label: "Disparate modelling with",
                helpText: "URI of an ontology that is considered to have a different model, because they represent corresponding entities in different ways.&lt;br&gt;e.g. an instance in one case and a class in the other for the same concept"

      # New metadata from SKOS
      attribute :hiddenLabel, namespace: :skos, extractedMetadata: true,
                helpText: "The hidden labels are useful when a user is interacting with a knowledge organization system via a text-based search function. The user may, for example, enter mis-spelled words when trying to find a relevant concept. If the mis-spelled query can be matched against a hidden label, the user will be able to find the relevant concept, but the hidden label won't otherwise be visible to the user"

      # New metadata from DC terms
      attribute :coverage, namespace: :dct, extractedMetadata: true, metadataMappings: ["dc:coverage", "schema:spatial"], display: "usage",
                helpText: "The spatial or temporal topic of the ontology, the spatial applicability of the ontology, or the jurisdiction under which the ontology is relevant."

      attribute :publisher, namespace: :dct, extractedMetadata: true, metadataMappings: ["dc:publisher", "schema:publisher"], display: "license",
                helpText: "An entity responsible for making the ontology available."

      attribute :identifier, namespace: :dct, extractedMetadata: true, metadataMappings: ["dc:identifier", "skos:notation", "adms:identifier"],
                helpText: "An unambiguous reference to the ontology. Use the ontology URI if not provided in the ontology metadata."

      attribute :source, namespace: :dct, enforce: [:concatenate], extractedMetadata: true, display: "links",
                metadataMappings: ["dc:source", "prov:wasInfluencedBy", "prov:wasDerivedFrom", "pav:derivedFrom", "schema:isBasedOn", "nkos:basedOn", "mod:sourceOntology"],
                helpText: "A related resource from which the described resource is derived."

      attribute :abstract, namespace: :dct, extractedMetadata: true, enforce: [:textarea], helpText: "A summary of the ontology"

      attribute :alternative, namespace: :dct, extractedMetadata: true, label: "Alternative name",
                metadataMappings: ["skos:altLabel", "idot:alternatePrefix", "schema:alternativeHeadline", "schema:alternateName"],
                helpText: "An alternative title for the ontology"

      attribute :hasPart, namespace: :dct, enforce: [:uri, :isOntology], extractedMetadata: true, metadataMappings: ["schema:hasPart", "oboInOwl:hasSubset", "adms:includedAsset"], display: "relations",
                helpText: "A related ontology that is included either physically or logically in the described ontology."

      attribute :isFormatOf, namespace: :dct, enforce: [:uri], extractedMetadata: true, display: "links",
                helpText: "URL to the original document that describe this ontology in a not ontological format (i.e.: the OBO original file)"

      attribute :hasFormat, namespace: :dct, enforce: [:uri], extractedMetadata: true, display: "links",
                helpText: "URL to a document that describe this ontology in a not ontological format (i.e.: the OBO original file) generated from this ontology."

      attribute :audience, namespace: :dct, extractedMetadata: true, metadataMappings: ["doap:audience", "schema:audience"], display: "community",
                helpText: "Description of the target user base of the ontology."

      attribute :valid, namespace: :dct, enforce: [:date_time], extractedMetadata: true, label: "Valid until",
                metadataMappings: ["prov:invaliatedAtTime", "schema:endDate"], display: "dates",
                helpText: "Date (often a range) of validity of the ontology."

      attribute :accrualMethod, namespace: :dct, extractedMetadata: true, display: "methodology",
                helpText: "The method by which items are added to the ontology."
      attribute :accrualPeriodicity, namespace: :dct, extractedMetadata: true, display: "methodology", metadataMappings: ["nkos:updateFrequency"],
                helpText: "The frequency with which items are added to the ontology."
      attribute :accrualPolicy, namespace: :dct, extractedMetadata: true, display: "methodology",
                helpText: "The policy governing the addition of items to the ontology."

      # New metadata from sd
      attribute :endpoint, namespace: :sd, enforce: [:uri], extractedMetadata: true, metadataMappings: ["void:sparqlEndpoint"], display: "content"

      # New metadata from VOID
      attribute :dataDump, namespace: :void, enforce: [:uri], extractedMetadata: true,
                metadataMappings: ["doap:download-mirror", "schema:distribution"], display: "content"

      attribute :csvDump, enforce: [:uri], display: "content", label: "CSV dump"

      attribute :openSearchDescription, namespace: :void, enforce: [:uri], extractedMetadata: true,
                metadataMappings: ["doap:service-endpoint"], display: "content"

      attribute :uriLookupEndpoint, namespace: :void, enforce: [:uri], extractedMetadata: true, display: "content", label: "URI Lookup Endpoint",
                helpText: "A protocol endpoint for simple URI lookups for the ontology."

      attribute :uriRegexPattern, namespace: :void, enforce: [:uri], extractedMetadata: true,
                metadataMappings: ["idot:identifierPattern"], display: "content", label: "URI Regex Pattern",
                helpText: "A regular expression that matches the URIs of the ontology entities."

      # New metadata from foaf
      attribute :depiction, namespace: :foaf, enforce: [:uri], extractedMetadata: true, metadataMappings: ["doap:screenshots", "schema:image"], display: "images",
                helpText: "The URL of an image representing the ontology."

      attribute :logo, namespace: :foaf, enforce: [:uri], extractedMetadata: true, metadataMappings: ["schema:logo"], display: "images",
                helpText: "The URL of the ontology logo."

      # New metadata from MOD
      attribute :competencyQuestion, namespace: :mod, extractedMetadata: true, enforce: [:textarea], display: "methodology",
                helpText: "A set of questions made to build an ontology at the design time."

      # New metadata from VOAF
      attribute :usedBy, namespace: :voaf, enforce: [:list, :uri, :isOntology], extractedMetadata: true, display: "relations", # Range : Ontology
                metadataMappings: ["nkos:usedBy"], helpText: "Ontologies that use the described ontology."

      attribute :metadataVoc, namespace: :voaf, enforce: [:list, :uri], extractedMetadata: true, display: "content", label: "Metadata vocabulary used",
                metadataMappings: ["mod:vocabularyUsed", "adms:supportedSchema", "schema:schemaVersion"],
                helpText: "Vocabularies that are used and/or referred to create the described ontology."

      attribute :hasDisjunctionsWith, namespace: :voaf, enforce: [:uri, :isOntology], extractedMetadata: true,
                helpText: "Ontology that declares some disjunct classes with the described ontology."

      attribute :toDoList, namespace: :voaf, enforce: [:concatenate, :textarea], extractedMetadata: true, display: "community",
                helpText: "Describes future tasks planned by a resource curator."

      # New metadata from VANN
      attribute :example, namespace: :vann, enforce: [:uri], extractedMetadata: true, metadataMappings: ["schema:workExample"], display: "usage",
                helpText: "A reference to a resource that provides an example of how this ontology can be used.", label: "Example of use"

      attribute :preferredNamespaceUri, namespace: :vann, extractedMetadata: true, metadataMappings: ["void:uriSpace"],
                helpText: "The preferred namespace URI to use when using terms from this ontology."

      attribute :preferredNamespacePrefix, namespace: :vann, extractedMetadata: true,
                metadataMappings: ["idot:preferredPrefix", "oboInOwl:default-namespace", "oboInOwl:hasDefaultNamespace"],
                helpText: "The preferred namespace prefix to use when using terms from this ontology."

      # New metadata from CC
      attribute :morePermissions, namespace: :cc, extractedMetadata: true, display: "license",
                helpText: "A related resource which describes additional permissions or alternative licenses."

      attribute :useGuidelines, namespace: :cc, extractedMetadata: true, enforce: [:textarea], display: "community",
                helpText: "A related resource which defines how the ontology should be used. "

      attribute :curatedOn, namespace: :pav, enforce: [:date_time], extractedMetadata: true, display: "dates",
                helpText: "The date the ontology was curated."

      # New metadata from ADMS and DOAP
      attribute :repository, namespace: :doap, enforce: [:uri], extractedMetadata: true, display: "community",
                helpText: "Link to the source code repository."

      # Should be bug-database and mailing-list but NameError - `@bug-database' is not allowed as an instance variable name
      attribute :bugDatabase, namespace: :doap, enforce: [:uri], extractedMetadata: true, display: "community",
                helpText: "Link to the bug tracker of the ontology (i.e.: GitHub issues)."

      attribute :mailingList, namespace: :doap, enforce: [:uri], extractedMetadata: true, display: "community",
                helpText: "Mailing list home page or email address."

      # New metadata from Schema and IDOT
      attribute :exampleIdentifier, namespace: :idot, enforce: [:uri], extractedMetadata: true, display: "content",
                helpText: "An example identifier used by one item (or record) from a dataset."

      attribute :award, namespace: :schema, extractedMetadata: true, display: "community",
                helpText: "An award won by this ontology."

      attribute :copyrightHolder, namespace: :schema, extractedMetadata: true, display: "license",
                helpText: "The party holding the legal copyright to the CreativeWork."

      attribute :associatedMedia, namespace: :schema, extractedMetadata: true, display: "images",
                helpText: "A media object that encodes this ontology. This property is a synonym for encoding."

      attribute :workTranslation, namespace: :schema, enforce: [:uri, :isOntology], extractedMetadata: true, display: "relations",
                helpText: "A ontology that is a translation of the content of this ontology.", label: "Translated from"

      attribute :translationOfWork, namespace: :schema, enforce: [:uri, :isOntology], extractedMetadata: true, metadataMappings: ["adms:translation"],
                helpText: "The ontology that this ontology has been translated from.", label: "Translation of", display: "relations"

      attribute :includedInDataCatalog, namespace: :schema, enforce: [:list, :uri], extractedMetadata: true, display: "links",
                helpText: "A data catalog which contains this ontology (i.e.: OBOfoundry, aber-owl, EBI, VEST registry...)."

      # Internal values for parsing - not definitive
      attribute :uploadFilePath
      attribute :diffFilePath
      attribute :masterFileName
      attribute :submissionStatus, enforce: [:submission_status, :list], default: lambda { |record| [LinkedData::Models::SubmissionStatus.find("UPLOADED").first] }
      attribute :missingImports, enforce: [:list]

      # URI for pulling ontology
      attribute :pullLocation, enforce: [:uri]

      # Link to ontology
      attribute :ontology, enforce: [:existence, :ontology]

      #Link to metrics
      attribute :metrics, enforce: [:metrics]

      # Hypermedia settings
      embed :contact, :ontology
      embed_values :submissionStatus => [:code], :hasOntologyLanguage => [:acronym]
      serialize_default :contact, :ontology, :hasOntologyLanguage, :released, :creationDate, :homepage,
                        :publication, :documentation, :version, :description, :status, :submissionId

      # Links
      links_load :submissionId, ontology: [:acronym]
      link_to LinkedData::Hypermedia::Link.new("metrics", lambda { |s| "#{self.ontology_link(s)}/submissions/#{s.submissionId}/metrics" }, self.type_uri)
      LinkedData::Hypermedia::Link.new("download", lambda { |s| "#{self.ontology_link(s)}/submissions/#{s.submissionId}/download" }, self.type_uri)

      # HTTP Cache settings
      cache_timeout 3600
      cache_segment_instance lambda { |sub| segment_instance(sub) }
      cache_segment_keys [:ontology_submission]
      cache_load ontology: [:acronym]

      # Access control
      read_restriction_based_on lambda { |sub| sub.ontology }
      access_control_load ontology: [:administeredBy, :acl, :viewingRestriction]

      def initialize(*args)
        super(*args)
        @mutex = Mutex.new
      end

      def synchronize(&block)
        @mutex.synchronize(&block)
      end

      def self.ontology_link(m)
        ontology_link = ""

        if m.class == self
          m.bring(:ontology) if m.bring?(:ontology)

          begin
            m.ontology.bring(:acronym) if m.ontology.bring?(:acronym)
            ontology_link = "ontologies/#{m.ontology.acronym}"
          rescue Exception => e
            ontology_link = ""
          end
        end
        ontology_link
      end

      # Override the bring_remaining method from Goo::Base::Resource : https://github.com/ncbo/goo/blob/master/lib/goo/base/resource.rb#L383
      # Because the old way to query the 4store was not working when lots of attributes
      # Now it is querying attributes 5 by 5 (way faster than 1 by 1)
      def bring_remaining
        to_bring = []
        i = 0
        self.class.attributes.each do |attr|
          to_bring << attr if self.bring?(attr)
          if i == 5
            self.bring(*to_bring)
            to_bring = []
            i = 0
          end
          i = i + 1
        end
        self.bring(*to_bring)
      end

      def self.segment_instance(sub)
        sub.bring(:ontology) unless sub.loaded_attributes.include?(:ontology)
        sub.ontology.bring(:acronym) unless sub.ontology.loaded_attributes.include?(:acronym)
        [sub.ontology.acronym] rescue []
      end

      def self.submission_id_generator(ss)
        if !ss.ontology.loaded_attributes.include?(:acronym)
          ss.ontology.bring(:acronym)
        end
        if ss.ontology.acronym.nil?
          raise ArgumentError, "Submission cannot be saved if ontology does not have acronym"
        end
        return RDF::URI.new(
          "#{(Goo.id_prefix)}ontologies/#{CGI.escape(ss.ontology.acronym.to_s)}/submissions/#{ss.submissionId.to_s}"
        )
      end

      # Copy file from /tmp/uncompressed-ont-rest-file to /srv/ncbo/repository/MY_ONT/1/
      def self.copy_file_repository(acronym, submissionId, src, filename = nil)
        path_to_repo = File.join([LinkedData.settings.repository_folder, acronym.to_s, submissionId.to_s])
        name = filename || File.basename(File.new(src).path)
        # THIS LOGGER IS JUST FOR DEBUG - remove after NCBO-795 is closed
        logger = Logger.new(Dir.pwd + "/create_permissions.log")
        if not Dir.exist? path_to_repo
          FileUtils.mkdir_p path_to_repo
          logger.debug("Dir created #{path_to_repo} | #{"%o" % File.stat(path_to_repo).mode} | umask: #{File.umask}") # NCBO-795
        end
        dst = File.join([path_to_repo, name])
        FileUtils.copy(src, dst)
        logger.debug("File created #{dst} | #{"%o" % File.stat(dst).mode} | umask: #{File.umask}") # NCBO-795
        if not File.exist? dst
          raise Exception, "Unable to copy #{src} to #{dst}"
        end
        return dst
      end

      def valid?
        valid_result = super
        return false unless valid_result
        sc = self.sanity_check
        return valid_result && sc
      end

      def sanity_check
        self.bring(:ontology) if self.bring?(:ontology)
        self.ontology.bring(:summaryOnly) if self.ontology.bring?(:summaryOnly)
        self.bring(:uploadFilePath) if self.bring?(:uploadFilePath)
        self.bring(:pullLocation) if self.bring?(:pullLocation)
        self.bring(:masterFileName) if self.bring?(:masterFileName)
        self.bring(:submissionStatus) if self.bring?(:submissionStatus)

        if self.submissionStatus
          self.submissionStatus.each do |st|
            st.bring(:code) if st.bring?(:code)
          end
        end

        # TODO: this code was added to deal with intermittent issues with 4store, where the error:
        # Attribute `summaryOnly` is not loaded for http://data.bioontology.org/ontologies/GPI
        # was thrown for no apparent reason!!!
        sum_only = nil

        begin
          sum_only = self.ontology.summaryOnly
        rescue Exception => e
          i = 0
          num_calls = LinkedData.settings.num_retries_4store
          sum_only = nil

          while sum_only.nil? && i < num_calls do
            i += 1
            puts "Exception while getting summaryOnly for #{self.id.to_s}. Retrying #{i} times..."
            sleep(1)

            begin
              self.ontology.bring(:summaryOnly)
              sum_only = self.ontology.summaryOnly
              puts "Success getting summaryOnly for #{self.id.to_s} after retrying #{i} times..."
            rescue Exception => e1
              sum_only = nil

              if i == num_calls
                raise $!, "#{$!} after retrying #{i} times...", $!.backtrace
              end
            end
          end
        end

        if sum_only == true || self.archived?
          return true
        elsif self.uploadFilePath.nil? && self.pullLocation.nil?
          self.errors[:uploadFilePath] = ["In non-summary only submissions a data file or url must be provided."]
          return false
        elsif self.pullLocation
          self.errors[:pullLocation] = ["File at #{self.pullLocation.to_s} does not exist"]
          if self.uploadFilePath.nil?
            return remote_file_exists?(self.pullLocation.to_s)
          end
          return true
        end

        zip = zipped?
        files =  LinkedData::Utils::FileHelpers.files_from_zip(self.uploadFilePath) if zip

        if not zip and self.masterFileName.nil?
          return true
        elsif zip and files.length == 1
          self.masterFileName = files.first
          return true
        elsif zip && self.masterFileName.nil? && LinkedData::Utils::FileHelpers.automaster?(self.uploadFilePath, self.hasOntologyLanguage.file_extension)
          self.masterFileName = LinkedData::Utils::FileHelpers.automaster(self.uploadFilePath, self.hasOntologyLanguage.file_extension)
          return true
        elsif zip and self.masterFileName.nil?
          #zip and masterFileName not set. The user has to choose.
          if self.errors[:uploadFilePath].nil?
            self.errors[:uploadFilePath] = []
          end

          #check for duplicated names
          repeated_names = LinkedData::Utils::FileHelpers.repeated_names_in_file_list(files)
          if repeated_names.length > 0
            names = repeated_names.keys.to_s
            self.errors[:uploadFilePath] <<
              "Zip file contains file names (#{names}) in more than one folder."
            return false
          end

          #error message with options to choose from.
          self.errors[:uploadFilePath] << {
            :message => "Zip file detected, choose the master file.", :options => files }
          return false

        elsif zip and not self.masterFileName.nil?
          #if zip and the user chose a file then we make sure the file is in the list.
          files = LinkedData::Utils::FileHelpers.files_from_zip(self.uploadFilePath)
          if not files.include? self.masterFileName
            if self.errors[:uploadFilePath].nil?
              self.errors[:uploadFilePath] = []
              self.errors[:uploadFilePath] << {
                :message =>
                  "The selected file `#{self.masterFileName}` is not included in the zip file",
                :options => files }
            end
          end
        end
        return true
      end

      def data_folder
        bring(:ontology) if bring?(:ontology)
        self.ontology.bring(:acronym) if self.ontology.bring?(:acronym)
        bring(:submissionId) if bring?(:submissionId)
        return File.join(LinkedData.settings.repository_folder,
                         self.ontology.acronym.to_s,
                         self.submissionId.to_s)
      end

      def zipped?(full_file_path = uploadFilePath)
        LinkedData::Utils::FileHelpers.zip?(full_file_path) || LinkedData::Utils::FileHelpers.gzip?(full_file_path)
      end

      def zip_folder
         File.join([data_folder, 'unzipped'])
      end

      def csv_path
        return File.join(self.data_folder, self.ontology.acronym.to_s + ".csv.gz")
      end

      def metrics_path
        return File.join(self.data_folder, "metrics.csv")
      end

      def rdf_path
        return File.join(self.data_folder, "owlapi.xrdf")
      end

      def parsing_log_path
        return File.join(self.data_folder, 'parsing.log')
      end

      def triples_file_path
        self.bring(:uploadFilePath) if self.bring?(:uploadFilePath)
        self.bring(:masterFileName) if self.bring?(:masterFileName)
        triples_file_name = File.basename(self.uploadFilePath.to_s)
        full_file_path = File.join(File.expand_path(self.data_folder.to_s), triples_file_name)
        zip = zipped? full_file_path
        triples_file_name = File.basename(self.masterFileName.to_s) if zip && self.masterFileName
        file_name = File.join(File.expand_path(self.data_folder.to_s), triples_file_name)
        File.expand_path(file_name)
      end

      def unzip_submission(logger)

        zip_dst = nil

        if zipped?
          zip_dst = self.zip_folder

          if Dir.exist? zip_dst
            FileUtils.rm_r [zip_dst]
          end
          FileUtils.mkdir_p zip_dst
          extracted = LinkedData::Utils::FileHelpers.unzip(self.uploadFilePath, zip_dst)

          # Set master file name automatically if there is only one file
          if extracted.length == 1 && self.masterFileName.nil?
            self.masterFileName = extracted.first.name
            self.save
          end

          if logger
            logger.info("Files extracted from zip/gz #{extracted}")
            logger.flush
          end
        end
        zip_dst
      end

      def delete_old_submission_files
        path_to_repo = data_folder
        submission_files = FILES_TO_DELETE.map { |f| File.join(path_to_repo, f) }
        submission_files.push(csv_path)
        submission_files.push(parsing_log_path) unless parsing_log_path.nil?
        FileUtils.rm(submission_files, force: true)
      end

      # accepts another submission in 'older' (it should be an 'older' ontology version)
      def diff(logger, older)
        begin
          bring_remaining
          bring :diffFilePath if bring? :diffFilePath
          older.bring :uploadFilePath if older.bring? :uploadFilePath

          LinkedData::Diff.logger = logger
          bubastis = LinkedData::Diff::BubastisDiffCommand.new(
            File.expand_path(older.master_file_path),
            File.expand_path(self.master_file_path),
            data_folder
          )
          self.diffFilePath = bubastis.diff
          save
          logger.info("Bubastis diff generated successfully for #{self.id}")
          logger.flush
        rescue Exception => e
          logger.error("Bubastis diff for #{self.id} failed - #{e.class}: #{e.message}")
          logger.flush
          raise e
        end
      end

      def class_count(logger = nil)
        logger ||= LinkedData::Parser.logger || Logger.new($stderr)
        count = -1
        count_set = false
        self.bring(:metrics) if self.bring?(:metrics)

        begin
          mx = self.metrics
        rescue Exception => e
          logger.error("Unable to retrieve metrics in class_count for #{self.id.to_s} - #{e.class}: #{e.message}")
          logger.flush
          mx = nil
        end

        self.bring(:hasOntologyLanguage) unless self.loaded_attributes.include?(:hasOntologyLanguage)

        if mx
          mx.bring(:classes) if mx.bring?(:classes)
          count = mx.classes

          if self.hasOntologyLanguage.skos?
            mx.bring(:individuals) if mx.bring?(:individuals)
            count += mx.individuals
          end
          count_set = true
        else
          mx = metrics_from_file(logger)

          unless mx.empty?
            count = mx[1][0].to_i

            if self.hasOntologyLanguage.skos?
              count += mx[1][1].to_i
            end
            count_set = true
          end
        end

        unless count_set
          logger.error("No calculated metrics or metrics file was found for #{self.id.to_s}. Unable to return total class count.")
          logger.flush
        end
        count
      end

      def metrics_from_file(logger = nil)
        logger ||= LinkedData::Parser.logger || Logger.new($stderr)
        metrics = []
        m_path = self.metrics_path

        begin
          metrics = CSV.read(m_path)
        rescue Exception => e
          logger.error("Unable to find metrics file: #{m_path}")
          logger.flush
        end
        metrics
      end

      def generate_metrics_file(class_count, indiv_count, prop_count)
        CSV.open(self.metrics_path, "wb") do |csv|
          csv << ["Class Count", "Individual Count", "Property Count"]
          csv << [class_count, indiv_count, prop_count]
        end
      end

      def generate_metrics_file2(class_count, indiv_count, prop_count, max_depth)
        CSV.open(self.metrics_path, "wb") do |csv|
          csv << ["Class Count", "Individual Count", "Property Count", "Max Depth"]
          csv << [class_count, indiv_count, prop_count, max_depth]
        end
      end

      def generate_umls_metrics_file(tr_file_path=nil)
        tr_file_path ||= self.triples_file_path
        class_count = 0
        indiv_count = 0
        prop_count = 0

        File.foreach(tr_file_path) do |line|
          class_count += 1 if line =~ /owl:Class/
          indiv_count += 1 if line =~ /owl:NamedIndividual/
          prop_count += 1 if line =~ /owl:ObjectProperty/
          prop_count += 1 if line =~ /owl:DatatypeProperty/
        end
        self.generate_metrics_file(class_count, indiv_count, prop_count)
      end

      def generate_rdf(logger, reasoning: true)
        mime_type = nil


        if self.hasOntologyLanguage.umls?
          triples_file_path = self.triples_file_path
          logger.info("Using UMLS turtle file found, skipping OWLAPI parse")
          logger.flush
          mime_type = LinkedData::MediaTypes.media_type_from_base(LinkedData::MediaTypes::TURTLE)
          generate_umls_metrics_file(triples_file_path)
        else
          output_rdf = self.rdf_path

          if File.exist?(output_rdf)
            logger.info("deleting old owlapi.xrdf ..")
            deleted = FileUtils.rm(output_rdf)

            if deleted.length > 0
              logger.info("deleted")
            else
              logger.info("error deleting owlapi.rdf")
            end
          end
          owlapi = owlapi_parser(logger: nil)

          if !reasoning
            owlapi.disable_reasoner
          end
          triples_file_path, missing_imports = owlapi.parse

          if missing_imports && missing_imports.length > 0
            self.missingImports = missing_imports

            missing_imports.each do |imp|
              logger.info("OWL_IMPORT_MISSING: #{imp}")
            end
          else
            self.missingImports = nil
          end
          logger.flush
        end
        delete_and_append(triples_file_path, logger, mime_type)
      end

      def process_callbacks(logger, callbacks, action_name, &block)
        callbacks.delete_if do |_, callback|
          begin
            if callback[action_name]
              callable = self.method(callback[action_name])
              yield(callable, callback)
            end
            false
          rescue Exception => e
            logger.error("#{e.class}: #{e.message}\n#{e.backtrace.join("\n\t")}")
            logger.flush

            if callback[:status]
              add_submission_status(callback[:status].get_error_status)
              self.save
            end

            # halt the entire processing if :required is set to true
            raise e if callback[:required]
            # continue processing of other callbacks, but not this one
            true
          end
        end
      end

      def loop_classes(logger, raw_paging, callbacks)
        page = 1
        size = 2500
        count_classes = 0
        acr = self.id.to_s.split("/")[-1]
        operations = callbacks.values.map { |v| v[:op_name] }.join(", ")

        time = Benchmark.realtime do
          paging = raw_paging.page(page, size)
          cls_count_set = false
          cls_count = class_count(logger)

          if cls_count > -1
            # prevent a COUNT SPARQL query if possible
            paging.page_count_set(cls_count)
            cls_count_set = true
          else
            cls_count = 0
          end

          iterate_classes = false
          # 1. init artifacts hash if not explicitly passed in the callback
          # 2. determine if class-level iteration is required
          callbacks.each { |_, callback| callback[:artifacts] ||= {}; iterate_classes = true if callback[:caller_on_each] }

          process_callbacks(logger, callbacks, :caller_on_pre) {
            |callable, callback| callable.call(callback[:artifacts], logger, paging) }

          page_len = -1
          prev_page_len = -1

          begin
            t0 = Time.now
            page_classes = paging.page(page, size).all
            total_pages = page_classes.total_pages
            page_len = page_classes.length

            # nothing retrieved even though we're expecting more records
            if total_pages > 0 && page_classes.empty? && (prev_page_len == -1 || prev_page_len == size)
              j = 0
              num_calls = LinkedData.settings.num_retries_4store

              while page_classes.empty? && j < num_calls do
                j += 1
                logger.error("Empty page encountered. Retrying #{j} times...")
                sleep(2)
                page_classes = paging.page(page, size).all
                logger.info("Success retrieving a page of #{page_classes.length} classes after retrying #{j} times...") unless page_classes.empty?
              end

              if page_classes.empty?
                msg = "Empty page #{page} of #{total_pages} persisted after retrying #{j} times. #{operations} of #{acr} aborted..."
                logger.error(msg)
                raise msg
              end
            end

            if page_classes.empty?
              if total_pages > 0
                logger.info("The number of pages reported for #{acr} - #{total_pages} is higher than expected #{page - 1}. Completing #{operations}...")
              else
                logger.info("Ontology #{acr} contains #{total_pages} pages...")
              end
              break
            end

            prev_page_len = page_len
            logger.info("#{acr}: page #{page} of #{total_pages} - #{page_len} ontology terms retrieved in #{Time.now - t0} sec.")
            logger.flush
            count_classes += page_classes.length

            process_callbacks(logger, callbacks, :caller_on_pre_page) {
              |callable, callback| callable.call(callback[:artifacts], logger, paging, page_classes, page) }

            page_classes.each { |c|
              # For real this is calling "generate_missing_labels_each". Is it that hard to be clear in your code?
              # It is unreadable, not stable and not powerful. What did you want to do?
              process_callbacks(logger, callbacks, :caller_on_each) {
                |callable, callback| callable.call(callback[:artifacts], logger, paging, page_classes, page, c) }
            } if iterate_classes

            process_callbacks(logger, callbacks, :caller_on_post_page) {
              |callable, callback| callable.call(callback[:artifacts], logger, paging, page_classes, page) }
            cls_count += page_classes.length unless cls_count_set

            page = page_classes.next? ? page + 1 : nil
          end while !page.nil?

          callbacks.each { |_, callback| callback[:artifacts][:count_classes] = cls_count }
          process_callbacks(logger, callbacks, :caller_on_post) {
            |callable, callback| callable.call(callback[:artifacts], logger, paging) }
        end

        logger.info("Completed #{operations}: #{acr} in #{time} sec. #{count_classes} classes.")
        logger.flush

        # set the status on actions that have completed successfully
        callbacks.each do |_, callback|
          if callback[:status]
            add_submission_status(callback[:status])
            self.save
          end
        end
      end

      def generate_missing_labels_pre(artifacts = {}, logger, paging)
        file_path = artifacts[:file_path]
        artifacts[:save_in_file] = File.join(File.dirname(file_path), "labels.ttl")
        artifacts[:save_in_file_mappings] = File.join(File.dirname(file_path), "mappings.ttl")
        property_triples = LinkedData::Utils::Triples.rdf_for_custom_properties(self)
        Goo.sparql_data_client.append_triples(self.id, property_triples, mime_type = "application/x-turtle")
        fsave = File.open(artifacts[:save_in_file], "w")
        fsave.write(property_triples)
        fsave_mappings = File.open(artifacts[:save_in_file_mappings], "w")
        artifacts[:fsave] = fsave
        artifacts[:fsave_mappings] = fsave_mappings
      end

      def generate_missing_labels_pre_page(artifacts = {}, logger, paging, page_classes, page)
        artifacts[:label_triples] = []
        artifacts[:mapping_triples] = []
      end

      # Generate labels when no label found in the prefLabel attribute (it checks rdfs:label and take label from the URI if nothing else found)
      def generate_missing_labels_each(artifacts = {}, logger, paging, page_classes, page, c)
        prefLabel = nil

        if c.prefLabel.nil?
          begin
            # in case there is no skos:prefLabel or rdfs:label from our main_lang
            rdfs_labels = c.label

            if rdfs_labels && rdfs_labels.length > 1 && c.synonym.length > 0
              rdfs_labels = (Set.new(c.label) - Set.new(c.synonym)).to_a.first

              if rdfs_labels.nil? || rdfs_labels.length == 0
                rdfs_labels = c.label
              end
            end

            if rdfs_labels and not (rdfs_labels.instance_of? Array)
              rdfs_labels = [rdfs_labels]
            end
            label = nil

            if rdfs_labels && rdfs_labels.length > 0
              label = rdfs_labels[0]
            else
              # If no label found, we take the last fragment of the URI
              label = LinkedData::Utils::Triples.last_iri_fragment c.id.to_s
            end
          rescue Goo::Base::AttributeNotLoaded => e
            label = LinkedData::Utils::Triples.last_iri_fragment c.id.to_s
          end
          artifacts[:label_triples] << LinkedData::Utils::Triples.label_for_class_triple(
            c.id, Goo.vocabulary(:metadata_def)[:prefLabel], label)
          prefLabel = label
        else
          prefLabel = c.prefLabel
        end

        if self.ontology.viewOf.nil?
          loomLabel = OntologySubmission.loom_transform_literal(prefLabel.to_s)

          if loomLabel.length > 2
            artifacts[:mapping_triples] << LinkedData::Utils::Triples.loom_mapping_triple(
              c.id, Goo.vocabulary(:metadata_def)[:mappingLoom], loomLabel)
          end
          artifacts[:mapping_triples] << LinkedData::Utils::Triples.uri_mapping_triple(
            c.id, Goo.vocabulary(:metadata_def)[:mappingSameURI], c.id)
        end
      end

      def generate_missing_labels_post_page(artifacts = {}, logger, paging, page_classes, page)
        rest_mappings = LinkedData::Mappings.migrate_rest_mappings(self.ontology.acronym)
        artifacts[:mapping_triples].concat(rest_mappings)

        if artifacts[:label_triples].length > 0
          logger.info("Asserting #{artifacts[:label_triples].length} labels in " +
                        "#{self.id.to_ntriples}")
          logger.flush
          artifacts[:label_triples] = artifacts[:label_triples].join("\n")
          artifacts[:fsave].write(artifacts[:label_triples])
          t0 = Time.now
          Goo.sparql_data_client.append_triples(self.id, artifacts[:label_triples], mime_type = "application/x-turtle")
          t1 = Time.now
          logger.info("Labels asserted in #{t1 - t0} sec.")
          logger.flush
        else
          logger.info("No labels generated in page #{page}.")
          logger.flush
        end

        if artifacts[:mapping_triples].length > 0
          logger.info("Asserting #{artifacts[:mapping_triples].length} mappings in " +
                        "#{self.id.to_ntriples}")
          logger.flush
          artifacts[:mapping_triples] = artifacts[:mapping_triples].join("\n")
          artifacts[:fsave_mappings].write(artifacts[:mapping_triples])

          t0 = Time.now
          Goo.sparql_data_client.append_triples(self.id, artifacts[:mapping_triples], mime_type = "application/x-turtle")
          t1 = Time.now
          logger.info("Mapping labels asserted in #{t1 - t0} sec.")
          logger.flush
        end
      end

      def generate_missing_labels_post(artifacts = {}, logger, paging)
        logger.info("end generate_missing_labels traversed #{artifacts[:count_classes]} classes")
        logger.info("Saved generated labels in #{artifacts[:save_in_file]}")
        artifacts[:fsave].close()
        artifacts[:fsave_mappings].close()
        logger.flush
      end

      def generate_obsolete_classes(logger, file_path)
        self.bring(:obsoleteProperty) if self.bring?(:obsoleteProperty)
        self.bring(:obsoleteParent) if self.bring?(:obsoleteParent)
        classes_deprecated = []
        if self.obsoleteProperty &&
          self.obsoleteProperty.to_s != "http://www.w3.org/2002/07/owl#deprecated"

          predicate_obsolete = RDF::URI.new(self.obsoleteProperty.to_s)
          query_obsolete_predicate = <<eos
SELECT ?class_id ?deprecated
FROM #{self.id.to_ntriples}
WHERE { ?class_id #{predicate_obsolete.to_ntriples} ?deprecated . }
eos
          Goo.sparql_query_client.query(query_obsolete_predicate).each_solution do |sol|
            unless ["0", "false"].include? sol[:deprecated].to_s
              classes_deprecated << sol[:class_id].to_s
            end
          end
          logger.info("Obsolete found #{classes_deprecated.length} for property #{self.obsoleteProperty.to_s}")
        end
        if self.obsoleteParent.nil?
          #try to find oboInOWL obsolete.
          obo_in_owl_obsolete_class = LinkedData::Models::Class
                                        .find(LinkedData::Utils::Triples.obo_in_owl_obsolete_uri)
                                        .in(self).first
          if obo_in_owl_obsolete_class
            self.obsoleteParent = LinkedData::Utils::Triples.obo_in_owl_obsolete_uri
          end
        end
        if self.obsoleteParent
          class_obsolete_parent = LinkedData::Models::Class
                                    .find(self.obsoleteParent)
                                    .in(self).first
          if class_obsolete_parent
            descendents_obsolete = class_obsolete_parent.descendants
            logger.info("Found #{descendents_obsolete.length} descendents of obsolete root #{self.obsoleteParent.to_s}")
            descendents_obsolete.each do |obs|
              classes_deprecated << obs.id
            end
          else
            logger.error("Submission #{self.id.to_s} obsoleteParent #{self.obsoleteParent.to_s} not found")
          end
        end
        if classes_deprecated.length > 0
          classes_deprecated.uniq!
          logger.info("Asserting owl:deprecated statement for #{classes_deprecated} classes")
          save_in_file = File.join(File.dirname(file_path), "obsolete.ttl")
          fsave = File.open(save_in_file, "w")
          classes_deprecated.each do |class_id|
            fsave.write(LinkedData::Utils::Triples.obselete_class_triple(class_id) + "\n")
          end
          fsave.close()
          result = Goo.sparql_data_client.append_triples_from_file(
            self.id,
            save_in_file,
            mime_type = "application/x-turtle")
        end
      end

      def add_submission_status(status)
        valid = status.is_a?(LinkedData::Models::SubmissionStatus)
        raise ArgumentError, "The status being added is not SubmissionStatus object" unless valid

        #archive removes the other status
        if status.archived?
          self.submissionStatus = [status]
          return self.submissionStatus
        end

        self.submissionStatus ||= []
        s = self.submissionStatus.dup

        if (status.error?)
          # remove the corresponding non_error status (if exists)
          non_error_status = status.get_non_error_status()
          s.reject! { |stat| stat.get_code_from_id() == non_error_status.get_code_from_id() } unless non_error_status.nil?
        else
          # remove the corresponding non_error status (if exists)
          error_status = status.get_error_status()
          s.reject! { |stat| stat.get_code_from_id() == error_status.get_code_from_id() } unless error_status.nil?
        end

        has_status = s.any? { |s| s.get_code_from_id() == status.get_code_from_id() }
        s << status unless has_status
        self.submissionStatus = s

      end

      def remove_submission_status(status)
        if (self.submissionStatus)
          valid = status.is_a?(LinkedData::Models::SubmissionStatus)
          raise ArgumentError, "The status being removed is not SubmissionStatus object" unless valid
          s = self.submissionStatus.dup

          # remove that status as well as the error status for the same status
          s.reject! { |stat|
            stat_code = stat.get_code_from_id()
            stat_code == status.get_code_from_id() ||
              stat_code == status.get_error_status().get_code_from_id()
          }
          self.submissionStatus = s
        end
      end

      def set_ready()
        ready_status = LinkedData::Models::SubmissionStatus.get_ready_status

        ready_status.each do |code|
          status = LinkedData::Models::SubmissionStatus.find(code).include(:code).first
          add_submission_status(status)
        end
      end

      # allows to optionally submit a list of statuses
      # that would define the "ready" state of this
      # submission in this context
      def ready?(options = {})
        self.bring(:submissionStatus) if self.bring?(:submissionStatus)
        status = options[:status] || :ready
        status = status.is_a?(Array) ? status : [status]
        return true if status.include?(:any)
        return false unless self.submissionStatus

        if status.include? :ready
          return LinkedData::Models::SubmissionStatus.status_ready?(self.submissionStatus)
        else
          status.each do |x|
            return false if self.submissionStatus.select { |x1|
              x1.get_code_from_id() == x.to_s.upcase
            }.length == 0
          end
          return true
        end
      end

      def archived?
        return ready?(status: [:archived])
      end

      ################################################################
      # Possible options with their defaults:
      #   process_rdf       = false
      #   index_search      = false
      #   index_properties  = false
      #   index_commit      = false
      #   run_metrics       = false
      #   reasoning         = false
      #   diff              = false
      #   archive           = false
      #   if no options passed, ALL actions, except for archive = true
      ################################################################
      def process_submission(logger, options = {})
        # Wrap the whole process so we can email results
        begin
          process_rdf = false
          index_search = false
          index_properties = false
          index_commit = false
          run_metrics = false
          reasoning = false
          diff = false
          archive = false

          if options.empty?
            process_rdf = true
            index_search = true
            index_properties = true
            index_commit = true
            run_metrics = true
            reasoning = true
            diff = true
            archive = false
          else
            process_rdf = options[:process_rdf] == true ? true : false
            index_search = options[:index_search] == true ? true : false
            index_properties = options[:index_properties] == true ? true : false
            index_commit = options[:index_commit] == true ? true : false
            run_metrics = options[:run_metrics] == true ? true : false

            if !process_rdf || options[:reasoning] == false
              reasoning = false
            else
              reasoning = true
            end

            if (!index_search && !index_properties) || options[:index_commit] == false
              index_commit = false
            else
              index_commit = true
            end

            diff = options[:diff] == true ? true : false
            archive = options[:archive] == true ? true : false
          end

          self.bring_remaining
          self.ontology.bring_remaining

          logger.info("Starting to process #{self.ontology.acronym}/submissions/#{self.submissionId}")
          logger.flush
          LinkedData::Parser.logger = logger
          status = nil

          if archive
            self.submissionStatus = nil
            status = LinkedData::Models::SubmissionStatus.find("ARCHIVED").first
            add_submission_status(status)

            # Delete everything except for original ontology file.
            ontology.bring(:submissions)
            submissions = ontology.submissions
            unless submissions.nil?
              submissions.each { |s| s.bring(:submissionId) }
              submission = submissions.sort { |a, b| b.submissionId <=> a.submissionId }[0]
              # Don't perform deletion if this is the most recent submission.
              if (self.submissionId < submission.submissionId)
                delete_old_submission_files
              end
            end
          else
            if process_rdf
              # Remove processing status types before starting RDF parsing etc.
              self.submissionStatus = nil
              status = LinkedData::Models::SubmissionStatus.find("UPLOADED").first
              add_submission_status(status)
              self.save

              # Parse RDF
              begin
                if not self.valid?
                  error = "Submission is not valid, it cannot be processed. Check errors."
                  raise ArgumentError, error
                end
                if not self.uploadFilePath
                  error = "Submission is missing an ontology file, cannot parse."
                  raise ArgumentError, error
                end
                status = LinkedData::Models::SubmissionStatus.find("RDF").first
                remove_submission_status(status) #remove RDF status before starting

                generate_rdf(logger, reasoning: reasoning)
                extract_metadata(logger, options[:params])
                add_submission_status(status)
                self.save
              rescue Exception => e
                logger.error("#{self.errors}")
                logger.error("#{e.class}: #{e.message}\n#{e.backtrace.join("\n\t")}")
                logger.flush
                add_submission_status(status.get_error_status)
                self.save
                # If RDF generation fails, no point of continuing
                raise e
              end

              file_path = self.uploadFilePath
              callbacks = {
                missing_labels: {
                  op_name: "Missing Labels Generation",
                  required: true,
                  status: LinkedData::Models::SubmissionStatus.find("RDF_LABELS").first,
                  artifacts: {
                    file_path: file_path
                  },
                  caller_on_pre: :generate_missing_labels_pre,
                  caller_on_pre_page: :generate_missing_labels_pre_page,
                  caller_on_each: :generate_missing_labels_each,
                  caller_on_post_page: :generate_missing_labels_post_page,
                  caller_on_post: :generate_missing_labels_post
                }
              }

              raw_paging = LinkedData::Models::Class.in(self).include(:prefLabel, :synonym, :label)
              loop_classes(logger, raw_paging, callbacks)

              status = LinkedData::Models::SubmissionStatus.find("OBSOLETE").first
              begin
                generate_obsolete_classes(logger, file_path)
                add_submission_status(status)
                self.save
              rescue Exception => e
                logger.error("#{e.class}: #{e.message}\n#{e.backtrace.join("\n\t")}")
                logger.flush
                add_submission_status(status.get_error_status)
                self.save
                # if obsolete fails the parsing fails
                raise e
              end
            end

            parsed = ready?(status: [:rdf, :rdf_labels])

            if index_search
              raise Exception, "The submission #{self.ontology.acronym}/submissions/#{self.submissionId} cannot be indexed because it has not been successfully parsed" unless parsed
              status = LinkedData::Models::SubmissionStatus.find("INDEXED").first
              begin
                index(logger, index_commit, false)
                add_submission_status(status)
              rescue Exception => e
                logger.error("#{e.class}: #{e.message}\n#{e.backtrace.join("\n\t")}")
                logger.flush
                add_submission_status(status.get_error_status)
                if File.file?(self.csv_path)
                  FileUtils.rm(self.csv_path)
                end
              ensure
                self.save
              end
            end

            if index_properties
              raise Exception, "The properties for the submission #{self.ontology.acronym}/submissions/#{self.submissionId} cannot be indexed because it has not been successfully parsed" unless parsed
              status = LinkedData::Models::SubmissionStatus.find("INDEXED_PROPERTIES").first
              begin
                index_properties(logger, index_commit, false)
                add_submission_status(status)
              rescue Exception => e
                logger.error("#{e.class}: #{e.message}\n#{e.backtrace.join("\n\t")}")
                logger.flush
                add_submission_status(status.get_error_status)
              ensure
                self.save
              end
            end

            if run_metrics
              raise Exception, "Metrics cannot be generated on the submission #{self.ontology.acronym}/submissions/#{self.submissionId} because it has not been successfully parsed" unless parsed
              status = LinkedData::Models::SubmissionStatus.find("METRICS").first
              begin
                process_metrics(logger)
                add_submission_status(status)
              rescue Exception => e
                logger.error("#{e.class}: #{e.message}\n#{e.backtrace.join("\n\t")}")
                logger.flush
                self.metrics = nil
                add_submission_status(status.get_error_status)
              ensure
                self.save
              end
            end

            if diff
              status = LinkedData::Models::SubmissionStatus.find("DIFF").first
              # Get previous submission from ontology.submissions
              self.ontology.bring(:submissions)
              submissions = self.ontology.submissions

              unless submissions.nil?
                submissions.each { |s| s.bring(:submissionId, :diffFilePath) }
                # Sort submissions in descending order of submissionId, extract last two submissions
                recent_submissions = submissions.sort { |a, b| b.submissionId <=> a.submissionId }[0..1]

                if recent_submissions.length > 1
                  # validate that the most recent submission is the current submission
                  if self.submissionId == recent_submissions.first.submissionId
                    prev = recent_submissions.last

                    # Ensure that prev is older than the current submission
                    if self.submissionId > prev.submissionId
                      # generate a diff
                      begin
                        self.diff(logger, prev)
                        add_submission_status(status)
                      rescue Exception => e
                        logger.error("#{e.class}: #{e.message}\n#{e.backtrace.join("\n\t")}")
                        logger.flush
                        add_submission_status(status.get_error_status)
                      ensure
                        self.save
                      end
                    end
                  end
                else
                  logger.info("Bubastis diff: no older submissions available for #{self.id}.")
                end
              else
                logger.info("Bubastis diff: no submissions available for #{self.id}.")
              end
            end
          end

          self.save
          logger.info("Submission processing of #{self.id} completed successfully")
          logger.flush
        ensure
          # make sure results get emailed
          begin
            LinkedData::Utils::Notifications.submission_processed(self)
          rescue Exception => e
            logger.error("Email sending failed: #{e.message}\n#{e.backtrace.join("\n\t")}"); logger.flush
          end
        end
        self
      end

      def process_metrics(logger)
        metrics = LinkedData::Metrics.metrics_for_submission(self, logger)
        metrics.id = RDF::URI.new(self.id.to_s + "/metrics")
        exist_metrics = LinkedData::Models::Metric.find(metrics.id).first
        exist_metrics.delete if exist_metrics
        metrics.save

        # Define metrics in submission metadata
        self.numberOfClasses = metrics.classes
        self.numberOfIndividuals = metrics.individuals
        self.numberOfProperties = metrics.properties
        self.maxDepth = metrics.maxDepth
        self.maxChildCount = metrics.maxChildCount
        self.averageChildCount = metrics.averageChildCount
        self.classesWithOneChild = metrics.classesWithOneChild
        self.classesWithMoreThan25Children = metrics.classesWithMoreThan25Children
        self.classesWithNoDefinition = metrics.classesWithNoDefinition

        self.metrics = metrics
        self
      end

      def index(logger, commit = true, optimize = true)
        page = 0
        size = 1000
        count_classes = 0

        time = Benchmark.realtime do
          self.bring(:ontology) if self.bring?(:ontology)
          self.ontology.bring(:acronym) if self.ontology.bring?(:acronym)
          self.ontology.bring(:provisionalClasses) if self.ontology.bring?(:provisionalClasses)
          csv_writer = LinkedData::Utils::OntologyCSVWriter.new
          csv_writer.open(self.ontology, self.csv_path)

          begin
            logger.info("Indexing ontology terms: #{self.ontology.acronym}...")
            t0 = Time.now
            self.ontology.unindex(false)
            logger.info("Removed ontology terms index (#{Time.now - t0}s)"); logger.flush

            paging = LinkedData::Models::Class.in(self).include(:unmapped).aggregate(:count, :children).page(page, size)
            # a fix for SKOS ontologies, see https://github.com/ncbo/ontologies_api/issues/20
            self.bring(:hasOntologyLanguage) unless self.loaded_attributes.include?(:hasOntologyLanguage)
            cls_count = self.hasOntologyLanguage.skos? ? -1 : class_count(logger)
            paging.page_count_set(cls_count) unless cls_count < 0
            total_pages = paging.page(1, size).all.total_pages
            num_threads = [total_pages, LinkedData.settings.indexing_num_threads].min
            threads = []
            page_classes = nil

            num_threads.times do |num|
              threads[num] = Thread.new {
                Thread.current["done"] = false
                Thread.current["page_len"] = -1
                Thread.current["prev_page_len"] = -1

                while !Thread.current["done"]
                  synchronize do
                    page = (page == 0 || page_classes.next?) ? page + 1 : nil

                    if page.nil?
                      Thread.current["done"] = true
                    else
                      Thread.current["page"] = page || "nil"
                      page_classes = paging.page(page, size).all
                      count_classes += page_classes.length
                      Thread.current["page_classes"] = page_classes
                      Thread.current["page_len"] = page_classes.length
                      Thread.current["t0"] = Time.now

                      # nothing retrieved even though we're expecting more records
                      if total_pages > 0 && page_classes.empty? && (Thread.current["prev_page_len"] == -1 || Thread.current["prev_page_len"] == size)
                        j = 0
                        num_calls = LinkedData.settings.num_retries_4store

                        while page_classes.empty? && j < num_calls do
                          j += 1
                          logger.error("Thread #{num + 1}: Empty page encountered. Retrying #{j} times...")
                          sleep(2)
                          page_classes = paging.page(page, size).all
                          logger.info("Thread #{num + 1}: Success retrieving a page of #{page_classes.length} classes after retrying #{j} times...") unless page_classes.empty?
                        end

                        if page_classes.empty?
                          msg = "Thread #{num + 1}: Empty page #{Thread.current["page"]} of #{total_pages} persisted after retrying #{j} times. Indexing of #{self.id.to_s} aborted..."
                          logger.error(msg)
                          raise msg
                        else
                          Thread.current["page_classes"] = page_classes
                        end
                      end

                      if page_classes.empty?
                        if total_pages > 0
                          logger.info("Thread #{num + 1}: The number of pages reported for #{self.id.to_s} - #{total_pages} is higher than expected #{page - 1}. Completing indexing...")
                        else
                          logger.info("Thread #{num + 1}: Ontology #{self.id.to_s} contains #{total_pages} pages...")
                        end

                        break
                      end

                      Thread.current["prev_page_len"] = Thread.current["page_len"]
                    end
                  end

                  break if Thread.current["done"]

                  logger.info("Thread #{num + 1}: Page #{Thread.current["page"]} of #{total_pages} - #{Thread.current["page_len"]} ontology terms retrieved in #{Time.now - Thread.current["t0"]} sec.")
                  Thread.current["t0"] = Time.now

                  Thread.current["page_classes"].each do |c|
                    begin
                      # this cal is needed for indexing of properties
                      LinkedData::Models::Class.map_attributes(c, paging.equivalent_predicates)
                    rescue Exception => e
                      i = 0
                      num_calls = LinkedData.settings.num_retries_4store
                      success = nil

                      while success.nil? && i < num_calls do
                        i += 1
                        logger.error("Thread #{num + 1}: Exception while mapping attributes for #{c.id.to_s}. Retrying #{i} times...")
                        sleep(2)

                        begin
                          LinkedData::Models::Class.map_attributes(c, paging.equivalent_predicates)
                          logger.info("Thread #{num + 1}: Success mapping attributes for #{c.id.to_s} after retrying #{i} times...")
                          success = true
                        rescue Exception => e1
                          success = nil

                          if i == num_calls
                            logger.error("Thread #{num + 1}: Error mapping attributes for #{c.id.to_s}:")
                            logger.error("Thread #{num + 1}: #{e1.class}: #{e1.message} after retrying #{i} times...\n#{e1.backtrace.join("\n\t")}")
                            logger.flush
                          end
                        end
                      end
                    end

                    synchronize do
                      csv_writer.write_class(c)
                    end
                  end
                  logger.info("Thread #{num + 1}: Page #{Thread.current["page"]} of #{total_pages} attributes mapped in #{Time.now - Thread.current["t0"]} sec.")

                  Thread.current["t0"] = Time.now
                  LinkedData::Models::Class.indexBatch(Thread.current["page_classes"])
                  logger.info("Thread #{num + 1}: Page #{Thread.current["page"]} of #{total_pages} - #{Thread.current["page_len"]} ontology terms indexed in #{Time.now - Thread.current["t0"]} sec.")
                  logger.flush
                end
              }
            end

            threads.map { |t| t.join }
            csv_writer.close

            begin
              # index provisional classes
              self.ontology.provisionalClasses.each { |pc| pc.index }
            rescue Exception => e
              logger.error("Error while indexing provisional classes for ontology #{self.ontology.acronym}:")
              logger.error("#{e.class}: #{e.message}\n#{e.backtrace.join("\n\t")}")
              logger.flush
            end

            if commit
              t0 = Time.now
              LinkedData::Models::Class.indexCommit()
              logger.info("Ontology terms index commit in #{Time.now - t0} sec.")
            end
          rescue StandardError => e
            csv_writer.close
            logger.error("\n\n#{e.class}: #{e.message}\n")
            logger.error(e.backtrace)
            raise e
          end
        end
        logger.info("Completed indexing ontology terms: #{self.ontology.acronym} in #{time} sec. #{count_classes} classes.")
        logger.flush

        if optimize
          logger.info("Optimizing ontology terms index...")
          time = Benchmark.realtime do
            LinkedData::Models::Class.indexOptimize()
          end
          logger.info("Completed optimizing ontology terms index in #{time} sec.")
        end
      end

      def index_properties(logger, commit = true, optimize = true)
        page = 1
        size = 2500
        count_props = 0

        time = Benchmark.realtime do
          self.bring(:ontology) if self.bring?(:ontology)
          self.ontology.bring(:acronym) if self.ontology.bring?(:acronym)
          logger.info("Indexing ontology properties: #{self.ontology.acronym}...")
          t0 = Time.now
          self.ontology.unindex_properties(commit)
          logger.info("Removed ontology properties index in #{Time.now - t0} seconds."); logger.flush

          props = self.ontology.properties
          count_props = props.length
          total_pages = (count_props / size.to_f).ceil
          logger.info("Indexing a total of #{total_pages} pages of #{size} properties each.")

          props.each_slice(size) do |prop_batch|
            t = Time.now
            LinkedData::Models::Class.indexBatch(prop_batch, :property)
            logger.info("Page #{page} of ontology properties indexed in #{Time.now - t} seconds."); logger.flush
            page += 1
          end

          if commit
            t0 = Time.now
            LinkedData::Models::Class.indexCommit(nil, :property)
            logger.info("Ontology properties index commit in #{Time.now - t0} seconds.")
          end
        end
        logger.info("Completed indexing ontology properties of #{self.ontology.acronym} in #{time} sec. Total of #{count_props} properties indexed.")
        logger.flush

        if optimize
          logger.info("Optimizing ontology properties index...")
          time = Benchmark.realtime do
            LinkedData::Models::Class.indexOptimize(nil, :property)
          end
          logger.info("Completed optimizing ontology properties index in #{time} seconds.")
        end
      end

      # Override delete to add removal from the search index
      #TODO: revise this with a better process
      def delete(*args)
        options = {}
        args.each { |e| options.merge!(e) if e.is_a?(Hash) }
        remove_index = options[:remove_index] ? true : false
        index_commit = options[:index_commit] == false ? false : true

        super(*args)
        self.ontology.unindex(index_commit)
        self.ontology.unindex_properties(index_commit)

        self.bring(:metrics) if self.bring?(:metrics)
        self.metrics.delete if self.metrics

        if remove_index
          # need to re-index the previous submission (if exists)
          self.ontology.bring(:submissions)

          if self.ontology.submissions.length > 0
            prev_sub = self.ontology.latest_submission()

            if prev_sub
              prev_sub.index(LinkedData::Parser.logger || Logger.new($stderr))
              prev_sub.index_properties(LinkedData::Parser.logger || Logger.new($stderr))
            end
          end
        end

        # delete the folder and files
        FileUtils.remove_dir(self.data_folder) if Dir.exist?(self.data_folder)
      end



      def roots(extra_include = nil, page = nil, pagesize = nil, concept_schemes: [])
        self.bring(:ontology) unless self.loaded_attributes.include?(:ontology)
        self.bring(:hasOntologyLanguage) unless self.loaded_attributes.include?(:hasOntologyLanguage)
        paged = false
        fake_paged = false

        if page || pagesize
          page ||= 1
          pagesize ||= 50
          paged = true
        end

        skos = self.hasOntologyLanguage&.skos?
        classes = []


        if skos
          classes = skos_roots(concept_schemes, page, paged, pagesize)
        else
          self.ontology.bring(:flat)
          data_query = nil
          if self.ontology.flat
            data_query = LinkedData::Models::Class.in(self)

            unless paged
              page = 1
              pagesize = FLAT_ROOTS_LIMIT
              paged = true
              fake_paged = true
            end
          else
            owl_thing = Goo.vocabulary(:owl)["Thing"]
            data_query = LinkedData::Models::Class.where(parents: owl_thing).in(self)
          end

          if paged
            page_data_query = data_query.page(page, pagesize)
            classes = page_data_query.page(page, pagesize).disable_rules.all
            # simulate unpaged query for flat ontologies
            # we use paging just to cap the return size
            classes = classes.to_a if fake_paged
          else
            classes = data_query.disable_rules.all
          end
        end

        where = LinkedData::Models::Class.in(self).models(classes).include(:prefLabel, :definition, :synonym, :obsolete)

        if extra_include
          [:prefLabel, :definition, :synonym, :obsolete, :childrenCount].each do |x|
            extra_include.delete x
          end
        end

        load_children = []

        if extra_include
          load_children = extra_include.delete :children

          if load_children.nil?
            load_children = extra_include.select { |x| x.instance_of?(Hash) && x.include?(:children) }

            if load_children.length > 0
              extra_include = extra_include.select { |x| !(x.instance_of?(Hash) && x.include?(:children)) }
            end
          else
            load_children = [:children]
          end

          if extra_include.length > 0
            where.include(extra_include)
          end
        end
        where.all

        if load_children.length > 0
          LinkedData::Models::Class.partially_load_children(classes, 99, self)
        end

        classes.delete_if { |c|
          obs = !c.obsolete.nil? && c.obsolete == true
          c.load_has_children if extra_include&.include?(:hasChildren) && !obs
          obs
        }

        classes
      end

      def ontology_uri
        self.bring(:URI) if self.bring? :URI
        RDF::URI.new(self.URI)
      end

      def uri
        self.ontology_uri.to_s
      end

      def uri=(uri)
        self.URI = uri
      end

      def roots_sorted(extra_include = nil, concept_schemes: [])
        classes = roots(extra_include, concept_schemes)
        LinkedData::Models::Class.sort_classes(classes)
      end

      def download_and_store_ontology_file
        file, filename = download_ontology_file
        file_location = self.class.copy_file_repository(self.ontology.acronym, self.submissionId, file, filename)
        self.uploadFilePath = file_location
        return file, filename
      end

      def remote_file_exists?(url)
        begin
          url = URI.parse(url)
          if url.kind_of?(URI::FTP)
            check = check_ftp_file(url)
          else
            check = check_http_file(url)
          end
        rescue Exception
          check = false
        end
        check
      end

      # Download ont file from pullLocation in /tmp/uncompressed-ont-rest-file
      def download_ontology_file
        file, filename = LinkedData::Utils::FileHelpers.download_file(self.pullLocation.to_s)
        return file, filename
      end

      def delete_classes_graph
        Goo.sparql_data_client.delete_graph(self.id)
      end


      def master_file_path
        path = if zipped?
                 File.join(self.zip_folder, self.masterFileName)
               else
                  self.uploadFilePath
               end
        File.expand_path(path)
      end

      def parsable?(logger: Logger.new($stdout))
        owlapi = owlapi_parser(logger: logger)
        owlapi.disable_reasoner
        parsable = true
        begin
          owlapi.parse
        rescue StandardError => e
          parsable = false
        end
        parsable
      end


      private


      def owlapi_parser_input
        path = if zipped?
                 self.zip_folder
               else
                 self.uploadFilePath
               end
        File.expand_path(path)
      end


      def owlapi_parser(logger: Logger.new($stdout))
        unzip_submission(logger)
        LinkedData::Parser::OWLAPICommand.new(
          owlapi_parser_input,
          File.expand_path(self.data_folder.to_s),
          master_file: self.masterFileName,
          logger: logger)
      end

      def delete_and_append(triples_file_path, logger, mime_type = nil)
        Goo.sparql_data_client.delete_graph(self.id)
        Goo.sparql_data_client.put_triples(self.id, triples_file_path, mime_type)
        logger.info("Triples #{triples_file_path} appended in #{self.id.to_ntriples}")
        logger.flush
      end

      def check_http_file(url)
        session = Net::HTTP.new(url.host, url.port)
        session.use_ssl = true if url.port == 443
        session.start do |http|
          response_valid = http.head(url.request_uri).code.to_i < 400
          return response_valid
        end
      end

      def check_ftp_file(uri)
        ftp = Net::FTP.new(uri.host, uri.user, uri.password)
        ftp.login
        begin
          file_exists = ftp.size(uri.path) > 0
        rescue Exception => e
          # Check using another method
          path = uri.path.split("/")
          filename = path.pop
          path = path.join("/")
          ftp.chdir(path)
          files = ftp.dir
          # Dumb check, just see if the filename is somewhere in the list
          files.each { |file| return true if file.include?(filename) }
        end
        file_exists
      end

      def self.loom_transform_literal(lit)
        res = []
        lit.each_char do |c|
          if (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')
            res << c.downcase
          end
        end
        return res.join ''
      end

    end
  end
end
