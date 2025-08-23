defmodule Lang.Workers.SDKGenerator do
  use Oban.Worker,
    queue: :default,
    max_attempts: 5

  @languages [:typescript, :python, :rust, :swift, :elixir]
  @base_url "https://lang.nocsi.com"
  @api_base "https://lang.nocsi.com/api"

  def perform(%Oban.Job{args: %{"environment" => env, "language" => lang}}) do
    with {:ok, spec} <- load_openapi_spec(env),
         {:ok, sdk_code} <- generate_sdk(spec, lang, env),
         {:ok, _published} <- publish_sdk(sdk_code, lang, env) do
      notify_sdk_ready(env, lang)
      :ok
    end
  end

  # TypeScript - For web and Node.js
  defp generate_sdk(spec, :typescript, env) do
    sdk = """
    // Auto-generated LANG SDK for #{env} environment
    // Generated: #{DateTime.utc_now()}

    export class Lang#{String.capitalize(to_string(env))}Client {
      private apiKey: string;
      private baseUrl: string;
      private obanJobId?: string;

      constructor(config: LangConfig) {
        this.apiKey = config.apiKey;
        this.baseUrl = config.baseUrl || '#{@api_base}';
      }

      #{generate_typescript_methods(spec)}

      // Async job monitoring (via Oban)
      async waitForJob(jobId: string): Promise<any> {
        const pollInterval = 1000;
        while (true) {
          const status = await this.getJobStatus(jobId);
          if (status.state === 'completed') {
            return status.result;
          }
          if (status.state === 'failed') {
            throw new Error(status.error);
          }
          await new Promise(r => setTimeout(r, pollInterval));
        }
      }
    }

    // JSON-LD type definitions
    export interface JsonLDContext {
      '@context': string | object | Array<string | object>;
      '@id'?: string;
      '@type'?: string | string[];
    }

    export interface ParseResult extends JsonLDContext {
      ast: any;
      triples: Triple[];
      metadata: Record<string, any>;
    }
    """

    {:ok, sdk}
  end

  # Python - For data science and backend
  defp generate_sdk(spec, :python, env) do
    sdk = """
    # Auto-generated LANG SDK for #{env} environment
    # Generated: #{DateTime.utc_now()}

    import asyncio
    import httpx
    from typing import Dict, Any, Optional, List, Union
    from dataclasses import dataclass
    from enum import Enum

    @dataclass
    class JsonLDContext:
        context: Union[str, Dict, List]
        id: Optional[str] = None
        type: Optional[Union[str, List[str]]] = None

        def to_dict(self):
            return {
                "@context": self.context,
                "@id": self.id,
                "@type": self.type
            }

    class Lang#{String.capitalize(to_string(env))}Client:
        \"\"\"LANG #{String.capitalize(to_string(env))} Intelligence Client\"\"\"

        def __init__(self, api_key: str, base_url: str = "#{@api_base}"):
            self.api_key = api_key
            self.base_url = base_url
            self.client = httpx.AsyncClient(
                headers={
                    "Authorization": f"Bearer {api_key}",
                    "Content-Type": "application/ld+json"
                }
            )

        #{generate_python_methods(spec)}

        async def wait_for_job(self, job_id: str) -> Dict[str, Any]:
            \"\"\"Wait for an Oban job to complete\"\"\"
            while True:
                status = await self.get_job_status(job_id)
                if status["state"] == "completed":
                    return status["result"]
                elif status["state"] == "failed":
                    raise Exception(status["error"])
                await asyncio.sleep(1)
    """

    {:ok, sdk}
  end

  # Rust - For high-performance applications
  defp generate_sdk(spec, :rust, env) do
    sdk = """
    // Auto-generated LANG SDK for #{env} environment
    // Generated: #{DateTime.utc_now()}

    use serde::{Deserialize, Serialize};
    use reqwest::{Client, Error};
    use std::collections::HashMap;

    const DEFAULT_BASE_URL: &str = "#{@api_base}";

    #[derive(Debug, Clone, Serialize, Deserialize)]
    pub struct JsonLDContext {
        #[serde(rename = "@context")]
        pub context: serde_json::Value,
        #[serde(rename = "@id", skip_serializing_if = "Option::is_none")]
        pub id: Option<String>,
        #[serde(rename = "@type", skip_serializing_if = "Option::is_none")]
        pub r#type: Option<Vec<String>>,
    }

    pub struct Lang#{String.capitalize(to_string(env))}Client {
        api_key: String,
        base_url: String,
        client: Client,
    }

    impl Lang#{String.capitalize(to_string(env))}Client {
        pub fn new(api_key: String) -> Self {
            Self::with_base_url(api_key, DEFAULT_BASE_URL.to_string())
        }

        pub fn with_base_url(api_key: String, base_url: String) -> Self {
            Self {
                api_key: api_key.clone(),
                base_url,
                client: Client::builder()
                    .default_headers({
                        let mut headers = reqwest::header::HeaderMap::new();
                        headers.insert(
                            "Authorization",
                            format!("Bearer {}", api_key).parse().unwrap()
                        );
                        headers.insert(
                            "Content-Type",
                            "application/ld+json".parse().unwrap()
                        );
                        headers
                    })
                    .build()
                    .unwrap(),
            }
        }

        #{generate_rust_methods(spec)}

        pub async fn wait_for_job(&self, job_id: &str) -> Result<serde_json::Value, Error> {
            loop {
                let status = self.get_job_status(job_id).await?;
                match status["state"].as_str() {
                    Some("completed") => return Ok(status["result"].clone()),
                    Some("failed") => {
                        return Err(Error::from(std::io::Error::new(
                            std::io::ErrorKind::Other,
                            status["error"].as_str().unwrap_or("Unknown error")
                        )))
                    }
                    _ => tokio::time::sleep(std::time::Duration::from_secs(1)).await,
                }
            }
        }
    }
    """

    {:ok, sdk}
  end

  # Swift - For iOS/macOS applications
  defp generate_sdk(spec, :swift, env) do
    sdk = """
    // Auto-generated LANG SDK for #{env} environment
    // Generated: #{DateTime.utc_now()}

    import Foundation
    import Combine

    /// JSON-LD Context protocol
    protocol JsonLDContext {
        var context: Any { get }
        var id: String? { get }
        var type: [String]? { get }
    }

    /// LANG #{String.capitalize(to_string(env))} Client for iOS/macOS
    class Lang#{String.capitalize(to_string(env))}Client {
        private let apiKey: String
        private let baseURL: URL
        private let session: URLSession
        private var cancellables = Set<AnyCancellable>()

        static let defaultBaseURL = "#{@api_base}"

        init(apiKey: String, baseURL: String = Lang#{String.capitalize(to_string(env))}Client.defaultBaseURL) {
            self.apiKey = apiKey
            self.baseURL = URL(string: baseURL)!

            let config = URLSessionConfiguration.default
            config.httpAdditionalHeaders = [
                "Authorization": "Bearer \\(apiKey)",
                "Content-Type": "application/ld+json"
            ]
            self.session = URLSession(configuration: config)
        }

        #{generate_swift_methods(spec)}

        /// Wait for an Oban job to complete
        func waitForJob(jobId: String) async throws -> Any {
            while true {
                let status = try await getJobStatus(jobId: jobId)

                if let state = status["state"] as? String {
                    switch state {
                    case "completed":
                        return status["result"] ?? [:]
                    case "failed":
                        throw LangError.jobFailed(status["error"] as? String ?? "Unknown error")
                    default:
                        try await Task.sleep(nanoseconds: 1_000_000_000)
                    }
                }
            }
        }
    }

    enum LangError: Error {
        case invalidResponse
        case jobFailed(String)
        case networkError(Error)
    }
    """

    {:ok, sdk}
  end

  # Elixir - For Elixir/Phoenix applications
  defp generate_sdk(spec, :elixir, env) do
    sdk = """
    defmodule Lang.Client.#{String.capitalize(to_string(env))} do
      @moduledoc \"\"\"
      Auto-generated LANG SDK for #{env} environment
      Generated: #{DateTime.utc_now()}

      ## Installation

      Add to your `mix.exs`:

      ```elixir
      {:lang_client_#{env}, "~> 1.0"}
      ```

      ## Usage

      ```elixir
      client = Lang.Client.#{String.capitalize(to_string(env))}.new(api_key)
      {:ok, result} = Lang.Client.#{String.capitalize(to_string(env))}.parse(client, content, format)
      ```
      \"\"\"

      use Tesla

      @base_url "#{@api_base}"

      plug Tesla.Middleware.BaseUrl, @base_url
      plug Tesla.Middleware.Headers, [
        {"content-type", "application/ld+json"},
        {"accept", "application/ld+json"}
      ]
      plug Tesla.Middleware.JSON
      plug Tesla.Middleware.Logger
      plug Tesla.Middleware.Retry,
        delay: 500,
        max_retries: 3,
        max_delay: 4_000,
        should_retry: fn
          {:ok, %{status: status}} when status in 500..599 -> true
          {:ok, %{status: 429}} -> true
          {:error, _} -> true
          _ -> false
        end

      @doc \"\"\"
      Create a new LANG client with API key authentication

      ## Options

      - `:base_url` - Override the default base URL (default: #{@base_url})
      - `:timeout` - Request timeout in milliseconds (default: 30_000)
      \"\"\"
      def new(api_key, opts \\\\ []) do
        base_url = Keyword.get(opts, :base_url, @base_url)

        middleware = [
          {Tesla.Middleware.BaseUrl, base_url},
          {Tesla.Middleware.Headers, [
            {"authorization", "Bearer \#{api_key}"},
            {"content-type", "application/ld+json"}
          ]},
          Tesla.Middleware.JSON,
          Tesla.Middleware.Logger
        ]

        Tesla.client(middleware)
      end

      #{generate_elixir_methods(spec)}

      @doc \"\"\"
      Wait for an Oban job to complete

      ## Options

      - `:timeout` - Maximum time to wait in milliseconds (default: 30_000)
      - `:poll_interval` - Time between status checks in milliseconds (default: 1_000)
      \"\"\"
      def wait_for_job(client, job_id, opts \\\\ []) do
        timeout = Keyword.get(opts, :timeout, 30_000)
        poll_interval = Keyword.get(opts, :poll_interval, 1_000)

        Task.async(fn ->
          wait_for_job_loop(client, job_id, poll_interval)
        end)
        |> Task.await(timeout)
      end

      defp wait_for_job_loop(client, job_id, poll_interval) do
        case get_job_status(client, job_id) do
          {:ok, %{"state" => "completed", "result" => result}} ->
            {:ok, result}

          {:ok, %{"state" => "failed", "error" => error}} ->
            {:error, error}

          {:ok, _} ->
            Process.sleep(poll_interval)
            wait_for_job_loop(client, job_id, poll_interval)

          {:error, reason} ->
            {:error, reason}
        end
      end

      @doc \"\"\"
      Stream results from a paginated endpoint
      \"\"\"
      def stream(client, path, opts \\\\ []) do
        Stream.resource(
          fn -> {client, path, 1} end,
          fn {client, path, page} ->
            case get(client, "\#{path}?page=\#{page}") do
              {:ok, %{body: %{"data" => data, "has_more" => true}}} ->
                {data, {client, path, page + 1}}

              {:ok, %{body: %{"data" => data}}} ->
                {data, :halt}

              _ ->
                {:halt, :halt}
            end
          end,
          fn _ -> :ok end
        )
      end
    end
    """

    {:ok, sdk}
  end

  # Helper methods for generating language-specific code

  defp generate_typescript_methods(spec) do
    paths = Map.get(spec, "paths", %{})

    methods =
      Enum.map(paths, fn {path, operations} ->
        Enum.map(operations, fn {method, operation} ->
          method_name = get_method_name(operation)

          """
          async #{method_name}(data: any): Promise<any> {
            const response = await fetch(`${this.baseUrl}#{path}`, {
              method: '#{String.upcase(method)}',
              headers: {
                'Authorization': `Bearer ${this.apiKey}`,
                'Content-Type': 'application/ld+json'
              },
              body: JSON.stringify(data)
            });

            if (!response.ok) {
              throw new Error(`HTTP ${response.status}: ${response.statusText}`);
            }

            return response.json();
          }
          """
        end)
      end)
      |> List.flatten()
      |> Enum.join("\n")

    methods
  end

  defp generate_python_methods(spec) do
    paths = Map.get(spec, "paths", %{})

    methods =
      Enum.map(paths, fn {path, operations} ->
        Enum.map(operations, fn {method, operation} ->
          method_name = get_method_name(operation)

          """
          async def #{method_name}(self, data: Dict[str, Any]) -> Dict[str, Any]:
              \"\"\"#{Map.get(operation, "summary", "API method")}\"\"\"
              response = await self.client.#{method}(
                  f"{self.base_url}#{path}",
                  json=data
              )
              response.raise_for_status()
              return response.json()
          """
        end)
      end)
      |> List.flatten()
      |> Enum.join("\n")

    methods
  end

  defp generate_rust_methods(spec) do
    paths = Map.get(spec, "paths", %{})

    methods =
      Enum.map(paths, fn {path, operations} ->
        Enum.map(operations, fn {method, operation} ->
          method_name = get_method_name(operation)

          """
          pub async fn #{method_name}(&self, data: serde_json::Value) -> Result<serde_json::Value, Error> {
              let response = self.client
                  .#{method}(&format!("{}#{path}", self.base_url))
                  .json(&data)
                  .send()
                  .await?;

              if !response.status().is_success() {
                  return Err(Error::from(std::io::Error::new(
                      std::io::ErrorKind::Other,
                      format!("HTTP {}: {}", response.status(), response.status().canonical_reason().unwrap_or("Unknown"))
                  )));
              }

              Ok(response.json().await?)
          }
          """
        end)
      end)
      |> List.flatten()
      |> Enum.join("\n")

    methods
  end

  defp generate_swift_methods(spec) do
    paths = Map.get(spec, "paths", %{})

    methods =
      Enum.map(paths, fn {path, operations} ->
        Enum.map(operations, fn {method, operation} ->
          method_name = get_method_name(operation)

          """
          func #{method_name}(data: [String: Any]) async throws -> [String: Any] {
              let url = baseURL.appendingPathComponent("#{path}")
              var request = URLRequest(url: url)
              request.httpMethod = "#{String.upcase(method)}"
              request.httpBody = try JSONSerialization.data(withJSONObject: data)

              let (data, response) = try await session.data(for: request)

              guard let httpResponse = response as? HTTPURLResponse,
                    200...299 ~= httpResponse.statusCode else {
                  throw LangError.invalidResponse
              }

              return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
          }
          """
        end)
      end)
      |> List.flatten()
      |> Enum.join("\n")

    methods
  end

  defp generate_elixir_methods(spec) do
    paths = Map.get(spec, "paths", %{})

    methods =
      Enum.map(paths, fn {path, operations} ->
        Enum.map(operations, fn {method, operation} ->
          method_name = get_method_name(operation)

          """
          @doc \"\"\"
          #{Map.get(operation, "summary", "API method")}
          \"\"\"
          def #{method_name}(client, data, opts \\\\ []) do
            case #{method}(client, "#{path}", data, opts) do
              {:ok, %{status: 200, body: body}} -> {:ok, body}
              {:ok, %{status: status, body: body}} -> {:error, {status, body}}
              error -> error
            end
          end
          """
        end)
      end)
      |> List.flatten()
      |> Enum.join("\n")

    methods
  end

  defp get_method_name(operation) do
    operation
    |> Map.get("operationId", Map.get(operation, "summary", "unknown"))
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9_]/, "_")
    |> String.replace(~r/_+/, "_")
    |> String.trim_trailing("_")
  end

  defp load_openapi_spec(env) do
    path = "priv/static/specs/#{env}_api_v2.json"

    case File.read(path) do
      {:ok, content} -> Jason.decode(content)
      {:error, reason} -> {:error, "Failed to load spec: #{reason}"}
    end
  end

  defp publish_sdk(sdk_code, language, env) do
    # Save SDK to files
    save_sdk_files(sdk_code, language, env)

    # Publish to package registries
    case language do
      :typescript -> publish_to_npm(sdk_code, env)
      :python -> publish_to_pypi(sdk_code, env)
      :rust -> publish_to_crates(sdk_code, env)
      :swift -> publish_to_swift_package_manager(sdk_code, env)
      :elixir -> publish_to_hex(sdk_code, env)
    end
  end

  defp save_sdk_files(sdk_code, language, env) do
    base_path = "priv/static/sdks/#{env}/#{language}"
    File.mkdir_p!(base_path)

    case language do
      :typescript ->
        File.write!("#{base_path}/index.ts", sdk_code)
        File.write!("#{base_path}/package.json", generate_package_json(env))

      :python ->
        File.write!("#{base_path}/lang_#{env}/__init__.py", sdk_code)
        File.write!("#{base_path}/setup.py", generate_setup_py(env))

      :rust ->
        File.write!("#{base_path}/src/lib.rs", sdk_code)
        File.write!("#{base_path}/Cargo.toml", generate_cargo_toml(env))

      :swift ->
        File.write!(
          "#{base_path}/Sources/Lang#{String.capitalize(to_string(env))}/Client.swift",
          sdk_code
        )

        File.write!("#{base_path}/Package.swift", generate_package_swift(env))

      :elixir ->
        File.write!("#{base_path}/lib/lang/client/#{env}.ex", sdk_code)
        File.write!("#{base_path}/mix.exs", generate_mix_exs(env))
    end

    {:ok, base_path}
  end

  defp generate_package_json(env) do
    Jason.encode!(
      %{
        name: "@lang/#{env}-sdk",
        version: "1.0.0",
        description:
          "LANG #{String.capitalize(to_string(env))} Intelligence SDK for TypeScript/JavaScript",
        main: "dist/index.js",
        types: "dist/index.d.ts",
        scripts: %{
          build: "tsc",
          test: "jest"
        },
        keywords: ["lang", "ai", "#{env}", "intelligence", "sdk"],
        author: "LANG Team",
        license: "MIT",
        dependencies: %{},
        devDependencies: %{
          "typescript" => "^4.9.0",
          "@types/node" => "^18.0.0"
        }
      },
      pretty: true
    )
  end

  defp generate_setup_py(env) do
    """
    from setuptools import setup, find_packages

    setup(
        name="lang-#{env}",
        version="1.0.0",
        description="LANG #{String.capitalize(to_string(env))} Intelligence SDK for Python",
        long_description=open("README.md").read(),
        long_description_content_type="text/markdown",
        author="LANG Team",
        author_email="team@lang.ai",
        url="https://github.com/lang-ai/#{env}-python-sdk",
        packages=find_packages(),
        install_requires=[
            "httpx>=0.24.0",
            "pydantic>=1.10.0"
        ],
        python_requires=">=3.8",
        classifiers=[
            "Development Status :: 4 - Beta",
            "Intended Audience :: Developers",
            "License :: OSI Approved :: MIT License",
            "Programming Language :: Python :: 3",
            "Programming Language :: Python :: 3.8",
            "Programming Language :: Python :: 3.9",
            "Programming Language :: Python :: 3.10",
            "Programming Language :: Python :: 3.11",
        ],
    )
    """
  end

  defp generate_cargo_toml(env) do
    """
    [package]
    name = "lang_#{env}"
    version = "1.0.0"
    edition = "2021"
    description = "LANG #{String.capitalize(to_string(env))} Intelligence SDK for Rust"
    license = "MIT"
    repository = "https://github.com/lang-ai/#{env}-rust-sdk"
    homepage = "https://lang.ai"
    keywords = ["lang", "ai", "#{env}", "intelligence"]

    [dependencies]
    reqwest = { version = "0.11", features = ["json"] }
    serde = { version = "1.0", features = ["derive"] }
    serde_json = "1.0"
    tokio = { version = "1.0", features = ["full"] }

    [dev-dependencies]
    tokio-test = "0.4"
    """
  end

  defp generate_package_swift(env) do
    """
    // swift-tools-version:5.7
    import PackageDescription

    let package = Package(
        name: "Lang#{String.capitalize(to_string(env))}",
        platforms: [
            .macOS(.v10_15),
            .iOS(.v13),
            .watchOS(.v6),
            .tvOS(.v13)
        ],
        products: [
            .library(
                name: "Lang#{String.capitalize(to_string(env))}",
                targets: ["Lang#{String.capitalize(to_string(env))}"]
            ),
        ],
        targets: [
            .target(
                name: "Lang#{String.capitalize(to_string(env))}",
                dependencies: []
            ),
            .testTarget(
                name: "Lang#{String.capitalize(to_string(env))}Tests",
                dependencies: ["Lang#{String.capitalize(to_string(env))}"]
            ),
        ]
    )
    """
  end

  defp generate_mix_exs(env) do
    """
    defmodule Lang.Client.#{String.capitalize(to_string(env))}.MixProject do
      use Mix.Project

      def project do
        [
          app: :lang_client_#{env},
          version: "1.0.0",
          elixir: "~> 1.14",
          start_permanent: Mix.env() == :prod,
          description: description(),
          package: package(),
          deps: deps()
        ]
      end

      def application do
        [
          extra_applications: [:logger]
        ]
      end

      defp deps do
        [
          {:tesla, "~> 1.7"},
          {:jason, "~> 1.4"},
          {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
        ]
      end

      defp description do
        "LANG #{String.capitalize(to_string(env))} Intelligence SDK for Elixir"
      end

      defp package do
        [
          licenses: ["MIT"],
          links: %{"GitHub" => "https://github.com/lang-ai/#{env}-elixir-sdk"}
        ]
      end
    end
    """
  end

  # Publishing functions (placeholders - would integrate with actual registries)

  defp publish_to_npm(sdk_code, env) do
    Logger.info("Publishing TypeScript SDK for #{env} to npm")
    {:ok, %{registry: "npm", package: "@lang/#{env}-sdk"}}
  end

  defp publish_to_pypi(sdk_code, env) do
    Logger.info("Publishing Python SDK for #{env} to PyPI")
    {:ok, %{registry: "pypi", package: "lang-#{env}"}}
  end

  defp publish_to_crates(sdk_code, env) do
    Logger.info("Publishing Rust SDK for #{env} to crates.io")
    {:ok, %{registry: "crates", package: "lang_#{env}"}}
  end

  defp publish_to_swift_package_manager(sdk_code, env) do
    Logger.info("Publishing Swift SDK for #{env} to Swift Package Manager")
    {:ok, %{registry: "swift", package: "Lang#{String.capitalize(to_string(env))}"}}
  end

  defp publish_to_hex(sdk_code, env) do
    Logger.info("Publishing Elixir SDK for #{env} to Hex")
    {:ok, %{registry: "hex", package: "lang_client_#{env}"}}
  end

  defp notify_sdk_ready(env, language) do
    Phoenix.PubSub.broadcast(
      Lang.PubSub,
      "orchestration:updates",
      {:sdk_ready, env, language}
    )

    Logger.info("SDK ready: #{language} for #{env} environment")
  end
end
