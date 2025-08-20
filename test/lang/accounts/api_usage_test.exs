defmodule Lang.Accounts.APIUsageTest do
  use Lang.DataCase

  alias Lang.Accounts.{APIUsage, APIUsageLogger, User}

  describe "API usage logging" do
    setup do
      {:ok, user} =
        User.create(%{
          email: "test@example.com",
          name: "Test User",
          organization_name: "Test Org"
        })

      %{user: user}
    end

    test "logs basic API usage", %{user: user} do
      assert {:ok, usage_record} = APIUsageLogger.log_usage(user.id, :analyze)

      assert usage_record.user_id == user.id
      assert usage_record.operation_type == :analyze
      assert usage_record.status == :success
      assert usage_record.processed == false
      assert is_binary(usage_record.month_year)
    end

    test "logs usage with options", %{user: user} do
      opts = [
        status: :error,
        format: "javascript",
        content_size_bytes: 1024,
        processing_time_ms: 150,
        error_type: "syntax_error"
      ]

      assert {:ok, usage_record} = APIUsageLogger.log_usage(user.id, :analyze, opts)

      assert usage_record.status == :error
      assert usage_record.format == "javascript"
      assert usage_record.content_size_bytes == 1024
      assert usage_record.processing_time_ms == 150
      assert usage_record.error_type == "syntax_error"
    end

    test "gets current month usage", %{user: user} do
      # Create some usage records
      for _ <- 1..3 do
        APIUsageLogger.log_usage(user.id, :analyze)
      end

      assert {:ok, count} = APIUsageLogger.current_month_count(user.id)
      assert count >= 3
    end

    test "checks rate limits", %{user: user} do
      # User starts with 1000 monthly limit
      assert APIUsageLogger.is_over_limit?(user, 999) == false
      assert APIUsageLogger.is_over_limit?(user, 1001) == true
    end

    test "calculates usage percentage", %{user: user} do
      # Create some usage records (10 out of 1000)
      for _ <- 1..10 do
        APIUsageLogger.log_usage(user.id, :analyze)
      end

      assert {:ok, percentage} = APIUsageLogger.usage_percentage(user)
      assert percentage >= 1.0
      # Should be around 1%
      assert percentage <= 2.0
    end
  end

  describe "API usage resource" do
    setup do
      {:ok, user} =
        User.create(%{
          email: "test2@example.com",
          name: "Test User 2",
          organization_name: "Test Org 2"
        })

      %{user: user}
    end

    test "creates usage record directly", %{user: user} do
      attrs = %{
        user_id: user.id,
        operation_type: :lsp,
        status: :success,
        format: "typescript",
        processing_time_ms: 50
      }

      assert {:ok, usage} = APIUsage.log_usage(attrs)
      assert usage.user_id == user.id
      assert usage.operation_type == :lsp
      assert usage.format == "typescript"
    end

    test "validates required attributes" do
      # Missing user_id should fail
      assert {:error, _changeset} =
               APIUsage.log_usage(%{
                 operation_type: :analyze,
                 status: :success
               })
    end

    test "validates operation_type" do
      {:ok, user} =
        User.create(%{
          email: "test3@example.com",
          name: "Test User 3",
          organization_name: "Test Org 3"
        })

      # Valid operation type should work
      assert {:ok, _usage} =
               APIUsage.log_usage(%{
                 user_id: user.id,
                 operation_type: :analyze,
                 status: :success
               })

      # Invalid operation type should fail
      assert {:error, _changeset} =
               APIUsage.log_usage(%{
                 user_id: user.id,
                 operation_type: :invalid_operation,
                 status: :success
               })
    end
  end
end
