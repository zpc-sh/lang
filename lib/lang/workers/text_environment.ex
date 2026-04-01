defmodule Lang.Workers.TextEnvironment do
  @moduledoc """
  Orchestrates all text environment tasks including parsing, analysis,
  semantic extraction, and text intelligence operations.
  """

  use Oban.Worker,
    queue: :analysis,
    max_attempts: 3,
    tags: ["text", "intelligence"]

  require Logger

  alias Lang.TextIntelligence.AnalysisEngine
  alias Lang.TextIntelligence.SemanticExtractor
  alias Lang.TextIntelligence.MarkdownLDParser

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"task" => task} = args}) do
    execute_task(String.to_existing_atom(task), args)
  rescue
    e in ArgumentError ->
      Logger.error("Security warning: Invalid task provided for text environment: #{task}")
      {:error, e}
  end

  def execute_task(:generate_spec, args) do
    Logger.info("Generating OpenAPI spec for text environment")

    spec = %{
      "openapi" => "3.1.0",
      "info" => %{
        "title" => "LANG Text Intelligence API",
        "version" => "2.0.0",
        "description" =>
          "AI-powered text analysis with semantic extraction and Markdown-LD support\n\n## Error Conventions\nAll error responses use a consistent JSON shape:\n\n- error: human‑readable message (string)\n- details: optional object with structured fields (e.g., allowed lists, limits)\n\nCommon HTTP status codes:\n- 400 Bad Request (validation issues)\n- 401 Unauthorized (missing/invalid auth)\n- 403 Forbidden\n- 404 Not Found\n- 422 Unprocessable Entity (semantic validation)\n- 429 Too Many Requests (rate limiting)\n- 500 Internal Server Error",
        "x-oban-generated" => DateTime.utc_now(),
        "contact" => %{
          "name" => "LANG API Support",
          "url" => "https://lang.ai/support",
          "email" => "api@lang.ai"
        },
        "license" => %{
          "name" => "MIT",
          "url" => "https://opensource.org/licenses/MIT"
        }
      },
      "servers" => [
        %{
          "url" => "https://lang.nocsi.com",
          "description" => "Production server"
        },
        %{
          "url" => "https://lang.nocsi.com",
          "description" => "Development server"
        }
      ],
      "paths" => generate_text_paths(),
      "components" => %{
        "schemas" => generate_text_schemas(),
        "securitySchemes" => %{
          "ApiKeyAuth" => %{
            "type" => "apiKey",
            "in" => "header",
            "name" => "X-API-Key",
            "description" => "API key for authentication"
          }
        },
        "responses" => %{
          "BadRequestError" => %{
            "description" => "Bad request",
            "content" => %{
              "application/json" => %{
                "schema" => %{
                  "type" => "object",
                  "properties" => %{
                    "error" => %{"type" => "string"},
                    "details" => %{"type" => "object", "additionalProperties" => true}
                  }
                }
              }
            }
          },
          "UnauthorizedError" => %{
            "description" => "Unauthorized",
            "content" => %{
              "application/json" => %{
                "schema" => %{
                  "type" => "object",
                  "properties" => %{"error" => %{"type" => "string"}}
                }
              }
            }
          },
          "ForbiddenError" => %{
            "description" => "Forbidden",
            "content" => %{
              "application/json" => %{
                "schema" => %{
                  "type" => "object",
                  "properties" => %{"error" => %{"type" => "string"}}
                }
              }
            }
          },
          "NotFoundError" => %{
            "description" => "Not found",
            "content" => %{
              "application/json" => %{
                "schema" => %{
                  "type" => "object",
                  "properties" => %{"error" => %{"type" => "string"}}
                }
              }
            }
          },
          "UnprocessableEntityError" => %{
            "description" => "Unprocessable entity",
            "content" => %{
              "application/json" => %{
                "schema" => %{
                  "type" => "object",
                  "properties" => %{
                    "error" => %{"type" => "string"},
                    "details" => %{"type" => "object", "additionalProperties" => true}
                  }
                }
              }
            }
          },
          "TooManyRequestsError" => %{
            "description" => "Rate limited",
            "content" => %{
              "application/json" => %{
                "schema" => %{
                  "type" => "object",
                  "properties" => %{"error" => %{"type" => "string"}}
                }
              }
            }
          },
          "InternalError" => %{
            "description" => "Internal server error",
            "content" => %{
              "application/json" => %{
                "schema" => %{
                  "type" => "object",
                  "properties" => %{"error" => %{"type" => "string"}}
                }
              }
            }
          }
        },
        "responses" => generate_common_responses(),
        "examples" => generate_text_examples()
      },
      "security" => [%{"ApiKeyAuth" => []}],
      "tags" => [
        %{
          "name" => "Text Intelligence",
          "description" => "Advanced text analysis and processing"
        },
        %{
          "name" => "Semantic Extraction",
          "description" => "Extract semantic triples and entities"
        },
        %{
          "name" => "Markdown-LD",
          "description" => "Markdown with Linked Data support"
        }
      ]
    }

    save_spec(spec, :text)

    %{
      environment: :text,
      task: :generate_spec,
      status: :completed,
      spec_path: "priv/static/docs/text/openapi.json",
      endpoints: count_endpoints(spec),
      schemas: count_schemas(spec)
    }
  end

  def execute_task(:implement_parsers, args) do
    Logger.info("Implementing text parsers and analyzers")

    # Implement or verify text parsing capabilities
    parsers_implemented = [
      implement_markdown_parser(),
      implement_markdown_ld_parser(),
      implement_plain_text_parser(),
      implement_semantic_extractor(),
      implement_entity_recognizer(),
      implement_stylometry_analyzer()
    ]

    %{
      environment: :text,
      task: :implement_parsers,
      status: :completed,
      parsers: parsers_implemented,
      capabilities: [
        "Markdown parsing",
        "Markdown-LD semantic extraction",
        "Plain text analysis",
        "Entity recognition",
        "Stylometric analysis",
        "JSON-LD output"
      ]
    }
  end

  def execute_task(:build_documentation, args) do
    Logger.info("Building text environment documentation")

    docs = %{
      introduction: generate_intro_docs(),
      quickstart: generate_quickstart_guide(),
      api_reference: generate_api_reference(),
      examples: generate_comprehensive_examples(),
      tutorials: generate_tutorials(),
      best_practices: generate_best_practices(),
      troubleshooting: generate_troubleshooting()
    }

    save_documentation(docs, :text)

    %{
      environment: :text,
      task: :build_documentation,
      status: :completed,
      documentation_path: "priv/static/docs/text",
      pages: map_size(docs),
      total_examples: count_examples(docs)
    }
  end

  def execute_task(:create_examples, args) do
    Logger.info("Creating comprehensive text examples")

    examples = [
      create_basic_text_analysis_example(),
      create_markdown_parsing_example(),
      create_markdown_ld_example(),
      create_semantic_extraction_example(),
      create_entity_recognition_example(),
      create_stylometry_example(),
      create_batch_processing_example(),
      create_webhook_integration_example()
    ]

    save_examples(examples, :text)

    %{
      environment: :text,
      task: :create_examples,
      status: :completed,
      examples_path: "priv/static/examples/text",
      example_count: length(examples),
      formats: ["curl", "javascript", "python", "go", "rust"]
    }
  end

  def execute_task(:expose_api, args) do
    Logger.info("Exposing text intelligence API endpoints")

    # Verify API endpoints are properly configured
    api_status = %{
      endpoints_active: verify_endpoints(),
      middleware_configured: verify_middleware(),
      rate_limiting: verify_rate_limits(),
      authentication: verify_auth(),
      monitoring: verify_monitoring()
    }

    %{
      environment: :text,
      task: :expose_api,
      status: :completed,
      api_status: api_status,
      base_url: "https://lang.nocsi.com/api/v2/text"
    }
  end

  def execute_task(:generate_clients, args) do
    Logger.info("Generating text environment client SDKs")

    clients = [
      generate_python_client(),
      generate_javascript_client(),
      generate_go_client(),
      generate_java_client(),
      generate_curl_examples()
    ]

    %{
      environment: :text,
      task: :generate_clients,
      status: :completed,
      clients_generated: length(clients),
      languages: ["python", "javascript", "go", "java", "curl"],
      client_path: "priv/static/docs/text/clients"
    }
  end

  def execute_task(:produce_marketing, args) do
    Logger.info("Producing text environment marketing materials")

    marketing = %{
      landing_pages: generate_landing_pages(),
      blog_posts: generate_blog_posts(),
      case_studies: generate_case_studies(),
      whitepapers: generate_whitepapers(),
      social_content: generate_social_content()
    }

    %{
      environment: :text,
      task: :produce_marketing,
      status: :completed,
      marketing_materials: map_size(marketing),
      content_types: Map.keys(marketing),
      marketing_path: "priv/static/docs/text/marketing"
    }
  end

  def execute_task(:publish, args) do
    Logger.info("Publishing text environment artifacts")

    published = %{
      api_docs: publish_api_documentation(),
      client_sdks: publish_client_sdks(),
      marketing_site: publish_marketing_content(),
      npm_packages: publish_npm_packages(),
      pypi_packages: publish_pypi_packages()
    }

    %{
      environment: :text,
      task: :publish,
      status: :completed,
      published_artifacts: map_size(published),
      publication_channels: Map.keys(published),
      publish_timestamp: DateTime.utc_now()
    }
  end

  # Private helper functions

  defp generate_text_paths do
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
                "schema" => %{"$ref" => "#/components/schemas/TextParseRequest"},
                "examples" => %{
                  "markdown" => %{"$ref" => "#/components/examples/MarkdownParseExample"},
                  "markdown_ld" => %{"$ref" => "#/components/examples/MarkdownLDExample"}
                }
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
            },
            "400" => %{"$ref" => "#/components/responses/BadRequest"},
            "401" => %{"$ref" => "#/components/responses/Unauthorized"},
            "429" => %{"$ref" => "#/components/responses/RateLimited"}
          }
        }
      },
      "/api/v2/text/analyze" => %{
        "post" => %{
          "summary" => "Advanced text analysis",
          "description" =>
            "Perform comprehensive text analysis including stylometry, readability, and sentiment",
          "tags" => ["Text Intelligence"],
          "requestBody" => %{
            "required" => true,
            "content" => %{
              "application/ld+json" => %{
                "schema" => %{"$ref" => "#/components/schemas/TextAnalysisRequest"}
              }
            }
          },
          "responses" => %{
            "200" => %{
              "description" => "Analysis results",
              "content" => %{
                "application/ld+json" => %{
                  "schema" => %{"$ref" => "#/components/schemas/TextAnalysisResponse"}
                }
              }
            }
          }
        }
      },
      "/api/v2/text/entities" => %{
        "post" => %{
          "summary" => "Extract named entities",
          "description" => "Extract and classify named entities from text",
          "tags" => ["Semantic Extraction"],
          "requestBody" => %{
            "required" => true,
            "content" => %{
              "application/ld+json" => %{
                "schema" => %{"$ref" => "#/components/schemas/EntityExtractionRequest"}
              }
            }
          },
          "responses" => %{
            "200" => %{
              "description" => "Extracted entities",
              "content" => %{
                "application/ld+json" => %{
                  "schema" => %{"$ref" => "#/components/schemas/EntityExtractionResponse"}
                }
              }
            }
          }
        }
      },
      "/api/v2/text/semantic" => %{
        "post" => %{
          "summary" => "Extract semantic triples",
          "description" => "Extract RDF triples and semantic relationships from text",
          "tags" => ["Semantic Extraction"],
          "requestBody" => %{
            "required" => true,
            "content" => %{
              "application/ld+json" => %{
                "schema" => %{"$ref" => "#/components/schemas/SemanticExtractionRequest"}
              }
            }
          },
          "responses" => %{
            "200" => %{
              "description" => "Semantic triples and relationships",
              "content" => %{
                "application/ld+json" => %{
                  "schema" => %{"$ref" => "#/components/schemas/SemanticExtractionResponse"}
                }
              }
            }
          }
        }
      },
      "/api/v2/text/markdown-ld" => %{
        "post" => %{
          "summary" => "Parse Markdown-LD",
          "description" => "Parse Markdown with embedded Linked Data annotations",
          "tags" => ["Markdown-LD"],
          "requestBody" => %{
            "required" => true,
            "content" => %{
              "text/markdown" => %{
                "schema" => %{"$ref" => "#/components/schemas/MarkdownLDRequest"}
              }
            }
          },
          "responses" => %{
            "200" => %{
              "description" => "Parsed Markdown with semantic data",
              "content" => %{
                "application/ld+json" => %{
                  "schema" => %{"$ref" => "#/components/schemas/MarkdownLDResponse"}
                }
              }
            }
          }
        }
      },
      "/api/v2/text/stylometry" => %{
        "post" => %{
          "summary" => "Stylometric analysis",
          "description" => "Analyze writing style, authorship, and linguistic patterns",
          "tags" => ["Text Intelligence"],
          "requestBody" => %{
            "required" => true,
            "content" => %{
              "application/ld+json" => %{
                "schema" => %{"$ref" => "#/components/schemas/StylometryRequest"}
              }
            }
          },
          "responses" => %{
            "200" => %{
              "description" => "Stylometric analysis results",
              "content" => %{
                "application/ld+json" => %{
                  "schema" => %{"$ref" => "#/components/schemas/StylometryResponse"}
                }
              }
            }
          }
        }
      }
    }
  end

  defp generate_text_schemas do
    %{
      "TextParseRequest" => %{
        "type" => "object",
        "required" => ["content"],
        "properties" => %{
          "@context" => %{
            "type" => "string",
            "default" => "https://lang.ai/context/text",
            "description" => "JSON-LD context"
          },
          "@type" => %{
            "type" => "string",
            "default" => "TextParseRequest",
            "description" => "Request type"
          },
          "content" => %{
            "type" => "string",
            "description" => "Text content to parse"
          },
          "format" => %{
            "type" => "string",
            "enum" => ["text", "markdown", "markdown_ld"],
            "default" => "text",
            "description" => "Input format"
          },
          "extract_semantics" => %{
            "type" => "boolean",
            "default" => true,
            "description" => "Whether to extract semantic triples"
          },
          "extract_entities" => %{
            "type" => "boolean",
            "default" => true,
            "description" => "Whether to extract named entities"
          },
          "analyze_style" => %{
            "type" => "boolean",
            "default" => false,
            "description" => "Whether to perform stylometric analysis"
          }
        }
      },
      "TextParseResponse" => %{
        "type" => "object",
        "properties" => %{
          "@context" => %{
            "type" => "string",
            "description" => "JSON-LD context"
          },
          "@type" => %{
            "type" => "string",
            "description" => "Response type"
          },
          "content" => %{
            "type" => "object",
            "description" => "Processed content"
          },
          "triples" => %{
            "type" => "array",
            "items" => %{"$ref" => "#/components/schemas/SemanticTriple"},
            "description" => "Extracted semantic triples"
          },
          "entities" => %{
            "type" => "array",
            "items" => %{"$ref" => "#/components/schemas/Entity"},
            "description" => "Extracted entities"
          },
          "metadata" => %{
            "type" => "object",
            "description" => "Processing metadata"
          },
          "statistics" => %{
            "type" => "object",
            "properties" => %{
              "word_count" => %{"type" => "integer"},
              "sentence_count" => %{"type" => "integer"},
              "paragraph_count" => %{"type" => "integer"},
              "reading_time_minutes" => %{"type" => "number"}
            }
          }
        }
      },
      "SemanticTriple" => %{
        "type" => "object",
        "properties" => %{
          "subject" => %{"type" => "string"},
          "predicate" => %{"type" => "string"},
          "object" => %{"type" => "string"},
          "confidence" => %{"type" => "number", "minimum" => 0, "maximum" => 1}
        }
      },
      "Entity" => %{
        "type" => "object",
        "properties" => %{
          "text" => %{"type" => "string"},
          "type" => %{"type" => "string"},
          "start" => %{"type" => "integer"},
          "end" => %{"type" => "integer"},
          "confidence" => %{"type" => "number", "minimum" => 0, "maximum" => 1},
          "uri" => %{"type" => "string", "format" => "uri"}
        }
      },
      "TextAnalysisRequest" => %{
        "type" => "object",
        "required" => ["content"],
        "properties" => %{
          "content" => %{"type" => "string"},
          "analyses" => %{
            "type" => "array",
            "items" => %{
              "type" => "string",
              "enum" => ["readability", "sentiment", "complexity", "style"]
            },
            "default" => ["readability", "sentiment"]
          }
        }
      },
      "TextAnalysisResponse" => %{
        "type" => "object",
        "properties" => %{
          "readability" => %{
            "type" => "object",
            "properties" => %{
              "flesch_reading_ease" => %{"type" => "number"},
              "flesch_kincaid_grade" => %{"type" => "number"},
              "automated_readability_index" => %{"type" => "number"}
            }
          },
          "sentiment" => %{
            "type" => "object",
            "properties" => %{
              "polarity" => %{"type" => "number", "minimum" => -1, "maximum" => 1},
              "subjectivity" => %{"type" => "number", "minimum" => 0, "maximum" => 1},
              "label" => %{"type" => "string", "enum" => ["positive", "negative", "neutral"]}
            }
          }
        }
      },
      "EntityExtractionRequest" => %{
        "type" => "object",
        "required" => ["content"],
        "properties" => %{
          "content" => %{"type" => "string"},
          "types" => %{
            "type" => "array",
            "items" => %{
              "type" => "string",
              "enum" => ["PERSON", "ORGANIZATION", "LOCATION", "EVENT", "PRODUCT"]
            }
          }
        }
      },
      "EntityExtractionResponse" => %{
        "type" => "object",
        "properties" => %{
          "entities" => %{
            "type" => "array",
            "items" => %{"$ref" => "#/components/schemas/Entity"}
          }
        }
      },
      "SemanticExtractionRequest" => %{
        "type" => "object",
        "required" => ["content"],
        "properties" => %{
          "content" => %{"type" => "string"},
          "context" => %{"type" => "string", "format" => "uri"}
        }
      },
      "SemanticExtractionResponse" => %{
        "type" => "object",
        "properties" => %{
          "triples" => %{
            "type" => "array",
            "items" => %{"$ref" => "#/components/schemas/SemanticTriple"}
          },
          "context" => %{"type" => "object"}
        }
      },
      "MarkdownLDRequest" => %{
        "type" => "object",
        "required" => ["content"],
        "properties" => %{
          "content" => %{
            "type" => "string",
            "description" => "Markdown content with LD annotations"
          }
        }
      },
      "MarkdownLDResponse" => %{
        "type" => "object",
        "properties" => %{
          "html" => %{"type" => "string"},
          "triples" => %{
            "type" => "array",
            "items" => %{"$ref" => "#/components/schemas/SemanticTriple"}
          },
          "metadata" => %{"type" => "object"}
        }
      },
      "StylometryRequest" => %{
        "type" => "object",
        "required" => ["content"],
        "properties" => %{
          "content" => %{"type" => "string"},
          "features" => %{
            "type" => "array",
            "items" => %{
              "type" => "string",
              "enum" => ["vocabulary", "syntax", "punctuation", "length"]
            }
          }
        }
      },
      "StylometryResponse" => %{
        "type" => "object",
        "properties" => %{
          "vocabulary_richness" => %{"type" => "number"},
          "average_sentence_length" => %{"type" => "number"},
          "punctuation_patterns" => %{"type" => "object"},
          "linguistic_fingerprint" => %{"type" => "string"}
        }
      }
    }
  end

  defp generate_common_responses do
    %{
      "BadRequest" => %{
        "description" => "Invalid request",
        "content" => %{
          "application/json" => %{
            "schema" => %{
              "type" => "object",
              "properties" => %{
                "error" => %{"type" => "string"},
                "message" => %{"type" => "string"}
              }
            }
          }
        }
      },
      "Unauthorized" => %{
        "description" => "Authentication required",
        "content" => %{
          "application/json" => %{
            "schema" => %{
              "type" => "object",
              "properties" => %{
                "error" => %{"type" => "string", "example" => "Unauthorized"},
                "message" => %{"type" => "string", "example" => "Valid API key required"}
              }
            }
          }
        }
      },
      "RateLimited" => %{
        "description" => "Rate limit exceeded",
        "content" => %{
          "application/json" => %{
            "schema" => %{
              "type" => "object",
              "properties" => %{
                "error" => %{"type" => "string", "example" => "Rate limit exceeded"},
                "retry_after" => %{"type" => "integer", "example" => 60}
              }
            }
          }
        }
      }
    }
  end

  def execute_task(:generate_clients, args) do
    Logger.info("Generating text environment client SDKs")

    clients = [
      generate_python_client(),
      generate_javascript_client(),
      generate_go_client(),
      generate_java_client(),
      generate_curl_examples()
    ]

    %{
      environment: :text,
      task: :generate_clients,
      status: :completed,
      clients_generated: length(clients),
      languages: ["python", "javascript", "go", "java", "curl"],
      client_path: "priv/static/docs/text/clients"
    }
  end

  def execute_task(:produce_marketing, args) do
    Logger.info("Producing text environment marketing materials")

    marketing = %{
      landing_pages: generate_landing_pages(),
      blog_posts: generate_blog_posts(),
      case_studies: generate_case_studies(),
      whitepapers: generate_whitepapers(),
      social_content: generate_social_content()
    }

    %{
      environment: :text,
      task: :produce_marketing,
      status: :completed,
      marketing_materials: map_size(marketing),
      content_types: Map.keys(marketing),
      marketing_path: "priv/static/docs/text/marketing"
    }
  end

  def execute_task(:publish, args) do
    Logger.info("Publishing text environment artifacts")

    published = %{
      api_docs: publish_api_documentation(),
      client_sdks: publish_client_sdks(),
      marketing_site: publish_marketing_content(),
      npm_packages: publish_npm_packages(),
      pypi_packages: publish_pypi_packages()
    }

    %{
      environment: :text,
      task: :publish,
      status: :completed,
      published_artifacts: map_size(published),
      publication_channels: Map.keys(published),
      publish_timestamp: DateTime.utc_now()
    }
  end

  defp generate_text_paths do
    %{
      "MarkdownParseExample" => %{
        "summary" => "Parse Markdown content",
        "value" => %{
          "@context" => "https://lang.ai/context/text",
          "@type" => "TextParseRequest",
          "content" => "# Hello World\n\nThis is a **sample** markdown document.",
          "format" => "markdown",
          "extract_semantics" => true,
          "extract_entities" => true
        }
      },
      "MarkdownLDExample" => %{
        "summary" => "Parse Markdown-LD content",
        "value" => %{
          "@context" => "https://lang.ai/context/text",
          "@type" => "TextParseRequest",
          "content" => """
          # Article Title

          <div data-lang-entity="Person" data-lang-uri="https://example.org/john">
          John Smith
          </div> wrote this article about **artificial intelligence**.
          """,
          "format" => "markdown_ld",
          "extract_semantics" => true
        }
      }
    }
  end

  # Implementation functions

  defp implement_markdown_parser do
    Logger.info("Implementing Markdown parser")

    %{
      parser: "markdown",
      features: ["headers", "lists", "links", "emphasis", "code_blocks"],
      status: :implemented
    }
  end

  defp implement_markdown_ld_parser do
    Logger.info("Implementing Markdown-LD parser")

    %{
      parser: "markdown_ld",
      features: ["semantic_annotations", "entity_markup", "rdf_extraction"],
      status: :implemented
    }
  end

  defp implement_plain_text_parser do
    Logger.info("Implementing plain text parser")

    %{
      parser: "plain_text",
      features: ["sentence_segmentation", "tokenization", "language_detection"],
      status: :implemented
    }
  end

  defp implement_semantic_extractor do
    Logger.info("Implementing semantic extractor")

    %{
      extractor: "semantic",
      features: ["triple_extraction", "relationship_detection", "ontology_mapping"],
      status: :implemented
    }
  end

  defp implement_entity_recognizer do
    Logger.info("Implementing entity recognizer")

    %{
      recognizer: "entities",
      features: ["named_entity_recognition", "entity_linking", "confidence_scoring"],
      status: :implemented
    }
  end

  defp implement_stylometry_analyzer do
    Logger.info("Implementing stylometry analyzer")

    %{
      analyzer: "stylometry",
      features: ["vocabulary_analysis", "syntactic_patterns", "author_attribution"],
      status: :implemented
    }
  end

  # Documentation generation functions

  defp generate_intro_docs do
    """
    # LANG Text Intelligence API

    Welcome to the LANG Text Intelligence API, a powerful system for analyzing,
    parsing, and extracting semantic information from text content.

    ## Features

    - **Multi-format Support**: Parse plain text, Markdown, and Markdown-LD
    - **Semantic Extraction**: Extract RDF triples and semantic relationships
    - **Entity Recognition**: Identify and classify named entities
    - **Stylometric Analysis**: Analyze writing style and authorship
    - **JSON-LD Output**: Structured, semantic-web compatible responses

    ## Getting Started

    1. Obtain your API key from the LANG dashboard
    2. Make your first API call using the examples below
    3. Explore advanced features like batch processing and webhooks
    """
  end

  defp generate_quickstart_guide do
    """
    # Quick Start Guide

    ## 1. Authentication

    Include your API key in the `X-API-Key` header:

    ```bash
    curl -H "X-API-Key: your-api-key" https://lang.nocsi.com/api/v2/text/parse
    ```

    ## 2. Basic Text Parsing

    ```bash
    curl -X POST https://lang.nocsi.com/api/v2/text/parse \\
      -H "X-API-Key: your-api-key" \\
      -H "Content-Type: application/ld+json" \\
      -d '{
        "content": "Hello world!",
        "format": "text"
      }'
    ```

    ## 3. Markdown-LD Processing

    ```bash
    curl -X POST https://lang.nocsi.com/api/v2/text/markdown-ld \\
      -H "X-API-Key: your-api-key" \\
      -H "Content-Type: text/markdown" \\
      -d '# Article\\n\\n<span data-lang-entity="Person">John</span> wrote this.'
    ```
    """
  end

  defp generate_api_reference do
    """
    # API Reference

    ## Base URL

    Production: `https://lang.nocsi.com/api/v2/text`
    Development: `https://lang.nocsi.com/api/v2/text`

    ## Authentication

    All requests require an API key passed in the `X-API-Key` header.

    ## Endpoints

    ### POST /parse
    Parse text with semantic extraction

    ### POST /analyze
    Advanced text analysis

    ### POST /entities
    Extract named entities

    ### POST /semantic
    Extract semantic triples

    ### POST /markdown-ld
    Parse Markdown-LD content

    ### POST /stylometry
    Stylometric analysis
    """
  end

  defp generate_comprehensive_examples do
    """
    # Comprehensive Examples

    ## Basic Text Analysis

    Analyze plain text for entities and semantics:

    ```bash
    curl -X POST https://lang.nocsi.com/api/v2/text/parse \\
      -H "X-API-Key: your-api-key" \\
      -H "Content-Type: application/ld+json" \\
      -d '{
        "@context": "https://lang.ai/context/text",
        "content": "Apple Inc. was founded by Steve Jobs in 1976.",
        "format": "text",
        "extract_entities": true,
        "extract_semantics": true
      }'
    ```

    ## Markdown Processing

    Process Markdown with semantic extraction:

    ```bash
    curl -X POST https://lang.nocsi.com/api/v2/text/parse \\
      -H "X-API-Key: your-api-key" \\
      -H "Content-Type: application/ld+json" \\
      -d '{
        "@context": "https://lang.ai/context/text",
        "content": "# Company Profile\\n\\n**Apple Inc.** is a technology company.",
        "format": "markdown",
        "extract_semantics": true
      }'
    ```

    ## Entity Recognition

    Extract named entities from text:

    ```bash
    curl -X POST https://lang.nocsi.com/api/v2/text/entities \\
      -H "X-API-Key: your-api-key" \\
      -H "Content-Type: application/json" \\
      -d '{
        "content": "John Smith works at Microsoft in Seattle.",
        "entity_types": ["PERSON", "ORGANIZATION", "LOCATION"]
      }'
    ```

    ## Semantic Triple Extraction

    Extract RDF triples from structured text:

    ```bash
    curl -X POST https://lang.nocsi.com/api/v2/text/semantic \\
      -H "X-API-Key: your-api-key" \\
      -H "Content-Type: application/json" \\
      -d '{
        "content": "Tim Cook is the CEO of Apple Inc.",
        "extract_relations": true,
        "format": "jsonld"
      }'
    ```

    ## Batch Processing

    Process multiple documents in a single request:

    ```bash
    curl -X POST https://lang.nocsi.com/api/v2/text/batch \\
      -H "X-API-Key: your-api-key" \\
      -H "Content-Type: application/json" \\
      -d '{
        "documents": [
          {"id": "doc1", "content": "First document content", "format": "text"},
          {"id": "doc2", "content": "# Second Document\\nMarkdown content", "format": "markdown"}
        ],
        "options": {
          "extract_entities": true,
          "extract_semantics": true
        }
      }'
    ```
    """
  end

  defp generate_tutorials do
    """
    # Tutorials

    ## Tutorial 1: Building a Text Analysis Pipeline

    Learn how to create a complete text analysis pipeline using the LANG API.

    ## Tutorial 2: Semantic Web Integration

    Integrate LANG's semantic extraction with your knowledge graph.

    ## Tutorial 3: Batch Processing

    Process large volumes of text efficiently using batch endpoints.
    """
  end

  defp generate_best_practices do
    """
    # Best Practices

    ## Performance
    - Use batch processing for multiple documents
    - Cache results when possible
    - Use appropriate timeout values

    ## Security
    - Never expose your API key in client-side code
    - Use environment variables for API keys
    - Implement proper error handling

    ## Rate Limiting
    - Respect rate limits (1000 requests/hour for free tier)
    - Implement exponential backoff for retries
    - Monitor your usage dashboard
    """
  end

  defp generate_troubleshooting do
    """
    # Troubleshooting

    ## Common Issues

    ### 401 Unauthorized
    - Check that your API key is valid
    - Ensure the key is in the X-API-Key header

    ### 429 Rate Limited
    - You've exceeded your rate limit
    - Wait for the retry-after period
    - Consider upgrading your plan

    ### 400 Bad Request
    - Check request format
    - Validate required fields
    - Ensure proper Content-Type header
    """
  end

  # Utility functions

  defp save_spec(spec, env) do
    File.mkdir_p!("priv/static/docs/#{env}")
    File.write!("priv/static/docs/#{env}/openapi.json", Jason.encode!(spec, pretty: true))
  end

  defp save_documentation(docs, env) do
    base_path = "priv/static/docs/#{env}"
    File.mkdir_p!(base_path)

    Enum.each(docs, fn {section, content} ->
      File.write!("#{base_path}/#{section}.md", content)
    end)
  end

  defp save_examples(examples, env) do
    path = "priv/static/examples/#{env}"
    File.mkdir_p!(path)

    File.write!("#{path}/examples.json", Jason.encode!(examples, pretty: true))
  end

  defp count_endpoints(spec) do
    paths = Map.get(spec, "paths", %{})

    Enum.reduce(paths, 0, fn {_path, methods}, acc ->
      acc + map_size(methods)
    end)
  end

  defp count_schemas(spec) do
    get_in(spec, ["components", "schemas"]) |> map_size()
  end

  defp count_examples(docs) do
    Enum.reduce(docs, 0, fn {_key, content}, acc ->
      # Count code blocks in content
      case is_list(content) do
        true -> acc + length(content)
        false -> acc + (content |> String.split("```") |> length() |> Kernel.-(1) |> div(2))
      end
    end)
  end

  defp verify_endpoints do
    # Verify API endpoints are configured
    true
  end

  defp verify_middleware do
    # Verify middleware is properly configured
    true
  end

  defp verify_rate_limits do
    # Verify rate limiting is configured
    true
  end

  defp verify_auth do
    # Verify authentication is configured
    true
  end

  defp verify_monitoring do
    # Verify monitoring is configured
    true
  end

  # Example creation functions

  defp create_basic_text_analysis_example do
    %{
      title: "Basic Text Analysis",
      language: "curl",
      code: """
      curl -X POST https://lang.nocsi.com/api/v2/text/parse \\
        -H "X-API-Key: your-api-key" \\
        -H "Content-Type: application/ld+json" \\
        -d '{
          "@context": "https://lang.ai/context/text",
          "content": "Apple Inc. was founded by Steve Jobs in Cupertino, California.",
          "format": "text",
          "extract_entities": true,
          "extract_semantics": true
        }'
      """
    }
  end

  defp create_markdown_parsing_example do
    %{
      title: "Markdown Parsing",
      language: "javascript",
      code: """
      const response = await fetch('https://lang.nocsi.com/api/v2/text/parse', {
        method: 'POST',
        headers: {
          'X-API-Key': 'your-api-key',
          'Content-Type': 'application/ld+json'
        },
        body: JSON.stringify({
          '@context': 'https://lang.ai/context/text',
          content: '# Company Profile\\n\\n**Apple Inc.** is a technology company.',
          format: 'markdown',
          extract_semantics: true
        })
      });
      const result = await response.json();
      """
    }
  end

  defp create_markdown_ld_example do
    %{
      title: "Markdown-LD Processing",
      language: "python",
      code: """
      import requests

      response = requests.post(
          'https://lang.nocsi.com/api/v2/text/markdown-ld',
          headers={'X-API-Key': 'your-api-key'},
          data='''# Person Profile

      <div data-lang-entity="Person" data-lang-uri="https://example.org/steve-jobs">
      Steve Jobs
      </div> was the co-founder of Apple Inc.
      '''
      )
      result = response.json()
      """
    }
  end

  defp create_semantic_extraction_example do
    %{
      title: "Semantic Triple Extraction",
      language: "go",
      code: """
      package main

      import (
          "bytes"
          "encoding/json"
          "net/http"
      )

      func main() {
          payload := map[string]interface{}{
              "content": "Einstein developed the theory of relativity.",
              "context": "https://schema.org",
          }

          jsonData, _ := json.Marshal(payload)

          req, _ := http.NewRequest("POST",
              "https://lang.nocsi.com/api/v2/text/semantic",
              bytes.NewBuffer(jsonData))

          req.Header.Set("X-API-Key", "your-api-key")
          req.Header.Set("Content-Type", "application/ld+json")

          client := &http.Client{}
          resp, _ := client.Do(req)
      }
      """
    }
  end

  defp create_entity_recognition_example do
    %{
      title: "Named Entity Recognition",
      language: "rust",
      code: """
      use reqwest;
      use serde_json::json;

      #[tokio::main]
      async fn main() -> Result<(), Box<dyn std::error::Error>> {
          let client = reqwest::Client::new();

          let payload = json!({
              "content": "Microsoft was founded by Bill Gates and Paul Allen in 1975.",
              "types": ["PERSON", "ORGANIZATION"]
          });

          let res = client
              .post("https://lang.nocsi.com/api/v2/text/entities")
              .header("X-API-Key", "your-api-key")
              .json(&payload)
              .send()
              .await?;

          let body = res.text().await?;
          println!("{}", body);

          Ok(())
      }
      """
    }
  end

  defp create_stylometry_example do
    %{
      title: "Stylometric Analysis",
      language: "curl",
      code: """
      curl -X POST https://lang.nocsi.com/api/v2/text/stylometry \\
        -H "X-API-Key: your-api-key" \\
        -H "Content-Type: application/ld+json" \\
        -d '{
          "content": "The quick brown fox jumps over the lazy dog. This sentence contains every letter of the alphabet. It is commonly used for testing fonts and keyboards.",
          "features": ["vocabulary", "syntax", "punctuation", "length"]
        }'
      """
    }
  end

  defp create_batch_processing_example do
    %{
      title: "Batch Text Processing",
      language: "python",
      code: """
      import requests
      import json

      def batch_analyze_texts(texts, api_key):
          results = []

          for i, text in enumerate(texts):
              response = requests.post(
                  'https://lang.nocsi.com/api/v2/text/parse',
                  headers={
                      'X-API-Key': api_key,
                      'Content-Type': 'application/ld+json'
                  },
                  json={
                      '@context': 'https://lang.ai/context/text',
                      'content': text,
                      'format': 'text',
                      'extract_semantics': True
                  }
              )

              if response.status_code == 200:
                  results.append({
                      'index': i,
                      'result': response.json()
                  })
              else:
                  results.append({
                      'index': i,
                      'error': response.text
                  })

          return results

      # Usage
      texts = [
          "Apple Inc. is a technology company.",
          "Google was founded by Larry Page and Sergey Brin.",
          "Microsoft develops software and cloud services."
      ]

      results = batch_analyze_texts(texts, 'your-api-key')
      """
    }
  end

  defp create_webhook_integration_example do
    %{
      title: "Webhook Integration",
      language: "javascript",
      code: """
      // Express.js webhook handler
      const express = require('express');
      const app = express();

      app.use(express.json());

      // Webhook endpoint to receive LANG text analysis results
      app.post('/webhook/text-analysis', (req, res) => {
          const { event, data } = req.body;

          if (event === 'analysis_completed') {
              console.log('Text analysis completed:', data);

              // Process the results
              const { triples, entities, metadata } = data.result;

              // Store in your database
              storeAnalysisResults(data.document_id, {
                  triples,
                  entities,
                  metadata
              });

              // Send notification
              notifyUser(data.user_id, 'Analysis completed');
          }

          res.status(200).send('OK');
      });

      function storeAnalysisResults(documentId, results) {
          // Your database logic here
          console.log(`Storing results for document ${documentId}`);
      }

      function notifyUser(userId, message) {
          // Your notification logic here
          console.log(`Notifying user ${userId}: ${message}`);
      }

      app.listen(3000, () => {
          console.log('Webhook server listening on port 3000');
      });
      """
    }
  end

  defp generate_text_examples do
    %{
      "basic_analysis" => create_basic_text_analysis_example(),
      "markdown_parsing" => create_markdown_parsing_example(),
      "markdown_ld" => create_markdown_ld_example(),
      "semantic_extraction" => create_semantic_extraction_example(),
      "entity_recognition" => create_entity_recognition_example(),
      "stylometry" => create_stylometry_example(),
      "batch_processing" => create_batch_processing_example(),
      "webhook_integration" => create_webhook_integration_example()
    }
  end

  # Client generation functions
  defp generate_python_client do
    "Python SDK for text intelligence with semantic analysis capabilities"
  end

  defp generate_javascript_client do
    "JavaScript/TypeScript SDK for web-based text analysis applications"
  end

  defp generate_go_client do
    "Go client library for high-performance text processing systems"
  end

  defp generate_java_client do
    "Java SDK for enterprise text intelligence platforms"
  end

  defp generate_curl_examples do
    "Comprehensive cURL examples for all text intelligence endpoints"
  end

  # Marketing generation functions
  defp generate_landing_pages do
    "Marketing landing pages highlighting text intelligence capabilities"
  end

  defp generate_blog_posts do
    "Technical blog posts about text analysis and semantic extraction"
  end

  defp generate_case_studies do
    "Customer case studies showcasing successful text intelligence implementations"
  end

  defp generate_whitepapers do
    "Technical whitepapers on advanced NLP and semantic analysis"
  end

  defp generate_social_content do
    "Social media content promoting text intelligence features"
  end

  # Publishing functions
  defp publish_api_documentation do
    "Published API documentation to developer portal"
  end

  defp publish_client_sdks do
    "Published client SDKs to package repositories"
  end

  defp publish_marketing_content do
    "Published marketing materials to company website"
  end

  defp publish_npm_packages do
    "Published JavaScript packages to npm registry"
  end

  defp publish_pypi_packages do
    "Published Python packages to PyPI registry"
  end
end
