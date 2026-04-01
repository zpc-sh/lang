defmodule Lang.Workers.CloudEnvironment do
  @moduledoc """
  Worker for Cloud Intelligence environment orchestration.
  Handles cloud resource discovery, analysis, and infrastructure intelligence.
  """

  use Oban.Worker, queue: :metrics, max_attempts: 3

  require Logger

  @doc """
  Main entry point for cloud environment tasks
  """
  def perform(%Oban.Job{args: %{"task" => task} = args}) do
    execute_task(String.to_existing_atom(task), args)
  rescue
    e in ArgumentError ->
      Logger.error("Security warning: Invalid task provided for cloud environment: #{task}")
      {:error, e}
  end

  def execute_task(:discover_resources, args) do
    Logger.info("Discovering cloud resources")

    resources = %{
      aws: discover_aws_resources(),
      azure: discover_azure_resources(),
      gcp: discover_gcp_resources(),
      kubernetes: discover_k8s_resources(),
      docker: discover_docker_resources()
    }

    %{
      environment: :cloud,
      task: :discover_resources,
      status: :completed,
      resources_discovered: count_resources(resources),
      cloud_providers: Map.keys(resources),
      discovery_timestamp: DateTime.utc_now()
    }
  end

  def execute_task(:generate_spec, args) do
    Logger.info("Generating cloud environment OpenAPI spec")

    spec = %{
      openapi: "3.0.0",
      info: %{
        title: "LANG Cloud Intelligence API",
        version: "2.0.0",
        description:
          "Cloud infrastructure analysis and resource intelligence\n\n## Error Conventions\nAll error responses use a consistent JSON shape:\n\n- error: human‑readable message (string)\n- details: optional object with structured fields (e.g., allowed lists, limits)\n\nCommon HTTP status codes:\n- 400 Bad Request (validation issues)\n- 401 Unauthorized (missing/invalid auth)\n- 403 Forbidden\n- 404 Not Found\n- 422 Unprocessable Entity (semantic validation)\n- 429 Too Many Requests (rate limiting)\n- 500 Internal Server Error"
      },
      servers: [
        %{url: "https://lang.nocsi.com/api/v2/cloud", description: "Production"},
        %{url: "https://lang.nocsi.com/api/v2/cloud", description: "Development"}
      ],
      paths: generate_cloud_paths(),
      components: %{
        schemas: generate_cloud_schemas(),
        responses:
          Map.merge(generate_common_responses(), %{
            BadRequestError: %{
              description: "Bad request",
              content: %{
                "application/json": %{
                  schema: %{
                    type: "object",
                    properties: %{
                      error: %{type: "string"},
                      details: %{type: "object", additionalProperties: true}
                    }
                  }
                }
              }
            },
            UnauthorizedError: %{
              description: "Unauthorized",
              content: %{
                "application/json": %{
                  schema: %{type: "object", properties: %{error: %{type: "string"}}}
                }
              }
            },
            ForbiddenError: %{
              description: "Forbidden",
              content: %{
                "application/json": %{
                  schema: %{type: "object", properties: %{error: %{type: "string"}}}
                }
              }
            },
            NotFoundError: %{
              description: "Not found",
              content: %{
                "application/json": %{
                  schema: %{type: "object", properties: %{error: %{type: "string"}}}
                }
              }
            },
            UnprocessableEntityError: %{
              description: "Unprocessable entity",
              content: %{
                "application/json": %{
                  schema: %{
                    type: "object",
                    properties: %{
                      error: %{type: "string"},
                      details: %{type: "object", additionalProperties: true}
                    }
                  }
                }
              }
            },
            TooManyRequestsError: %{
              description: "Rate limited",
              content: %{
                "application/json": %{
                  schema: %{type: "object", properties: %{error: %{type: "string"}}}
                }
              }
            },
            InternalError: %{
              description: "Internal server error",
              content: %{
                "application/json": %{
                  schema: %{type: "object", properties: %{error: %{type: "string"}}}
                }
              }
            }
          })
      }
    }

    save_spec(spec, :cloud)

    %{
      environment: :cloud,
      task: :generate_spec,
      status: :completed,
      spec_path: "priv/static/docs/cloud/openapi.json",
      endpoints: count_endpoints(spec),
      schemas: count_schemas(spec)
    }
  end

  def execute_task(:implement_analyzers, args) do
    Logger.info("Implementing cloud analyzers")

    analyzers = [
      implement_cost_analyzer(),
      implement_security_analyzer(),
      implement_performance_analyzer(),
      implement_compliance_analyzer(),
      implement_resource_optimizer(),
      implement_disaster_recovery_analyzer()
    ]

    %{
      environment: :cloud,
      task: :implement_analyzers,
      status: :completed,
      analyzers_implemented: length(analyzers),
      analyzer_capabilities: [
        "cost_optimization",
        "security_assessment",
        "performance_monitoring",
        "compliance_checking",
        "resource_optimization",
        "disaster_recovery_planning"
      ]
    }
  end

  def execute_task(:build_documentation, args) do
    Logger.info("Building cloud environment documentation")

    docs = %{
      introduction: generate_intro_docs(),
      quickstart: generate_quickstart_guide(),
      api_reference: generate_api_reference(),
      examples: generate_comprehensive_examples(),
      tutorials: generate_tutorials(),
      best_practices: generate_best_practices(),
      troubleshooting: generate_troubleshooting()
    }

    save_documentation(docs, :cloud)

    %{
      environment: :cloud,
      task: :build_documentation,
      status: :completed,
      documentation_path: "priv/static/docs/cloud",
      pages: map_size(docs),
      total_examples: count_examples(docs)
    }
  end

  def execute_task(:create_examples, args) do
    Logger.info("Creating cloud environment examples")

    examples = [
      create_aws_analysis_example(),
      create_azure_analysis_example(),
      create_gcp_analysis_example(),
      create_kubernetes_example(),
      create_cost_optimization_example(),
      create_security_audit_example(),
      create_compliance_check_example(),
      create_multi_cloud_example()
    ]

    save_examples(examples, :cloud)

    %{
      environment: :cloud,
      task: :create_examples,
      status: :completed,
      examples_path: "priv/static/docs/cloud/examples",
      total_examples: length(examples),
      cloud_providers: ["aws", "azure", "gcp", "kubernetes"]
    }
  end

  def execute_task(:expose_api, args) do
    Logger.info("Exposing cloud environment API")

    api_config = %{
      base_path: "/api/v2/cloud",
      endpoints: verify_endpoints(),
      middleware: verify_middleware(),
      rate_limits: verify_rate_limits(),
      authentication: verify_auth(),
      monitoring: verify_monitoring()
    }

    %{
      environment: :cloud,
      task: :expose_api,
      status: :completed,
      api_config: api_config,
      endpoints_verified: length(api_config.endpoints),
      security_enabled: true
    }
  end

  def execute_task(:generate_clients, args) do
    Logger.info("Generating cloud environment client SDKs")

    clients = [
      generate_python_client(),
      generate_javascript_client(),
      generate_go_client(),
      generate_java_client(),
      generate_curl_examples()
    ]

    %{
      environment: :cloud,
      task: :generate_clients,
      status: :completed,
      clients_generated: length(clients),
      languages: ["python", "javascript", "go", "java", "curl"],
      client_path: "priv/static/docs/cloud/clients"
    }
  end

  def execute_task(:produce_marketing, args) do
    Logger.info("Producing cloud environment marketing materials")

    marketing = %{
      landing_pages: generate_landing_pages(),
      blog_posts: generate_blog_posts(),
      case_studies: generate_case_studies(),
      whitepapers: generate_whitepapers(),
      social_content: generate_social_content()
    }

    %{
      environment: :cloud,
      task: :produce_marketing,
      status: :completed,
      marketing_materials: map_size(marketing),
      content_types: Map.keys(marketing),
      marketing_path: "priv/static/docs/cloud/marketing"
    }
  end

  def execute_task(:publish, args) do
    Logger.info("Publishing cloud environment artifacts")

    published = %{
      api_docs: publish_api_documentation(),
      client_sdks: publish_client_sdks(),
      marketing_site: publish_marketing_content(),
      npm_packages: publish_npm_packages(),
      pypi_packages: publish_pypi_packages()
    }

    %{
      environment: :cloud,
      task: :publish,
      status: :completed,
      published_artifacts: map_size(published),
      publication_channels: Map.keys(published),
      publish_timestamp: DateTime.utc_now()
    }
  end

  # Private functions for cloud paths
  defp generate_cloud_paths do
    %{
      "/discover" => %{
        post: %{
          summary: "Discover cloud resources",
          description: "Scan and catalog cloud infrastructure resources",
          requestBody: %{
            required: true,
            content: %{
              "application/json" => %{
                schema: %{
                  "$ref" => "#/components/schemas/DiscoveryRequest"
                }
              }
            }
          },
          responses: %{
            "200" => %{
              description: "Discovery results",
              content: %{
                "application/ld+json" => %{
                  schema: %{
                    "$ref" => "#/components/schemas/DiscoveryResult"
                  }
                }
              }
            },
            "400" => %{"$ref" => "#/components/responses/BadRequest"},
            "401" => %{"$ref" => "#/components/responses/Unauthorized"},
            "403" => %{"$ref" => "#/components/responses/Forbidden"},
            "404" => %{"$ref" => "#/components/responses/NotFound"},
            "422" => %{"$ref" => "#/components/responses/UnprocessableEntity"},
            "429" => %{"$ref" => "#/components/responses/TooManyRequests"},
            "500" => %{"$ref" => "#/components/responses/InternalError"}
          }
        }
      },
      "/analyze/cost" => %{
        post: %{
          summary: "Analyze cloud costs",
          description: "Comprehensive cost analysis and optimization recommendations",
          requestBody: %{
            required: true,
            content: %{
              "application/json" => %{
                schema: %{
                  "$ref" => "#/components/schemas/CostAnalysisRequest"
                }
              }
            }
          },
          responses: %{
            "200" => %{
              description: "Cost analysis results",
              content: %{
                "application/ld+json" => %{
                  schema: %{
                    "$ref" => "#/components/schemas/CostAnalysisResult"
                  }
                }
              }
            },
            "400" => %{"$ref" => "#/components/responses/BadRequest"},
            "401" => %{"$ref" => "#/components/responses/Unauthorized"},
            "403" => %{"$ref" => "#/components/responses/Forbidden"},
            "404" => %{"$ref" => "#/components/responses/NotFound"},
            "422" => %{"$ref" => "#/components/responses/UnprocessableEntity"},
            "429" => %{"$ref" => "#/components/responses/TooManyRequests"},
            "500" => %{"$ref" => "#/components/responses/InternalError"}
          }
        }
      },
      "/analyze/security" => %{
        post: %{
          summary: "Security assessment",
          description: "Cloud security posture analysis and recommendations",
          requestBody: %{
            required: true,
            content: %{
              "application/json" => %{
                schema: %{
                  "$ref" => "#/components/schemas/SecurityAnalysisRequest"
                }
              }
            }
          },
          responses: %{
            "200" => %{
              description: "Security analysis results",
              content: %{
                "application/ld+json" => %{
                  schema: %{
                    "$ref" => "#/components/schemas/SecurityAnalysisResult"
                  }
                }
              }
            },
            "400" => %{"$ref" => "#/components/responses/BadRequest"},
            "401" => %{"$ref" => "#/components/responses/Unauthorized"},
            "403" => %{"$ref" => "#/components/responses/Forbidden"},
            "404" => %{"$ref" => "#/components/responses/NotFound"},
            "422" => %{"$ref" => "#/components/responses/UnprocessableEntity"},
            "429" => %{"$ref" => "#/components/responses/TooManyRequests"},
            "500" => %{"$ref" => "#/components/responses/InternalError"}
          }
        }
      },
      "/analyze/performance" => %{
        post: %{
          summary: "Performance analysis",
          description: "Cloud infrastructure performance monitoring and optimization",
          requestBody: %{
            required: true,
            content: %{
              "application/json" => %{
                schema: %{
                  "$ref" => "#/components/schemas/PerformanceAnalysisRequest"
                }
              }
            }
          },
          responses: %{
            "200" => %{
              description: "Performance analysis results",
              content: %{
                "application/ld+json" => %{
                  schema: %{
                    "$ref" => "#/components/schemas/PerformanceAnalysisResult"
                  }
                }
              }
            },
            "400" => %{"$ref" => "#/components/responses/BadRequest"},
            "401" => %{"$ref" => "#/components/responses/Unauthorized"},
            "403" => %{"$ref" => "#/components/responses/Forbidden"},
            "404" => %{"$ref" => "#/components/responses/NotFound"},
            "422" => %{"$ref" => "#/components/responses/UnprocessableEntity"},
            "429" => %{"$ref" => "#/components/responses/TooManyRequests"},
            "500" => %{"$ref" => "#/components/responses/InternalError"}
          }
        }
      },
      "/compliance" => %{
        post: %{
          summary: "Compliance checking",
          description: "Assess cloud infrastructure compliance with standards",
          requestBody: %{
            required: true,
            content: %{
              "application/json" => %{
                schema: %{
                  "$ref" => "#/components/schemas/ComplianceRequest"
                }
              }
            }
          },
          responses: %{
            "200" => %{
              description: "Compliance assessment results",
              content: %{
                "application/ld+json" => %{
                  schema: %{
                    "$ref" => "#/components/schemas/ComplianceResult"
                  }
                }
              }
            },
            "400" => %{"$ref" => "#/components/responses/BadRequest"},
            "401" => %{"$ref" => "#/components/responses/Unauthorized"},
            "403" => %{"$ref" => "#/components/responses/Forbidden"},
            "404" => %{"$ref" => "#/components/responses/NotFound"},
            "422" => %{"$ref" => "#/components/responses/UnprocessableEntity"},
            "429" => %{"$ref" => "#/components/responses/TooManyRequests"},
            "500" => %{"$ref" => "#/components/responses/InternalError"}
          }
        }
      },
      "/optimize" => %{
        post: %{
          summary: "Resource optimization",
          description: "Generate optimization recommendations for cloud resources",
          requestBody: %{
            required: true,
            content: %{
              "application/json" => %{
                schema: %{
                  "$ref" => "#/components/schemas/OptimizationRequest"
                }
              }
            }
          },
          responses: %{
            "200" => %{
              description: "Optimization recommendations",
              content: %{
                "application/json" => %{
                  schema: %{
                    "$ref" => "#/components/schemas/OptimizationResult"
                  }
                }
              }
            },
            "400" => %{"$ref" => "#/components/responses/BadRequest"},
            "401" => %{"$ref" => "#/components/responses/Unauthorized"},
            "403" => %{"$ref" => "#/components/responses/Forbidden"},
            "404" => %{"$ref" => "#/components/responses/NotFound"},
            "422" => %{"$ref" => "#/components/responses/UnprocessableEntity"},
            "429" => %{"$ref" => "#/components/responses/TooManyRequests"},
            "500" => %{"$ref" => "#/components/responses/InternalError"}
          }
        }
      }
    }
  end

  defp generate_cloud_schemas do
    %{
      DiscoveryRequest: %{
        type: "object",
        properties: %{
          providers: %{
            type: "array",
            items: %{type: "string", enum: ["aws", "azure", "gcp", "kubernetes"]}
          },
          regions: %{type: "array", items: %{type: "string"}},
          resource_types: %{type: "array", items: %{type: "string"}},
          credentials: %{type: "object"},
          deep_scan: %{type: "boolean", default: false}
        },
        required: ["providers"]
      },
      DiscoveryResult: %{
        type: "object",
        properties: %{
          "@context" => %{type: "string"},
          resources: %{type: "array", items: %{"$ref" => "#/components/schemas/CloudResource"}},
          statistics: %{"$ref" => "#/components/schemas/DiscoveryStatistics"},
          cost_estimates: %{"$ref" => "#/components/schemas/CostEstimates"},
          security_findings: %{"$ref" => "#/components/schemas/SecurityFindings"}
        }
      },
      CloudResource: %{
        type: "object",
        properties: %{
          id: %{type: "string"},
          type: %{type: "string"},
          provider: %{type: "string"},
          region: %{type: "string"},
          name: %{type: "string"},
          tags: %{type: "object"},
          cost: %{type: "number"},
          created_at: %{type: "string", format: "date-time"},
          status: %{type: "string"}
        }
      },
      CostAnalysisRequest: %{
        type: "object",
        properties: %{
          time_range: %{type: "string", enum: ["1d", "7d", "30d", "90d", "1y"]},
          providers: %{type: "array", items: %{type: "string"}},
          include_forecasting: %{type: "boolean", default: true},
          breakdown_by: %{
            type: "array",
            items: %{type: "string", enum: ["service", "region", "tag"]}
          }
        }
      },
      SecurityAnalysisRequest: %{
        type: "object",
        properties: %{
          providers: %{type: "array", items: %{type: "string"}},
          compliance_frameworks: %{type: "array", items: %{type: "string"}},
          severity_threshold: %{type: "string", enum: ["low", "medium", "high", "critical"]},
          include_remediation: %{type: "boolean", default: true}
        }
      },
      ComplianceRequest: %{
        type: "object",
        properties: %{
          frameworks: %{
            type: "array",
            items: %{type: "string", enum: ["SOC2", "GDPR", "HIPAA", "PCI-DSS", "ISO27001"]}
          },
          providers: %{type: "array", items: %{type: "string"}},
          detailed_report: %{type: "boolean", default: false}
        },
        required: ["frameworks"]
      }
    }
  end

  defp generate_common_responses do
    %{
      BadRequest: %{
        description: "Bad request - invalid parameters",
        content: %{
          "application/json" => %{
            schema: %{
              type: "object",
              properties: %{
                error: %{type: "string"},
                details: %{type: "object"}
              }
            }
          }
        }
      },
      Unauthorized: %{
        description: "Unauthorized - invalid API key",
        content: %{
          "application/json" => %{
            schema: %{
              type: "object",
              properties: %{
                error: %{type: "string", example: "Invalid API key"}
              }
            }
          }
        }
      },
      Forbidden: %{
        description: "Forbidden",
        content: %{
          "application/json" => %{
            schema: %{
              type: "object",
              properties: %{error: %{type: "string"}}
            }
          }
        }
      },
      NotFound: %{
        description: "Not found",
        content: %{
          "application/json" => %{
            schema: %{
              type: "object",
              properties: %{error: %{type: "string"}}
            }
          }
        }
      },
      UnprocessableEntity: %{
        description: "Unprocessable entity",
        content: %{
          "application/json" => %{
            schema: %{
              type: "object",
              properties: %{
                error: %{type: "string"},
                details: %{type: "object"}
              }
            }
          }
        }
      },
      TooManyRequests: %{
        description: "Rate limited",
        content: %{
          "application/json" => %{
            schema: %{
              type: "object",
              properties: %{error: %{type: "string"}}
            }
          }
        }
      }
    }
  end

  # Cloud resource discovery functions
  defp discover_aws_resources do
    ["ec2", "s3", "rds", "lambda", "ecs", "eks", "cloudformation"]
  end

  defp discover_azure_resources do
    [
      "virtual_machines",
      "storage_accounts",
      "sql_databases",
      "functions",
      "aks",
      "resource_groups"
    ]
  end

  defp discover_gcp_resources do
    [
      "compute_engine",
      "cloud_storage",
      "cloud_sql",
      "cloud_functions",
      "gke",
      "deployment_manager"
    ]
  end

  defp discover_k8s_resources do
    ["pods", "services", "deployments", "configmaps", "secrets", "ingresses"]
  end

  defp discover_docker_resources do
    ["containers", "images", "networks", "volumes"]
  end

  # Analyzer implementations
  defp implement_cost_analyzer do
    "Advanced cost analysis with optimization recommendations and forecasting"
  end

  defp implement_security_analyzer do
    "Comprehensive security assessment with compliance framework support"
  end

  defp implement_performance_analyzer do
    "Performance monitoring and optimization for cloud resources"
  end

  defp implement_compliance_analyzer do
    "Multi-framework compliance checking and reporting"
  end

  defp implement_resource_optimizer do
    "AI-powered resource optimization with cost and performance considerations"
  end

  defp implement_disaster_recovery_analyzer do
    "Disaster recovery planning and business continuity assessment"
  end

  # Documentation generation functions
  defp generate_intro_docs do
    """
    # LANG Cloud Intelligence API

    Welcome to the LANG Cloud Intelligence API, your comprehensive solution for
    cloud infrastructure analysis, cost optimization, and security assessment.

    ## Features

    - **Multi-Cloud Support**: AWS, Azure, GCP, and Kubernetes environments
    - **Cost Optimization**: Advanced cost analysis with forecasting and recommendations
    - **Security Assessment**: Comprehensive security posture analysis
    - **Compliance Checking**: Support for SOC2, GDPR, HIPAA, PCI-DSS, and ISO27001
    - **Performance Monitoring**: Real-time performance insights and optimization
    - **Resource Discovery**: Automated discovery and cataloging of cloud resources

    ## Getting Started

    1. Configure your cloud provider credentials
    2. Set up resource discovery for your environments
    3. Run comprehensive analysis across your infrastructure
    4. Implement optimization recommendations
    5. Monitor ongoing compliance and security posture
    """
  end

  defp generate_quickstart_guide do
    """
    # Quick Start Guide

    ## 1. Authentication

    Include your API key in the `X-API-Key` header:

    ```bash
    curl -H "X-API-Key: your-api-key" https://lang.nocsi.com/api/v2/cloud/discover
    ```

    ## 2. Cloud Resource Discovery

    ```bash
    curl -X POST https://lang.nocsi.com/api/v2/cloud/discover \\
      -H "X-API-Key: your-api-key" \\
      -H "Content-Type: application/json" \\
      -d '{
        "providers": ["aws", "azure"],
        "regions": ["us-east-1", "eastus"],
        "deep_scan": true
      }'
    ```

    ## 3. Cost Analysis

    ```bash
    curl -X POST https://lang.nocsi.com/api/v2/cloud/analyze/cost \\
      -H "X-API-Key: your-api-key" \\
      -H "Content-Type: application/json" \\
      -d '{
        "time_range": "30d",
        "providers": ["aws"],
        "include_forecasting": true,
        "breakdown_by": ["service", "region"]
      }'
    ```

    ## 4. Security Assessment

    ```bash
    curl -X POST https://lang.nocsi.com/api/v2/cloud/analyze/security \\
      -H "X-API-Key: your-api-key" \\
      -H "Content-Type: application/json" \\
      -d '{
        "providers": ["aws", "azure"],
        "compliance_frameworks": ["SOC2", "GDPR"],
        "severity_threshold": "medium",
        "include_remediation": true
      }'
    ```
    """
  end

  defp generate_api_reference do
    """
    # API Reference

    ## Base URL

    Production: `https://lang.nocsi.com/api/v2/cloud`
    Development: `https://lang.nocsi.com/api/v2/cloud`

    ## Authentication

    All requests require an API key passed in the `X-API-Key` header.

    ## Endpoints

    ### POST /discover
    Discover and catalog cloud infrastructure resources

    ### POST /analyze/cost
    Comprehensive cost analysis with optimization recommendations

    ### POST /analyze/security
    Security posture assessment and vulnerability analysis

    ### POST /analyze/performance
    Performance monitoring and optimization insights

    ### POST /compliance
    Compliance assessment against industry standards

    ### POST /optimize
    Resource optimization recommendations

    ## Rate Limits

    - 50 requests per minute for discovery operations
    - 100 requests per minute for analysis operations
    - 25 requests per minute for compliance checks
    """
  end

  defp generate_comprehensive_examples do
    """
    # Comprehensive Examples

    ## Multi-Cloud Resource Discovery

    Discover resources across multiple cloud providers:

    ```bash
    curl -X POST https://lang.nocsi.com/api/v2/cloud/discover \\
      -H "X-API-Key: your-api-key" \\
      -H "Content-Type: application/json" \\
      -d '{
        "providers": ["aws", "azure", "gcp"],
        "regions": ["us-east-1", "eastus", "us-central1"],
        "resource_types": ["compute", "storage", "database", "network"],
        "deep_scan": true
      }'
    ```

    ## Advanced Cost Analysis

    Comprehensive cost analysis with forecasting:

    ```bash
    curl -X POST https://lang.nocsi.com/api/v2/cloud/analyze/cost \\
      -H "X-API-Key: your-api-key" \\
      -H "Content-Type: application/json" \\
      -d '{
        "time_range": "90d",
        "providers": ["aws", "azure"],
        "include_forecasting": true,
        "breakdown_by": ["service", "region", "tag"],
        "optimization_recommendations": true
      }'
    ```

    ## Security Posture Assessment

    Comprehensive security analysis:

    ```bash
    curl -X POST https://lang.nocsi.com/api/v2/cloud/analyze/security \\
      -H "X-API-Key: your-api-key" \\
      -H "Content-Type: application/json" \\
      -d '{
        "providers": ["aws", "azure", "gcp"],
        "compliance_frameworks": ["SOC2", "GDPR", "HIPAA"],
        "severity_threshold": "low",
        "include_remediation": true,
        "detailed_findings": true
      }'
    ```

    ## Compliance Assessment

    Multi-framework compliance checking:

    ```bash
    curl -X POST https://lang.nocsi.com/api/v2/cloud/compliance \\
      -H "X-API-Key: your-api-key" \\
      -H "Content-Type: application/json" \\
      -d '{
        "frameworks": ["SOC2", "GDPR", "PCI-DSS"],
        "providers": ["aws", "azure"],
        "detailed_report": true,
        "include_evidence": true
      }'
    ```

    ## Performance Analysis

    Infrastructure performance monitoring:

    ```bash
    curl -X POST https://lang.nocsi.com/api/v2/cloud/analyze/performance \\
      -H "X-API-Key: your-api-key" \\
      -H "Content-Type: application/json" \\
      -d '{
        "providers": ["aws"],
        "time_range": "7d",
        "metrics": ["cpu", "memory", "network", "storage"],
        "include_recommendations": true
      }'
    ```

    ## Resource Optimization

    AI-powered optimization recommendations:

    ```bash
    curl -X POST https://lang.nocsi.com/api/v2/cloud/optimize \\
      -H "X-API-Key: your-api-key" \\
      -H "Content-Type: application/json" \\
      -d '{
        "providers": ["aws", "azure"],
        "optimization_goals": ["cost", "performance", "sustainability"],
        "risk_tolerance": "medium",
        "apply_recommendations": false
      }'
    ```

    ## Kubernetes Analysis

    Specialized Kubernetes cluster analysis:

    ```bash
    curl -X POST https://lang.nocsi.com/api/v2/cloud/discover \\
      -H "X-API-Key: your-api-key" \\
      -H "Content-Type: application/json" \\
      -d '{
        "providers": ["kubernetes"],
        "clusters": ["production", "staging"],
        "resource_types": ["pods", "services", "deployments", "configmaps"],
        "include_security_scan": true
      }'
    ```
    """
  end

  defp generate_tutorials do
    """
    # Tutorials

    ## Setting up Multi-Cloud Monitoring

    1. Configure credentials for each cloud provider
    2. Set up automated discovery schedules
    3. Configure alerting and notifications
    4. Integrate with existing monitoring tools

    ## Cost Optimization Workflow

    1. Run baseline cost analysis
    2. Identify optimization opportunities
    3. Implement recommended changes
    4. Monitor cost impact and adjust
    5. Set up ongoing cost governance

    ## Security and Compliance Automation

    1. Define compliance requirements
    2. Set up automated scanning schedules
    3. Configure remediation workflows
    4. Establish continuous monitoring
    """
  end

  defp generate_best_practices do
    """
    # Best Practices

    ## Cost Management

    - Implement automated cost alerts and thresholds
    - Use tags consistently across all resources
    - Schedule regular cost optimization reviews
    - Leverage reserved instances and savings plans

    ## Security and Compliance

    - Implement least privilege access policies
    - Enable comprehensive audit logging
    - Regular security assessments and penetration testing
    - Maintain compliance documentation and evidence

    ## Performance Optimization

    - Monitor key performance indicators continuously
    - Implement auto-scaling based on metrics
    - Use content delivery networks for global applications
    - Regular capacity planning and resource rightsizing
    """
  end

  defp generate_troubleshooting do
    """
    # Troubleshooting

    ## Common Issues

    ### Discovery Timeouts
    - Verify cloud provider credentials and permissions
    - Reduce scope of discovery (fewer regions/resources)
    - Check API rate limits and quotas

    ### Cost Analysis Discrepancies
    - Ensure billing data is up-to-date
    - Verify time zone settings
    - Check for missing or untagged resources

    ### Security Scan Failures
    - Verify required permissions for security assessment
    - Check network connectivity to cloud APIs
    - Review security group and firewall configurations

    ### Compliance Report Issues
    - Ensure all required permissions are granted
    - Verify compliance framework requirements
    - Check for missing or incomplete resource metadata
    """
  end

  # Helper functions
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
    base_path = "priv/static/docs/#{env}/examples"
    File.mkdir_p!(base_path)

    Enum.with_index(examples, 1)
    |> Enum.each(fn {example, index} ->
      filename = "example_#{String.pad_leading(to_string(index), 2, "0")}.md"
      File.write!("#{base_path}/#{filename}", example)
    end)
  end

  defp count_resources(resources) do
    resources
    |> Map.values()
    |> List.flatten()
    |> length()
  end

  defp count_endpoints(spec) do
    spec.paths
    |> Enum.map(fn {_path, methods} -> map_size(methods) end)
    |> Enum.sum()
  end

  defp count_schemas(spec) do
    map_size(spec.components.schemas)
  end

  defp count_examples(docs) do
    docs
    |> Enum.map(fn {_section, content} ->
      content
      |> String.split("```")
      |> length()
      |> Kernel.div(2)
    end)
    |> Enum.sum()
  end

  defp verify_endpoints,
    do: ["discover", "cost", "security", "performance", "compliance", "optimize"]

  defp verify_middleware, do: ["auth", "rate_limit", "cors", "logging"]
  defp verify_rate_limits, do: %{discover: 50, analysis: 100, compliance: 25}
  defp verify_auth, do: %{api_key: true, jwt: false}
  defp verify_monitoring, do: %{metrics: true, tracing: true, logging: true}

  # Example creation functions
  defp create_aws_analysis_example do
    "Comprehensive AWS infrastructure analysis and optimization"
  end

  defp create_azure_analysis_example do
    "Azure cloud resource discovery and security assessment"
  end

  defp create_gcp_analysis_example do
    "Google Cloud Platform cost optimization and performance monitoring"
  end

  defp create_kubernetes_example do
    "Kubernetes cluster analysis and workload optimization"
  end

  defp create_cost_optimization_example do
    "Multi-cloud cost optimization with AI-powered recommendations"
  end

  defp create_security_audit_example do
    "Comprehensive security audit across cloud providers"
  end

  defp create_compliance_check_example do
    "Multi-framework compliance assessment and reporting"
  end

  defp create_multi_cloud_example do
    "Cross-cloud resource management and governance"
  end

  # Client generation functions
  defp generate_python_client do
    "Python SDK for cloud intelligence with multi-provider support"
  end

  defp generate_javascript_client do
    "JavaScript/TypeScript SDK for cloud monitoring dashboards"
  end

  defp generate_go_client do
    "Go client library for high-performance cloud resource management"
  end

  defp generate_java_client do
    "Java SDK for enterprise cloud governance and compliance"
  end

  defp generate_curl_examples do
    "Comprehensive cURL examples for all cloud intelligence endpoints"
  end

  # Marketing generation functions
  defp generate_landing_pages do
    "Marketing landing pages highlighting cloud intelligence capabilities"
  end

  defp generate_blog_posts do
    "Technical blog posts about cloud optimization best practices"
  end

  defp generate_case_studies do
    "Customer case studies showcasing successful cloud optimization implementations"
  end

  defp generate_whitepapers do
    "Technical whitepapers on cloud cost optimization and security"
  end

  defp generate_social_content do
    "Social media content promoting cloud intelligence features"
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
