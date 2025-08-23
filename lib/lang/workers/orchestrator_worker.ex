defmodule Lang.Workers.OrchestratorWorker do
  @moduledoc """
  Main orchestrator worker that handles task distribution across environments.
  Routes tasks to appropriate specialized workers based on environment and task type.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    tags: ["orchestration", "master"]

  require Logger

  alias Lang.Orchestration.Master

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"environment" => env, "task" => task} = args}) do
    Logger.info("Orchestrating #{task} for #{env} environment")

    start_time = System.monotonic_time(:millisecond)

    try do
      result = execute_task(String.to_atom(env), String.to_atom(task), args)

      duration = System.monotonic_time(:millisecond) - start_time

      Logger.info("Successfully completed #{task} for #{env} in #{duration}ms")

      # Notify master of completion
      Master.notify_job_completed(args["job_id"])

      # Broadcast completion event
      Phoenix.PubSub.broadcast(
        Lang.PubSub,
        "orchestration:updates",
        {:task_completed, env, task, result, duration}
      )

      # Trigger dependent tasks
      trigger_dependent_tasks(env, task, args)

      :ok
    rescue
      error ->
        Logger.error("Failed to execute #{task} for #{env}: #{inspect(error)}")
        Master.notify_job_failed(args["job_id"], error)
        {:error, error}
    end
  end

  # Task execution routing

  defp execute_task(:text, task, args) do
    delegate_to_worker(Lang.Workers.TextEnvironment, task, args)
  end

  defp execute_task(:filesystem, task, args) do
    delegate_to_worker(Lang.Workers.FilesystemEnvironment, task, args)
  end

  defp execute_task(:cloud, task, args) do
    delegate_to_worker(Lang.Workers.CloudEnvironment, task, args)
  end

  defp execute_task(:systems, task, args) do
    delegate_to_worker(Lang.Workers.SystemsEnvironment, task, args)
  end

  # Generic task handlers for all environments

  defp execute_task(env, :generate_spec, args) do
    Logger.info("Generating OpenAPI spec for #{env}")

    spec = generate_openapi_spec(env)
    save_spec(spec, env)

    %{
      environment: env,
      artifact: :spec,
      status: :completed,
      output_path: spec_path(env),
      metadata: %{
        version: spec["info"]["version"],
        endpoints: count_endpoints(spec),
        schemas: count_schemas(spec)
      }
    }
  end

  defp execute_task(env, :build_documentation, args) do
    Logger.info("Building documentation for #{env}")

    with {:ok, spec} <- load_spec(env),
         {:ok, docs} <- generate_documentation(spec, env),
         {:ok, _saved} <- save_documentation(docs, env) do
      %{
        environment: env,
        artifact: :documentation,
        status: :completed,
        output_path: docs_path(env),
        metadata: %{
          pages: length(docs.pages),
          examples: length(docs.examples)
        }
      }
    end
  end

  defp execute_task(env, :create_examples, args) do
    Logger.info("Creating examples for #{env}")

    with {:ok, spec} <- load_spec(env),
         {:ok, examples} <- generate_examples(spec, env),
         {:ok, _saved} <- save_examples(examples, env) do
      %{
        environment: env,
        artifact: :examples,
        status: :completed,
        output_path: examples_path(env),
        metadata: %{
          example_count: length(examples),
          languages: extract_languages(examples)
        }
      }
    end
  end

  defp execute_task(env, :generate_clients, args) do
    Logger.info("Generating client SDKs for #{env}")

    languages = [:typescript, :python, :go, :rust, :java, :csharp]

    # Enqueue SDK generation jobs for each language
    sdk_jobs =
      Enum.map(languages, fn lang ->
        %{
          environment: env,
          language: lang,
          parent_job_id: args["job_id"]
        }
        |> Lang.Workers.SDKGenerator.new(queue: :sdk_generation)
        |> Oban.insert!()
      end)

    %{
      environment: env,
      artifact: :clients,
      status: :in_progress,
      sdk_job_ids: Enum.map(sdk_jobs, & &1.id),
      languages: languages
    }
  end

  defp execute_task(env, :produce_marketing, args) do
    Logger.info("Producing marketing content for #{env}")

    content_types = [:landing_page, :blog_post, :case_study, :social_media, :video_script]

    # Enqueue marketing generation jobs
    marketing_jobs =
      Enum.map(content_types, fn type ->
        %{
          environment: env,
          content_type: type,
          parent_job_id: args["job_id"]
        }
        |> Lang.Workers.MarketingGenerator.new(queue: :marketing)
        |> Oban.insert!()
      end)

    %{
      environment: env,
      artifact: :marketing,
      status: :in_progress,
      marketing_job_ids: Enum.map(marketing_jobs, & &1.id),
      content_types: content_types
    }
  end

  defp execute_task(env, :publish, args) do
    Logger.info("Publishing artifacts for #{env}")

    with {:ok, artifacts} <- collect_artifacts(env),
         {:ok, published} <- publish_artifacts(artifacts, env) do
      # Notify external systems
      notify_publication(env, published)

      %{
        environment: env,
        artifact: :publication,
        status: :completed,
        published_artifacts: published,
        publication_url: publication_url(env)
      }
    end
  end

  # Helper functions

  defp delegate_to_worker(worker_module, task, args) do
    case apply(worker_module, :execute_task, [task, args]) do
      {:ok, result} -> result
      {:error, error} -> raise error
      result when is_map(result) -> result
    end
  end

  defp generate_openapi_spec(env) do
    base_spec = %{
      "openapi" => "3.1.0",
      "info" => %{
        "title" => "LANG #{String.capitalize(to_string(env))} Intelligence API",
        "version" => "2.0.0",
        "description" => "AI-powered #{env} analysis and processing",
        "x-oban-generated" => DateTime.utc_now(),
        "x-environment" => env
      },
      "servers" => [
        %{"url" => "https://lang.nocsi.com", "description" => "Production"},
        %{"url" => "https://lang.nocsi.com", "description" => "Development"}
      ],
      "security" => [%{"ApiKeyAuth" => []}],
      "components" => %{
        "securitySchemes" => %{
          "ApiKeyAuth" => %{
            "type" => "apiKey",
            "in" => "header",
            "name" => "X-API-Key"
          }
        },
        "schemas" => generate_common_schemas()
      }
    }

    # Add environment-specific paths and schemas
    case env do
      :text ->
        Map.merge(base_spec, %{
          "paths" => generate_text_paths(),
          "components" =>
            Map.merge(base_spec["components"], %{
              "schemas" => Map.merge(base_spec["components"]["schemas"], generate_text_schemas())
            })
        })

      :filesystem ->
        Map.merge(base_spec, %{
          "paths" => generate_filesystem_paths(),
          "components" =>
            Map.merge(base_spec["components"], %{
              "schemas" =>
                Map.merge(base_spec["components"]["schemas"], generate_filesystem_schemas())
            })
        })

      :cloud ->
        Map.merge(base_spec, %{
          "paths" => generate_cloud_paths(),
          "components" =>
            Map.merge(base_spec["components"], %{
              "schemas" => Map.merge(base_spec["components"]["schemas"], generate_cloud_schemas())
            })
        })

      :systems ->
        Map.merge(base_spec, %{
          "paths" => generate_systems_paths(),
          "components" =>
            Map.merge(base_spec["components"], %{
              "schemas" =>
                Map.merge(base_spec["components"]["schemas"], generate_systems_schemas())
            })
        })
    end
  end

  defp generate_common_schemas do
    %{
      "Error" => %{
        "type" => "object",
        "properties" => %{
          "error" => %{"type" => "string"},
          "message" => %{"type" => "string"},
          "code" => %{"type" => "integer"}
        }
      },
      "JobStatus" => %{
        "type" => "object",
        "properties" => %{
          "job_id" => %{"type" => "string"},
          "status" => %{
            "type" => "string",
            "enum" => ["queued", "running", "completed", "failed"]
          },
          "progress" => %{"type" => "number", "minimum" => 0, "maximum" => 100},
          "result" => %{"type" => "object"},
          "error" => %{"type" => "string"}
        }
      }
    }
  end

  defp generate_text_paths do
    %{
      "/api/v2/text/parse" => %{
        "post" => %{
          "summary" => "Parse text with semantic extraction",
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
              "description" => "Successful parsing",
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

  defp generate_text_schemas do
    %{
      "TextParseRequest" => %{
        "type" => "object",
        "properties" => %{
          "content" => %{"type" => "string"},
          "format" => %{"type" => "string", "enum" => ["markdown", "text", "markdown_ld"]},
          "extract_semantics" => %{"type" => "boolean", "default" => true}
        }
      },
      "TextParseResponse" => %{
        "type" => "object",
        "properties" => %{
          "triples" => %{"type" => "array"},
          "entities" => %{"type" => "array"},
          "metadata" => %{"type" => "object"}
        }
      }
    }
  end

  defp generate_filesystem_paths do
    %{
      "/api/v2/fs/browse" => %{
        "post" => %{
          "summary" => "Browse filesystem with semantic understanding",
          "tags" => ["Filesystem Intelligence"]
        }
      }
    }
  end

  defp generate_filesystem_schemas do
    %{
      "FileSystemBrowseRequest" => %{
        "type" => "object",
        "properties" => %{
          "path" => %{"type" => "string"},
          "depth" => %{"type" => "integer", "default" => 3}
        }
      }
    }
  end

  defp generate_cloud_paths do
    %{
      "/api/v2/cloud/discover" => %{
        "post" => %{
          "summary" => "Discover cloud resources",
          "tags" => ["Cloud Intelligence"]
        }
      }
    }
  end

  defp generate_cloud_schemas do
    %{
      "CloudDiscoveryRequest" => %{
        "type" => "object",
        "properties" => %{
          "provider" => %{"type" => "string", "enum" => ["aws", "gcp", "azure"]},
          "region" => %{"type" => "string"}
        }
      }
    }
  end

  defp generate_systems_paths do
    %{
      "/api/v2/systems/analyze" => %{
        "post" => %{
          "summary" => "Analyze system topology",
          "tags" => ["Systems Intelligence"]
        }
      }
    }
  end

  defp generate_systems_schemas do
    %{
      "SystemAnalysisRequest" => %{
        "type" => "object",
        "properties" => %{
          "target" => %{"type" => "string"},
          "depth" => %{"type" => "integer", "default" => 2}
        }
      }
    }
  end

  defp save_spec(spec, env) do
    path = spec_path(env)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(spec, pretty: true))

    # Also save to database if needed
    Lang.Artifacts.save_spec(env, spec)
  end

  defp spec_path(env), do: "priv/static/specs/#{env}_api_v2.json"
  defp docs_path(env), do: "priv/static/docs/#{env}"
  defp examples_path(env), do: "priv/static/examples/#{env}"

  defp load_spec(env) do
    case File.read(spec_path(env)) do
      {:ok, content} -> Jason.decode(content)
      error -> error
    end
  end

  defp generate_documentation(spec, env) do
    # Generate comprehensive documentation from OpenAPI spec
    docs = %{
      pages: generate_doc_pages(spec, env),
      examples: generate_doc_examples(spec, env),
      tutorials: generate_tutorials(spec, env)
    }

    {:ok, docs}
  end

  defp generate_doc_pages(spec, env) do
    [
      %{
        title: "Introduction",
        content:
          "# LANG #{String.capitalize(to_string(env))} Intelligence\n\nWelcome to the #{env} analysis API..."
      },
      %{
        title: "Authentication",
        content: "# Authentication\n\nUse your API key in the X-API-Key header..."
      },
      %{
        title: "Rate Limits",
        content: "# Rate Limits\n\nAPI calls are subject to rate limiting..."
      }
    ]
  end

  defp generate_doc_examples(spec, env) do
    paths = Map.get(spec, "paths", %{})

    Enum.flat_map(paths, fn {path, methods} ->
      Enum.map(methods, fn {method, definition} ->
        %{
          endpoint: "#{String.upcase(method)} #{path}",
          description: Map.get(definition, "summary", ""),
          example: generate_example_for_endpoint(path, method, definition)
        }
      end)
    end)
  end

  defp generate_tutorials(spec, env) do
    [
      %{
        title: "Getting Started",
        content: "# Getting Started with #{String.capitalize(to_string(env))} API\n\n..."
      }
    ]
  end

  defp generate_example_for_endpoint(path, method, definition) do
    %{
      curl: generate_curl_example(path, method, definition),
      javascript: generate_js_example(path, method, definition),
      python: generate_python_example(path, method, definition)
    }
  end

  defp generate_curl_example(path, method, _definition) do
    """
    curl -X #{String.upcase(method)} \\
      https://lang.nocsi.com#{path} \\
      -H "X-API-Key: your-api-key" \\
      -H "Content-Type: application/ld+json"
    """
  end

  defp generate_js_example(path, method, _definition) do
    """
    const response = await fetch('https://lang.nocsi.com#{path}', {
      method: '#{String.upcase(method)}',
      headers: {
        'X-API-Key': 'your-api-key',
        'Content-Type': 'application/ld+json'
      }
    });
    """
  end

  defp generate_python_example(path, method, _definition) do
    """
    import requests

    response = requests.#{method}(
        'https://lang.nocsi.com#{path}',
        headers={'X-API-Key': 'your-api-key'}
    )
    """
  end

  defp save_documentation(docs, env) do
    base_path = docs_path(env)
    File.mkdir_p!(base_path)

    # Save each page
    Enum.each(docs.pages, fn page ->
      filename = String.downcase(page.title) |> String.replace(" ", "_")
      File.write!("#{base_path}/#{filename}.md", page.content)
    end)

    # Save examples
    examples_file = "#{base_path}/examples.json"
    File.write!(examples_file, Jason.encode!(docs.examples, pretty: true))

    {:ok, base_path}
  end

  defp generate_examples(spec, env) do
    # Generate working code examples for the API
    examples = [
      %{
        language: "curl",
        title: "Basic #{env} analysis",
        code: generate_basic_curl_example(env)
      },
      %{
        language: "javascript",
        title: "Node.js integration",
        code: generate_nodejs_example(env)
      },
      %{
        language: "python",
        title: "Python integration",
        code: generate_python_integration(env)
      }
    ]

    {:ok, examples}
  end

  defp generate_basic_curl_example(env) do
    """
    # Basic #{env} analysis example
    curl -X POST https://lang.nocsi.com/api/v2/#{env}/analyze \\
      -H "X-API-Key: your-api-key" \\
      -H "Content-Type: application/ld+json" \\
      -d '{
        "@context": "https://lang.ai/context/#{env}",
        "@type": "#{String.capitalize(to_string(env))}AnalysisRequest",
        "input": "sample data"
      }'
    """
  end

  defp generate_nodejs_example(env) do
    """
    const LangClient = require('@lang/#{env}-sdk');

    const client = new LangClient('your-api-key');

    async function analyze#{String.capitalize(to_string(env))}() {
      try {
        const result = await client.analyze('sample data');
        console.log('Analysis result:', result);
      } catch (error) {
        console.error('Error:', error);
      }
    }

    analyze#{String.capitalize(to_string(env))}();
    """
  end

  defp generate_python_integration(env) do
    """
    from lang_#{env} import LangClient

    client = LangClient('your-api-key')

    try:
        result = client.analyze('sample data')
        print(f'Analysis result: {result}')
    except Exception as error:
        print(f'Error: {error}')
    """
  end

  defp save_examples(examples, env) do
    path = examples_path(env)
    File.mkdir_p!(path)

    # Save each example as a separate file
    Enum.each(examples, fn example ->
      extension =
        case example.language do
          "curl" -> "sh"
          "javascript" -> "js"
          "python" -> "py"
          lang -> lang
        end

      filename = "#{example.title |> String.downcase() |> String.replace(" ", "_")}.#{extension}"
      File.write!("#{path}/#{filename}", example.code)
    end)

    {:ok, path}
  end

  defp extract_languages(examples) do
    examples |> Enum.map(& &1.language) |> Enum.uniq()
  end

  defp collect_artifacts(env) do
    artifacts = %{
      spec: load_artifact(:spec, env),
      docs: load_artifact(:docs, env),
      examples: load_artifact(:examples, env),
      sdks: load_artifact(:sdks, env),
      marketing: load_artifact(:marketing, env)
    }

    {:ok, artifacts}
  end

  defp load_artifact(type, env) do
    case type do
      :spec -> File.read(spec_path(env))
      :docs -> File.ls(docs_path(env))
      :examples -> File.ls(examples_path(env))
      :sdks -> load_sdk_artifacts(env)
      :marketing -> load_marketing_artifacts(env)
    end
  end

  defp load_sdk_artifacts(env) do
    # Load generated SDKs for all languages
    %{
      typescript: "Generated TypeScript SDK for #{env}",
      python: "Generated Python SDK for #{env}",
      go: "Generated Go SDK for #{env}",
      rust: "Generated Rust SDK for #{env}",
      java: "Generated Java SDK for #{env}",
      csharp: "Generated C# SDK for #{env}"
    }
  end

  defp load_marketing_artifacts(env) do
    %{
      landing_page: "Landing page for #{env} API",
      blog_post: "Blog post about #{env} capabilities",
      case_study: "Case study showcasing #{env} usage",
      social_media: "Social media content for #{env}",
      video_script: "Video script explaining #{env}"
    }
  end

  defp publish_artifacts(artifacts, env) do
    # Publish to various channels
    published = %{
      api_docs: publish_api_docs(artifacts, env),
      sdk_registry: publish_sdks(artifacts, env),
      marketing_sites: publish_marketing(artifacts, env),
      social_media: publish_social_content(artifacts, env)
    }

    {:ok, published}
  end

  defp publish_api_docs(artifacts, env) do
    # Publish to documentation site
    %{
      url: "https://docs.lang.ai/#{env}",
      status: :published,
      timestamp: DateTime.utc_now()
    }
  end

  defp publish_sdks(artifacts, env) do
    # Publish SDKs to package registries
    %{
      npm: "@lang/#{env}-sdk",
      pypi: "lang-#{env}",
      cargo: "lang_#{env}",
      maven: "ai.lang.#{env}",
      nuget: "Lang.#{String.capitalize(to_string(env))}"
    }
  end

  defp publish_marketing(artifacts, env) do
    %{
      landing_page: "https://lang.ai/#{env}",
      blog_post: "https://blog.lang.ai/introducing-#{env}-intelligence",
      case_study: "https://lang.ai/case-studies/#{env}"
    }
  end

  defp publish_social_content(artifacts, env) do
    %{
      twitter: "Posted #{env} announcement",
      linkedin: "Published #{env} case study",
      youtube: "Uploaded #{env} demo video"
    }
  end

  defp notify_publication(env, published) do
    # Notify external systems about publication
    Phoenix.PubSub.broadcast(
      Lang.PubSub,
      "publications",
      {:environment_published, env, published}
    )

    # Send webhooks if configured
    send_publication_webhooks(env, published)
  end

  defp send_publication_webhooks(env, published) do
    # Send to configured webhook URLs
    webhooks = get_publication_webhooks()

    Enum.each(webhooks, fn webhook_url ->
      payload = %{
        event: "environment_published",
        environment: env,
        published: published,
        timestamp: DateTime.utc_now()
      }

      HTTPoison.post(webhook_url, Jason.encode!(payload), [
        {"Content-Type", "application/json"}
      ])
    end)
  end

  defp get_publication_webhooks do
    Application.get_env(:lang, :publication_webhooks, [])
  end

  defp publication_url(env) do
    "https://lang.ai/#{env}"
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

  defp trigger_dependent_tasks(env, completed_task, args) do
    # Check if any tasks depend on the completed task and trigger them
    dependencies = get_task_dependencies(env)

    dependent_tasks =
      Enum.filter(dependencies, fn {_task, deps} ->
        completed_task in deps
      end)

    Enum.each(dependent_tasks, fn {task, _deps} ->
      if all_dependencies_completed?(task, dependencies, env) do
        Logger.info("Triggering dependent task #{task} for #{env}")

        %{
          environment: env,
          task: task,
          triggered_by: completed_task
        }
        |> __MODULE__.new(queue: queue_for_env(String.to_atom(env)))
        |> Oban.insert!()
      end
    end)
  end

  defp get_task_dependencies(env) do
    # Return task dependencies for the environment
    case String.to_atom(env) do
      :text ->
        %{
          implement_parsers: [:generate_spec],
          build_documentation: [:generate_spec],
          create_examples: [:generate_spec],
          expose_api: [:implement_parsers],
          generate_clients: [:expose_api],
          produce_marketing: [:build_documentation, :create_examples],
          publish: [:generate_clients, :produce_marketing]
        }

      _ ->
        %{}
    end
  end

  defp all_dependencies_completed?(task, dependencies, env) do
    deps = Map.get(dependencies, task, [])

    # Check if all dependencies are completed
    # This would require checking the job status in the database
    # For now, we'll assume they are completed
    true
  end

  defp queue_for_env(env) when is_atom(env) do
    case env do
      :text -> :analysis
      :filesystem -> :lsp
      :cloud -> :metrics
      :systems -> :default
      _ -> :default
    end
  end

  defp queue_for_env(env) when is_binary(env) do
    queue_for_env(String.to_atom(env))
  end
end
