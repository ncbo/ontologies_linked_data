Bubastis version 1.2
18th December 2014
---

Bubastis is an ontology change tool which is able to analyse two ontologies (typically two versions of the same ontology) to highlight logical changes which have occurred and to present these changes in more or less detail, as required.


Usage:
java -jar bubastis.jar parameters:
(required)  -ontology1 location of ontology 1 either a URL for an ontology on the web or a local file location in obo or owl format. Typically the older version of the ontologies being compared
(required)  -ontology2 location of ontology 2 either a URL or local file location of an obo or owl format ontology. Typically the newer version of the ontologies being compared.
(optional)  -output location of output file to send results, default is to console.
(optional)  -format required format of diff report, default is plain text, value 'xml' will produce xml
(optional)  -xslt for xml version of the diff report this will insert an xslt location into the header for rendering these in a customised manner in a web page. Value should be location of xslt file.

Examples:
Loading two files locally and outputting results to console:
java -jar bubastis.jar -ontology1 "H://obi_nov_08.owl" -ontology2 "H://obi_jan_09.owl"

Loading two files locally and output results to xml file with an xslt location inserted into header
java -jar bubastis.jar -1 "H://obi_nov_08.owl" -2 "H://obi_jan_09.owl" -output "H://OBIdiff.xml" -format xml -xslt "./stylesheets/bubastis.xslt"

Loading one file locally and one from the web and outputting results to plain text:
java -jar bubastis.jar -ontology1 "H://disease_ontology_version_1.owl" -ontology2 "http://www.disease.org/diseaseontology_latest.owl" -output "C://my_diff.txt" 