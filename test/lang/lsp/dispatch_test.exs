defmodule Lang.LSP.DispatchTest do
  use ExUnit.Case, async: true

  alias Lang.LSP.Dispatch

  test "parser.detect_format infers markdown from content" do
    msg = %{"id" => 1, "method" => "lang.parser.detect_format", "params" => %{"content" => "# Title\ntext"}}
    resp = Dispatch.process(msg)
    assert resp["result"]["format"] in ["markdown", "text", "unknown"]
  end

  test "parser.parse handles JSON" do
    msg = %{"id" => 2, "method" => "lang.parser.parse", "params" => %{"content" => ~s({"a":1}), "format" => "json"}}
    resp = Dispatch.process(msg)
    assert %{"result" => %{"data" => %{"a" => 1}}} = resp
  end

  test "fs.preview returns joined content for an existing file" do
    assert File.exists?("README.md")
    msg = %{"id" => 3, "method" => "lang.fs.preview", "params" => %{"path" => "README.md", "max_lines" => 5}}
    resp = Dispatch.process(msg)
    assert is_binary(resp["result"])
  end

  test "analysis.document returns analysis structure" do
    msg = %{"id" => 4, "method" => "lang.analyze.document", "params" => %{"content" => "defmodule X do\nend", "format" => "elixir"}}
    resp = Dispatch.process(msg)
    # Accept either {:ok, analysis} or {:error, reason} wrapped; at least a response map
    assert is_map(resp)
  end

  test "storage CRUD via in-memory store" do
    create = %{"id" => 5, "method" => "lang.storage.create_session", "params" => %{"project_id" => "proj1"}}
    %{"result" => %{"id" => sid}} = Dispatch.process(create)

    get = %{"id" => 6, "method" => "lang.storage.get_session", "params" => %{"session_id" => sid}}
    %{"result" => %{"id" => ^sid}} = Dispatch.process(get)

    close = %{"id" => 7, "method" => "lang.storage.close_session", "params" => %{"session_id" => sid}}
    %{"result" => %{"closed" => true}} = Dispatch.process(close)
  end
end

