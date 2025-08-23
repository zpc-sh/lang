defmodule Lang.Specs.JsonLD do
  @moduledoc """
  JSON-LD specifications with correct domain
  """

  @context %{
    "@context" => %{
      "lang" => "https://lang.nocsi.com/schema/v1#",
      "rdf" => "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
      "rdfs" => "http://www.w3.org/2000/01/rdf-schema#",
      "schema" => "https://schema.org/",
      "dc" => "http://purl.org/dc/terms/"
    }
  }

  def generate_openapi_spec(environment) do
    %{
      "openapi" => "3.1.0",
      "info" => %{
        "title" => "LANG #{String.capitalize(to_string(environment))} Intelligence API",
        "version" => "2.0.0",
        "x-ld-context" => @context
      },
      "servers" => [
        %{
          "url" => "https://lang.nocsi.com/api",
          "description" => "Production"
        },
        %{
          "url" => "https://lang.nocsi.com/api",
          "description" => "Development"
        }
      ],
      "paths" => generate_paths(environment)
    }
  end

  defp generate_paths(:text) do
    %{
      "/api/v2/text/parse" => %{
        "post" => %{
          "summary" => "Parse text with semantic extraction",
          "description" =>
            "Analyze text content and extract semantic information, entities, and metadata",
          "tags" => ["Text Intelligence"],
          "requestBody" => %{
            "required" => true,
            "content" => %{
              "application/ld+json" => %{
                "schema" => %{"$ref" => "#/components/schemas/TextParseRequest"}
              }
            }
          },
          "responses" => %{
            "200" => %{
              "description" => "Successful parsing with semantic data",
              "content" => %{
                "application/ld+json" => %{
                  "schema" => %{"$ref" => "#/components/schemas/TextParseResponse"}
                }
              }
            }
          }
        }
      }
    }
  end

  defp generate_paths(:filesystem) do
    %{
      "/api/v2/fs/browse" => %{
        "post" => %{
          "summary" => "Browse filesystem with semantic understanding",
          "tags" => ["Filesystem Intelligence"]
        }
      }
    }
  end

  defp generate_paths(:cloud) do
    %{
      "/api/v2/cloud/discover" => %{
        "post" => %{
          "summary" => "Discover cloud resources",
          "tags" => ["Cloud Intelligence"]
        }
      }
    }
  end

  defp generate_paths(:systems) do
    %{
      "/api/v2/systems/analyze" => %{
        "post" => %{
          "summary" => "Analyze system topology",
          "tags" => ["Systems Intelligence"]
        }
      }
    }
  end

  defp generate_paths(_) do
    %{}
  end
end
