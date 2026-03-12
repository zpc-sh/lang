defmodule Lang.Api do
  @moduledoc """
  API configuration for LANG Universal Text Intelligence Platform.

  This module provides JSON API endpoints for resource management.
  Currently simplified while AshJsonApi integration is being completed.
  """

  # Placeholder for AshJsonApi integration
  # TODO: Implement proper AshJsonApi routes once auth system is complete

  @doc """
  Returns available API versions and endpoints.
  """
  def versions do
    %{
      v1: %{
        base_url: "/api/v1",
        resources: [
          "users",
          "organizations",
          "api-keys"
        ],
        auth_required: true
      }
    }
  end

  @doc """
  Returns API documentation structure.
  """
  def docs do
    %{
      title: "LANG API",
      version: "1.0.0",
      description: "Universal Text Intelligence Platform API",
      endpoints: %{
        users: %{
          post: "/api/v1/users",
          get: "/api/v1/users/:id",
          patch: "/api/v1/users/:id",
          delete: "/api/v1/users/:id"
        },
        organizations: %{
          get: "/api/v1/organizations/:id",
          patch: "/api/v1/organizations/:id"
        },
        api_keys: %{
          get: "/api/v1/api-keys",
          post: "/api/v1/api-keys",
          patch: "/api/v1/api-keys/:id",
          delete: "/api/v1/api-keys/:id"
        }
      }
    }
  end

  @doc """
  Return a summary of loaded Ash domains and their resources.
  Used by deployment verification.
  """
  def resources do
    domains = [
      Lang.Analyses,
      Lang.Spatial,
      Lang.Think,
      Lang.Generate,
      Lang.Accounts,
      Lang.Billing
    ]

    Enum.map(domains, fn domain ->
      resources =
        try do
          domain.resources()
        rescue
          _ -> []
        end

      %{domain: domain, resources: resources}
    end)
  end
end
