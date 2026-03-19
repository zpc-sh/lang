defmodule Lang.Events.ApiUsageEventTest do
  use Lang.DataCase

  alias Lang.Events.{ApiUsageEvent, ApiUsageLogger}
  alias Lang.Accounts.User

  describe "API usage event logging" do
    setup do
      {:ok, user} =
        User.create(%{
          email: "test@example.com",
          name: "Test User",
          organization_name: "Test Org"
        })

      %{user: user}
    end

    test "logs basic API usage event", %{user: user} do
      assert {:ok, event} = ApiUsageLogger.log_usage(user.id, :text_analysis)

      assert event.user_id == user.id
      assert event.operation_type == :text_analysis
      assert event.success == true
      assert event.organization_id == user.organization_id
    end

    test "logs usage with options", %{user: user} do
      opts = [
        status: :error,
        format: "javascript",
        content_size_bytes: 1024,
        processing_time_ms: 150,
        error_type: "syntax_error",
        metadata: %{"extra" => "data"}
      ]

      assert {:ok, event} = ApiUsageLogger.log_usage(user.id, :text_analysis, opts)

      assert event.success == false
      assert event.content_format == "javascript"
      assert event.content_size == 1024
      assert event.processing_time_ms == 150
      assert event.error_type == "syntax_error"
      assert event.metadata == %{"extra" => "data"}
    end

    test "logs analysis usage", %{user: user} do
      assert {:ok, event} =
               ApiUsageLogger.log_analysis_usage(user.id, "python", 2048, 200)

      assert event.operation_type == :text_analysis
      assert event.content_format == "python"
      assert event.content_size == 2048
      assert event.processing_time_ms == 200
    end

    test "logs LSP usage", %{user: user} do
      assert {:ok, event} =
               ApiUsageLogger.log_lsp_usage(user.id, "textDocument/hover", 50)

      assert event.operation_type == :lsp
      assert event.content_format == "textDocument/hover"
      assert event.processing_time_ms == 50
    end

    test "logs rate limited usage", %{user: user} do
      assert {:ok, event} =
               ApiUsageLogger.log_rate_limited_usage(user.id, :text_analysis)

      assert event.rate_limited == true
      assert event.success == false
    end

    test "gets current month count from cache", %{user: user} do
      # Create some events
      for _ <- 1..3 do
        ApiUsageLogger.log_usage(user.id, :text_analysis)
      end

      # Should hit cache
      assert {:ok, count} = ApiUsageLogger.current_month_count(user.id)
      assert count == 3
    end

    test "checks if user is over limit", %{user: user} do
      # User has default limit of 1000
      assert user.monthly_request_limit == 1000

      # Not over limit initially
      refute ApiUsageLogger.is_over_limit?(user)

      # Still not over with 999 requests
      refute ApiUsageLogger.is_over_limit?(user, 999)

      # Would be over with 1001 requests
      assert ApiUsageLogger.is_over_limit?(user, 1001)
    end

    test "calculates usage percentage", %{user: user} do
      # Create 100 events (10% of 1000 limit)
      for _ <- 1..100 do
        ApiUsageLogger.log_usage(user.id, :text_analysis)
      end

      assert {:ok, percentage} = ApiUsageLogger.usage_percentage(user)
      assert percentage == 10.0
    end

    test "subscribes to usage updates", %{user: user} do
      # Subscribe to updates
      ApiUsageLogger.subscribe_to_usage_updates(user.id)

      # Log usage
      {:ok, event} = ApiUsageLogger.log_usage(user.id, :text_analysis)

      # Should receive notification
      assert_receive {:usage_logged, ^event}
    end

    test "gets monthly stats", %{user: user} do
      # Create various events
      ApiUsageLogger.log_usage(user.id, :text_analysis, status: :success)
      ApiUsageLogger.log_usage(user.id, :text_analysis, status: :error)
      ApiUsageLogger.log_usage(user.id, :lsp, status: :rate_limited)

      assert {:ok, stats} = ApiUsageLogger.get_monthly_stats(user.id)

      assert stats.total_requests == 3
      assert stats.successful_requests == 1
      assert stats.error_requests == 1
      assert stats.rate_limited_requests == 1
    end
  end

  describe "unified API usage interface" do
    setup do
      {:ok, user} =
        User.create(%{
          email: "unified@example.com",
          name: "Unified User",
          organization_name: "Test Org"
        })

      %{user: user}
    end

    test "works with events backend", %{user: user} do
      # Ensure we're using events backend
      Application.put_env(:lang, :api_usage_backend, :events)

      assert {:ok, _event} = Lang.APIUsage.log_usage(user.id, :text_analysis)
      assert {:ok, count} = Lang.APIUsage.current_month_count(user.id)
      assert count > 0
    end

    test "can switch to legacy backend", %{user: user} do
      # Switch to legacy backend
      Application.put_env(:lang, :api_usage_backend, :legacy)

      assert {:ok, _usage} = Lang.APIUsage.log_usage(user.id, :analyze)

      # Switch back
      Application.put_env(:lang, :api_usage_backend, :events)
    end
  end
end
