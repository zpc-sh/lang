defmodule Lang.LSP.API do
  @moduledoc """
  Thin convenience wrappers around `Lang.LSP.Client` for common LSP operations.
  """

  alias Lang.LSP.Client

  @doc "Initialize a session (if supported by the server)."
  def initialize(params \\ %{}, opts \\ []) do
    Client.request("rpc.initialize", params, opts)
  end

  @doc "Gracefully shutdown the server (if supported)."
  def shutdown(opts \\ []) do
    Client.request("rpc.shutdown", %{}, opts)
  end

  @doc "Health check ping."
  def ping(opts \\ []) do
    Client.request("rpc.ping", %{}, opts)
  end

  @doc "Generic method invoker."
  def call(method, params \\ %{}, opts \\ []) when is_binary(method) do
    Client.request(method, params, opts)
  end

  # ----------------------------------------------------------------------------
  # Convenience wrappers for common LANG methods
  # ----------------------------------------------------------------------------

  @doc "Filesystem scan wrapper using native NIFs via the LSP server."
  def fs_scan(path, opts \\ %{}, call_opts \\ []) when is_binary(path) and is_map(opts) do
    params = Map.merge(%{"path" => path}, opts)
    Client.request("lang.fs.scan", params, call_opts)
  end

  @doc "Filesystem regex search wrapper."
  def fs_search(path, query, opts \\ %{}, call_opts \\ []) when is_binary(path) and is_binary(query) do
    params = Map.merge(%{"path" => path, "query" => query}, opts)
    Client.request("lang.fs.search", params, call_opts)
  end

  @doc "Tree-sitter code search wrapper."
  def fs_search_code(path, language, pattern, opts \\ %{}, call_opts \\ [])
      when is_binary(path) and is_binary(language) and is_binary(pattern) do
    params = Map.merge(%{"path" => path, "language" => language, "pattern" => pattern}, opts)
    Client.request("lang.fs.search_code", params, call_opts)
  end

  @doc "Analyze a document’s content with native analysis engine."
  def analyze_document(content, opts \\ %{}, call_opts \\ []) when is_binary(content) do
    params = Map.merge(%{"content" => content}, opts)
    Client.request("lang.analyze.document", params, call_opts)
  end

  @doc "Parser: parse content or structured input."
  def parser_parse(params, call_opts \\ []) when is_map(params) do
    Client.request("lang.parser.parse", params, call_opts)
  end
end
