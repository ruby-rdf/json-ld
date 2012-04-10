# coding: utf-8
$:.unshift "."
require 'spec_helper'

describe JSON::LD::API do
  before(:each) { @debug = []}

  describe ".frame" do
    {
      "frame with @type matches subject with @type" => {
        :frame => {
          "@context" => {"ex" => "http://example.org/"},
          "@type" => "ex:Type1"
        },
        :input => [
          {
            "@context" => {"ex" => "http://example.org/"},
            "@id" => "ex:Sub1",
            "@type" => "ex:Type1"
          },
          {
            "@context" => {"ex" => "http://example.org/"},
            "@id" => "ex:Sub2",
            "@type" => "ex:Type2"
          },
        ],
        :output => [{
          "@context" => {"ex" => "http://example.org/"},
          "@id" => "ex:Sub1",
          "@type" => "ex:Type1"
        }]
      },
      "implicitly includes unframed properties" => {
        :frame => {
          "@context" => {"ex" => "http://example.org/"},
          "@type" => "ex:Type1"
        },
        :input => [
          {
            "@context" => {"ex" => "http://example.org/"},
            "@id" => "ex:Sub1",
            "@type" => "ex:Type1",
            "ex:prop1" => "Property 1",
            "ex:prop2" => {"@id" => "ex:Obj1"}
          }
        ],
        :output => [{
          "@context" => {"ex" => "http://example.org/"},
          "@id" => "ex:Sub1",
          "@type" => "ex:Type1",
          "ex:prop1" => "Property 1",
          "ex:prop2" => {"@id" => "ex:Obj1"}
        }]
      },
      "explicitly excludes unframed properties" => {
        :frame => {
          "@context" => {"ex" => "http://example.org/"},
          "@explicit" => true,
          "@type" => "ex:Type1"
        },
        :input => [
          {
            "@context" => {"ex" => "http://example.org/"},
            "@id" => "ex:Sub1",
            "@type" => "ex:Type1",
            "ex:prop1" => "Property 1",
            "ex:prop2" => {"@id" => "ex:Obj1"}
          }
        ],
        :output => [{
          "@context" => {"ex" => "http://example.org/"},
          "@id" => "ex:Sub1",
          "@type" => "ex:Type1"
        }]
      },
      "explicitly includes unframed properties" => {
        :frame => {
          "@context" => {"ex" => "http://example.org/"},
          "@explicit" => false,
          "@type" => "ex:Type1"
        },
        :input => [
          {
            "@context" => {"ex" => "http://example.org/"},
            "@id" => "ex:Sub1",
            "@type" => "ex:Type1",
            "ex:prop1" => "Property 1",
            "ex:prop2" => {"@id" => "ex:Obj1"}
          }
        ],
        :output => [{
          "@context" => {"ex" => "http://example.org/"},
          "@id" => "ex:Sub1",
          "@type" => "ex:Type1",
          "ex:prop1" => "Property 1",
          "ex:prop2" => {"@id" => "ex:Obj1"}
        }]
      },
      "frame without @type matches only subjects containing listed properties (duck typing)" => {
        :frame => {
          "@context" => {"ex" => "http://example.org/"},
          "ex:prop1" => {},
          "ex:prop2" => {}
        },
        :input => [
          {
            "@context" => {"ex" => "http://example.org/"},
            "@id" => "ex:Sub1",
            "ex:prop1" => "Property 1"
          },
          {
            "@context" => {"ex" => "http://example.org/"},
            "@id" => "ex:Sub2",
            "ex:prop2" => "Property 2"
          },
          {
            "@context" => {"ex" => "http://example.org/"},
            "@id" => "ex:Sub3",
            "ex:prop1" => "Property 1",
            "ex:prop2" => "Property 2"
          },
        ],
        :output => [{
          "@context" => {"ex" => "http://example.org/"},
          "@id" => "ex:Sub3",
          "ex:prop1" => "Property 1",
          "ex:prop2" => "Property 2"
        }]
      },
      "embed matched frames" => {
        :frame => {
          "@context" => {"ex" => "http://example.org/"},
          "@type" => "ex:Type1",
          "ex:includes" => {
            "@type" => "ex:Type2"
          }
        },
        :input => [
          {
            "@context" => {"ex" => "http://example.org/"},
            "@id" => "ex:Sub1",
            "@type" => "ex:Type1",
            "ex:includes" => {"@id" => "ex:Sub2"}
          },
          {
            "@context" => {"ex" => "http://example.org/"},
            "@id" => "ex:Sub2",
            "@type" => "ex:Type2",
            "ex:includes" => {"@id" => "ex:Sub1"}
          },
        ],
        :output => [{
          "@context" => {"ex" => "http://example.org/"},
          "@id" => "ex:Sub1",
          "@type" => "ex:Type1",
          "ex:includes" => {
            "@id" => "ex:Sub2",
            "@type" => "ex:Type2",
            "ex:includes" => {"@id" => "ex:Sub1"}
          }
        }]
      },
      "multiple matches" => {
        :frame => {
          "@context" => {"ex" => "http://example.org/"},
          "@type" => "ex:Type1"
        },
        :input => [
          {
            "@context" => {"ex" => "http://example.org/"},
            "@id" => "ex:Sub1",
            "@type" => "ex:Type1"
          },
          {
            "@context" => {"ex" => "http://example.org/"},
            "@id" => "ex:Sub2",
            "@type" => "ex:Type1"
          },
        ],
        :output => [
          {
            "@context" => {"ex" => "http://example.org/"},
            "@id" => "ex:Sub1",
            "@type" => "ex:Type1"
          },
          {
            "@context" => {"ex" => "http://example.org/"},
            "@id" => "ex:Sub2",
            "@type" => "ex:Type1"
          },
        ]
      },
      "non-existent framed properties create null property" => {
        :frame => {
          "@context" => {"ex" => "http://example.org/"},
          "@type" => "ex:Type1",
          "ex:null" => []
        },
        :input => [
          {
            "@context" => {"ex" => "http://example.org/"},
            "@id" => "ex:Sub1",
            "@type" => "ex:Type1",
            "ex:prop1" => "Property 1",
            "ex:prop2" => {"@id" => "ex:Obj1"}
          }
        ],
        :output => [{
          "@context" => {"ex" => "http://example.org/"},
          "@id" => "ex:Sub1",
          "@type" => "ex:Type1",
          "ex:prop1" => "Property 1",
          "ex:prop2" => {"@id" => "ex:Obj1"},
          "ex:null" => nil
        }]
      },
      "non-existent framed properties create default property" => {
        :frame => {
          "@context" => {"ex" => "http://example.org/", "ex:null" => {"@container" => "@set"}},
          "@type" => "ex:Type1",
          "ex:null" => [{"@default" => "foo"}]
        },
        :input => [
          {
            "@context" => {"ex" => "http://example.org/"},
            "@id" => "ex:Sub1",
            "@type" => "ex:Type1",
            "ex:prop1" => "Property 1",
            "ex:prop2" => {"@id" => "ex:Obj1"}
          }
        ],
        :output => [{
          "@context" => {"ex" => "http://example.org/", "ex:null" => {"@container" => "@set"}},
          "@id" => "ex:Sub1",
          "@type" => "ex:Type1",
          "ex:prop1" => "Property 1",
          "ex:prop2" => {"@id" => "ex:Obj1"},
          "ex:null" => ["foo"]
        }]
      },
      "mixed content" => {
        :frame => {
          "@context" => {"ex" => "http://example.org/"},
          "ex:mixed" => {"@embed" => false}
        },
        :input => [
          {
            "@context" => {"ex" => "http://example.org/"},
            "@id" => "ex:Sub1",
            "ex:mixed" => [
              {"@id" => "ex:Sub2"},
              "literal1"
            ]
          }
        ],
        :output => [{
          "@context" => {"ex" => "http://example.org/"},
          "@id" => "ex:Sub1",
          "ex:mixed" => [
            {"@id" => "ex:Sub2"},
            "literal1"
          ]
        }]
      },
      "no embedding" => {
        :frame => {
          "@context" => {"ex" => "http://example.org/"},
          "ex:embed" => {"@embed" => false}
        },
        :input => [
          {
            "@context" => {"ex" => "http://example.org/"},
            "@id" => "ex:Sub1",
            "ex:embed" => {
              "@id" => "ex:Sub2",
              "ex:prop" => "property"
            }
          }
        ],
        :output => [{
          "@context" => {"ex" => "http://example.org/"},
          "@id" => "ex:Sub1",
          "ex:embed" =>  {"@id" => "ex:Sub2"}
        }]
      },
    }.each do |title, params|
      it title do
        @debug = []
        jld = JSON::LD::API.frame(params[:input], params[:frame], nil, :debug => @debug)
        jld.should produce(params[:output], @debug)
      end
    end
  end
  
  describe "#get_framing_subjects" do
    {
      "single object" => {
        :input => {"@id" => "http://example.com", "@type" => RDF::RDFS.Resource.to_s},
        :subjects => %w(http://example.com),
        :output => {
          "http://example.com" => {
            "@id" => "http://example.com", "@type" => [RDF::RDFS.Resource.to_s]
          }
        }
      },
      "embedded object" => {
        :input => {
          "@context" => {"foaf" => RDF::FOAF.to_s},
          "@id" => "http://greggkellogg.net/foaf",
          "@type" => ["foaf:PersonalProfile"],
          "foaf:primaryTopic" => [{
            "@id" => "http://greggkellogg.net/foaf#me",
            "@type" => ["foaf:Person"]
          }]
        },
        :subjects => %w(http://greggkellogg.net/foaf http://greggkellogg.net/foaf#me),
        :output => {
          "http://greggkellogg.net/foaf" => {
            "@id" => "http://greggkellogg.net/foaf",
            "@type" => [RDF::FOAF.PersonalProfile.to_s],
            RDF::FOAF.primaryTopic.to_s => [{"@id" => "http://greggkellogg.net/foaf#me"}]
          },
          "http://greggkellogg.net/foaf#me" => {
            "@id" => "http://greggkellogg.net/foaf#me",
            "@type" => [RDF::FOAF.Person.to_s]
          }
        }
      },
      "embedded anon" => {
        :input => {
          "@context" => {"foaf" => RDF::FOAF.to_s},
          "@id" => "http://greggkellogg.net/foaf",
          "@type" => "foaf:PersonalProfile",
          "foaf:primaryTopic" => {
            "@type" => "foaf:Person"
          }
        },
        :subjects => %w(http://greggkellogg.net/foaf _:t0),
        :output => {
          "http://greggkellogg.net/foaf" => {
            "@id" => "http://greggkellogg.net/foaf",
            "@type" => [RDF::FOAF.PersonalProfile.to_s],
            RDF::FOAF.primaryTopic.to_s => [{"@id" => "_:t0"}]
          },
          "_:t0" => {
            "@id" => "_:t0",
            "@type" => [RDF::FOAF.Person.to_s]
          }
        }
      },
    }.each do |title, params|
      it title do
        @debug = []
        @subjects = Hash.ordered
        jld = nil
        JSON::LD::API.new(params[:input], nil, :debug => @debug) do |api|
          expanded_value = api.expand(api.value, nil, api.context)
          api.get_framing_subjects(@subjects, expanded_value, JSON::LD::BlankNodeNamer.new("t"))
        end
        @subjects.keys.should produce(params[:subjects], @debug)
        @subjects.should produce(params[:output], @debug)
      end
    end
  end

  describe ".flatten" do
    {
      "single object" => {
        :input => {"@id" => "http://example.com", "@type" => RDF::RDFS.Resource.to_s},
        :output => [{"@id" => "http://example.com", "@type" => [RDF::RDFS.Resource.to_s]}]
      },
      "embedded object" => {
        :input => {
          "@context" => {
            "foaf" => RDF::FOAF.to_s
          },
          "@id" => "http://greggkellogg.net/foaf",
          "@type" => ["foaf:PersonalProfile"],
          "foaf:primaryTopic" => [{
            "@id" => "http://greggkellogg.net/foaf#me",
            "@type" => ["foaf:Person"]
          }]
        },
        :output => [
          {
            "@id" => "http://greggkellogg.net/foaf",
            "@type" => [RDF::FOAF.PersonalProfile.to_s],
            RDF::FOAF.primaryTopic.to_s => [{"@id" => "http://greggkellogg.net/foaf#me"}]
          },
          {
            "@id" => "http://greggkellogg.net/foaf#me",
            "@type" => [RDF::FOAF.Person.to_s]
          }
        ]
      },
      "embedded anon" => {
        :input => {
          "@context" => {
            "foaf" => RDF::FOAF.to_s
          },
          "@id" => "http://greggkellogg.net/foaf",
          "@type" => "foaf:PersonalProfile",
          "foaf:primaryTopic" => {
            "@type" => "foaf:Person"
          }
        },
        :output => [
          {
            "@id" => "http://greggkellogg.net/foaf",
            "@type" => [RDF::FOAF.PersonalProfile.to_s],
            RDF::FOAF.primaryTopic.to_s => [{"@id" => "_:jld_t0000"}]
          },
          {
            "@id" => "_:jld_t0000",
            "@type" => [RDF::FOAF.Person.to_s]
          }
        ]
      }
    }.each do |title, params|
      it title do
        @debug = []
        jld = nil
        JSON::LD::API.new(params[:input], nil, :debug => @debug) do |api|
          jld = api.flatten
        end
        jld.should produce(params[:output], @debug)
      end
    end
  end
end
