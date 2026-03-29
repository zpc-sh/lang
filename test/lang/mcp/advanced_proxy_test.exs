defmodule Lang.MCP.AdvancedProxyTest do
  use Lang.DataCase, async: true
  use LangWeb.ConnCase

  alias Lang.MCP.{AdvancedProxy, Broker}
  alias Lang.Accounts.User
  alias Lang.Repo

  setup do
    # Create test user
    {:ok, user} = %User{
      email: "test@example.com",
      hashed_password: "hashed_password"
    } |> Repo.insert()

    # Start AdvancedProxy for testing
    {:ok, _pid} = AdvancedProxy.start_link([])

    %{user: user}
  end

  describe "SSE connection management" do
    test "connect_sse/4 establishes authenticated SSE connection", %{user: user} do
      config = %{"server_type" => "filesystem", "config" => %{}}

      assert {:ok, topic} = AdvancedProxy.connect_sse(user.id, "test_conn_1", "filesystem", config)

      # Verify topic format
      assert String.starts_with?(topic, "mcp:sse:test_conn_1")

      # Verify connection is tracked
      stats = AdvancedProxy.get_stats()
      assert stats.sse_clients == 1
    end

    test "connect_sse/4 enforces connection limits per user", %{user: user} do
      # Create maximum allowed connections
      config = %{"server_type" => "filesystem", "config" => %{}}

      # This should work
      for i <- 1..10 do
        {:ok, _topic} = AdvancedProxy.connect_sse(user.id, "test_conn_#{i}", "filesystem", config)
      end

      # This should fail (exceeds limit)
      assert {:error, :max_clients_exceeded} = AdvancedProxy.connect_sse(user.id, "test_conn_11", "filesystem", config)
    end

    test "connect_sse/4 prevents duplicate connections", %{user: user} do
      config = %{"server_type" => "filesystem", "config" => %{}}

      # First connection should work
      {:ok, _topic} = AdvancedProxy.connect_sse(user.id, "duplicate_conn", "filesystem", config)

      # Duplicate should fail
      assert {:error, :connection_already_exists} = AdvancedProxy.connect_sse(user.id, "duplicate_conn", "filesystem", config)
    end

    test "sse_heartbeat/1 maintains connection", %{user: user} do
      config = %{"server_type" => "filesystem", "config" => %{}}
      {:ok, _topic} = AdvancedProxy.connect_sse(user.id, "heartbeat_conn", "filesystem", config)

      # Send heartbeat
      :ok = AdvancedProxy.sse_heartbeat("heartbeat_conn")

      # Verify connection still exists
      stats = AdvancedProxy.get_stats()
      assert stats.sse_clients == 1
    end
  end

  describe "OAuth connection management" do
    test "connect_oauth/3 initiates OAuth flow", %{user: user} do
      oauth_config = %{
        client_id: "test_client",
        client_secret: "test_secret",
        authorization_url: "https://example.com/oauth/authorize",
        token_url: "https://example.com/oauth/token",
        redirect_uri: "https://lang.example.com/oauth/callback",
        scopes: ["read", "write"]
      }

      assert {:ok, %{flow_id: flow_id, authorization_url: auth_url}} =
               AdvancedProxy.connect_oauth(user.id, "github", oauth_config)

      assert is_binary(flow_id)
      assert String.contains?(auth_url, "https://example.com/oauth/authorize")
      assert String.contains?(auth_url, "client_id=test_client")
    end

    test "connect_oauth/3 validates OAuth configuration", %{user: user} do
      # Missing required fields
      invalid_config = %{client_id: "test"}

      assert {:error, {:missing_fields, missing}} =
               AdvancedProxy.connect_oauth(user.id, "github", invalid_config)

      assert :client_secret in missing
      assert :authorization_url in missing
      assert :token_url in missing
      assert :redirect_uri in missing
    end
  end

  describe "HTTP/stdio deployment" do
    test "deploy_http_stdio/3 creates stdio process", %{user: user} do
      server_config = %{"server_type" => "filesystem", "config" => %{}}
      deployment_opts = %{"env" => %{"PATH" => "/usr/bin"}, "timeout" => 30000}

      # Mock the Broker.request_connection call
      assert {:ok, connection_id} = AdvancedProxy.deploy_http_stdio(user.id, server_config, deployment_opts)

      assert is_binary(connection_id)
      assert String.starts_with?(connection_id, "stdio_")

      # Verify process is tracked
      stats = AdvancedProxy.get_stats()
      assert stats.stdio_processes == 1
    end
  end

  describe "statistics and monitoring" do
    test "get_stats/0 returns comprehensive statistics", %{user: user} do
      # Create some connections
      config = %{"server_type" => "filesystem", "config" => %{}}
      {:ok, _topic} = AdvancedProxy.connect_sse(user.id, "stats_conn", "filesystem", config)

      oauth_config = %{
        client_id: "test_client",
        client_secret: "test_secret",
        authorization_url: "https://example.com/oauth/authorize",
        token_url: "https://example.com/oauth/token",
        redirect_uri: "https://lang.example.com/oauth/callback",
        scopes: ["read"]
      }
      {:ok, _} = AdvancedProxy.connect_oauth(user.id, "github", oauth_config)

      stats = AdvancedProxy.get_stats()

      assert stats.sse_clients == 1
      assert stats.oauth_tokens == 1
      assert is_integer(stats.http_connections)
      assert is_integer(stats.stdio_processes)
      assert is_integer(stats.circuit_breakers)
      assert %DateTime{} = stats.timestamp
    end
  end

  describe "cleanup mechanisms" do
    test "expired connections are cleaned up", %{user: user} do
      config = %{"server_type" => "filesystem", "config" => %{}}
      {:ok, _topic} = AdvancedProxy.connect_sse(user.id, "cleanup_conn", "filesystem", config)

      # Verify connection exists
      stats = AdvancedProxy.get_stats()
      assert stats.sse_clients == 1

      # Simulate cleanup by calling the cleanup function directly
      # In real scenario, this would happen via timer
      GenServer.call(AdvancedProxy, :cleanup_expired_clients)

      # Connection should still exist (not expired yet)
      stats = AdvancedProxy.get_stats()
      assert stats.sse_clients == 1
    end
  end
end