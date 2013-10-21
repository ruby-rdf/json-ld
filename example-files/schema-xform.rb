#!/usr/bin/env ruby
require 'rubygems'
require 'rdf/rdfa'
require 'json/ld'

type_exclusion = %w(
FinancialService
ProfessionalService
EntertainmentBusiness
AnimalShelter
AutomotiveBusiness
Store
FoodEstablishment
HealthAndBeautyBusiness
LodgingBusiness
SportsActivityLocation
ChildCare
MedicalOrganization
DryCleaningOrLaundry
HomeAndConstructionBusiness
EmergencyService
EmploymentAgency
GovernmentOffice
InternetCafe
Library
RadioStation
RealEstateAgent
RecyclingCenter
SelfStorage
ShoppingCenter
TelevisionStation
TouristInformationCenter
)

context = JSON.parse(File.read(File.expand_path("../schema-context.jsonld", __FILE__)))['@context']
object_map = {}

# Extract IDs
ARGV.each do |infile|
  outfile = infile.sub('.html', '.jsonld')
  puts outfile
  RDF::Repository.load(infile) do |repo|
    JSON::LD::API.fromRdf(repo) do |expanded|
      JSON::LD::API.compact(expanded, context) do |compacted|
        compacted['@graph'].each do |obj|
          next if type_exclusion.include?(obj['name'])
          object_map[obj['@id']] = obj if obj['@type'] == "rdfs:Class"
        end
      end
    end
  end

  thing = object_map['schema:Thing']

  # Build type heirarchy
  object_map.each do |id, obj|
    Array(obj['rdfs:subClassOf']).each do |super_class|
      so = object_map[super_class]
      next if so.nil?
      raise "super class not found: #{super_class}" if so.nil?
      (so['children'] ||= []) << obj
    end
  end

  context = context.merge({"children" => {"@reverse" => "rdfs:subClassOf"}})
  context = {"@context" => context}
  File.open(outfile, 'w') do |f|
    f.puts context.merge(thing).to_json(JSON::LD::JSON_STATE)
  end
end