defmodule LangWeb.ApiPortalLive do
  @moduledoc """
  API Portal - Key Management, Documentation & Testing

  The comprehensive API portal where customers can:
  - Generate and manage API keys
  - View interactive API documentation
  - Test API endpoints in real-time
  - Monitor API usage and rate limits
  - Access code examples and SDKs
  """

  use LangWeb, :live_view
  alias Lang.Accounts
  alias Lang.Events

  @impl true
  def mount(_params, _session, socket) do
    # Use assigned current_user from authenticated live_session; fallback in dev
    socket = ensure_current_user(socket)

    if connected?(socket) and socket.assigns.current_user do
      # Subscribe to real-time API key updates
      Phoenix.PubSub.subscribe(Lang.PubSub, "user:#{socket.assigns.current_user.id}:api_keys")
    end

    socket =
      socket
      |> assign(:page_title, "API Portal")
      |> assign(:active_tab, "keys")
      |> assign(:selected_endpoint, nil)
      |> assign(:test_request, %{})
      |> assign(:test_response, nil)
      |> assign(:show_api_key, false)
      |> load_portal_data()

    {:ok, socket}
  end

  # Temporary authentication fallback for development
  defp ensure_current_user(socket) do
    case socket.assigns do
      %{current_user: %{} = user} ->
        socket

      _ ->
        # Create a mock user for development
        mock_user = %{
          id: "dev_user_123",
          email: "dev@example.com",
          name: "Development User",
          organization_id: "dev_org_123"
        }

        socket
        |> assign(:current_user, mock_user)
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    active_tab = Map.get(params, "tab", "keys")
    endpoint = Map.get(params, "endpoint")

    socket =
      socket
      |> assign(:active_tab, active_tab)
      |> assign(:selected_endpoint, endpoint)

    {:noreply, socket}
  end

  @impl true
  def handle_event("change_tab", %{"tab" => tab}, socket) do
    socket =
      socket
      |> assign(:active_tab, tab)
      |> push_patch(to: ~p"/api-portal?tab=#{tab}")

    {:noreply, socket}
  end

  @impl true
  def handle_event("generate_api_key", %{"name" => name}, socket) do
    case generate_api_key(socket.assigns.current_user.id, name) do
      {:ok, api_key} ->
        socket =
          socket
          |> put_flash(:info, "API key generated successfully!")
          |> assign(:new_api_key, api_key)
          |> assign(:show_api_key, true)
          |> load_portal_data()

        {:noreply, socket}

      {:error, reason} ->
        socket = put_flash(socket, :error, "Failed to generate API key: #{reason}")
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("revoke_api_key", %{"key_id" => key_id}, socket) do
    case revoke_api_key(key_id) do
      {:ok, _} ->
        socket =
          socket
          |> put_flash(:info, "API key revoked successfully")
          |> load_portal_data()

        {:noreply, socket}

      {:error, reason} ->
        socket = put_flash(socket, :error, "Failed to revoke API key: #{reason}")
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("test_endpoint", params, socket) do
    endpoint = socket.assigns.selected_endpoint
    test_params = Map.get(params, "test", %{})

    case test_api_endpoint(endpoint, test_params, socket.assigns.current_user) do
      {:ok, response} ->
        socket =
          socket
          |> assign(:test_response, response)
          |> put_flash(:info, "API test completed successfully")

        {:noreply, socket}

      {:error, reason} ->
        socket =
          socket
          |> assign(:test_response, %{error: reason})
          |> put_flash(:error, "API test failed: #{reason}")

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("select_endpoint", %{"endpoint" => endpoint}, socket) do
    socket =
      socket
      |> assign(:selected_endpoint, endpoint)
      |> assign(:test_response, nil)
      |> push_patch(to: ~p"/api-portal?tab=docs&endpoint=#{endpoint}")

    {:noreply, socket}
  end

  @impl true
  def handle_event("copy_api_key", %{"key" => key}, socket) do
    # Client-side copying will be handled by JavaScript
    socket = put_flash(socket, :info, "API key copied to clipboard")
    {:noreply, socket}
  end

  @impl true
  def handle_event("hide_api_key", _params, socket) do
    socket = assign(socket, :show_api_key, false)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:api_key_updated, _data}, socket) do
    {:noreply, load_portal_data(socket)}
  end

  # Private Functions

  defp load_portal_data(socket) do
    user = socket.assigns.current_user
    org = fetch_organization(user.organization_id)

    # Load API keys
    api_keys = get_user_api_keys(user.id)

    # Load usage statistics
    api_usage = get_api_usage_stats(user.id)

    # Load rate limiting info
    rate_limits = get_rate_limits(org)

    socket
    |> assign(:api_keys, api_keys)
    |> assign(:api_usage, api_usage)
    |> assign(:rate_limits, rate_limits)
    |> assign(:organization, org)
    |> assign(:api_endpoints, get_api_endpoints())
  end

  defp get_user_api_keys(user_id) do
    case Lang.Accounts.ApiKey.list_by_user(user_id: user_id) do
      {:ok, api_keys} ->
        Enum.map(api_keys, fn key ->
          %{
            id: key.id,
            name: key.name,
            key: Lang.Accounts.ApiKey.display_key(key),
            created_at: key.inserted_at,
            last_used_at: key.last_used_at,
            usage_count: key.usage_count,
            status: key.status
          }
        end)

      {:error, _} ->
        []
    end
  end

  defp get_api_usage_stats(user_id) do
    import Ash.Query

    case Lang.Accounts.APIUsage
         |> Ash.Query.for_read(:recent_usage, %{user_id: user_id, limit: 200})
         |> Ash.read() do
      {:ok, usages} ->
        total = length(usages)
        success = Enum.count(usages, &(&1.status == :success))
        failed = Enum.count(usages, &(&1.status == :error))
        rate_limited = Enum.count(usages, &(&1.status == :rate_limited))

        avg_ms =
          usages
          |> Enum.map(&(&1.processing_time_ms || 0))
          |> case do
            [] -> 0
            times -> Enum.sum(times) |> div(max(1, length(times)))
          end

        %{
          total_requests: total,
          successful_requests: success,
          failed_requests: failed,
          rate_limited_requests: rate_limited,
          avg_response_time: avg_ms,
          daily_usage: generate_daily_api_usage(),
          top_endpoints: []
        }

      _ ->
        %{
          total_requests: 0,
          successful_requests: 0,
          failed_requests: 0,
          rate_limited_requests: 0,
          avg_response_time: 0,
          daily_usage: generate_daily_api_usage(),
          top_endpoints: []
        }
    end
  end

  defp get_rate_limits(organization) do
    tier = organization.plan || organization.subscription_tier || :free

    case tier do
      :free ->
        %{requests_per_minute: 10, requests_per_hour: 100, requests_per_day: 1000}

      :pro ->
        %{requests_per_minute: 100, requests_per_hour: 1000, requests_per_day: 10_000}

      :enterprise ->
        %{requests_per_minute: 1000, requests_per_hour: 10_000, requests_per_day: 100_000}

      _ ->
        %{requests_per_minute: 10, requests_per_hour: 100, requests_per_day: 1000}
    end
  end

  defp get_api_endpoints do
    [
      %{
        id: "analyze",
        name: "Text Analysis",
        method: "POST",
        path: "/api/v1/analyze",
        description: "Analyze text for readability, sentiment, language detection, and more",
        parameters: [
          %{
            name: "content",
            type: "string",
            required: true,
            description: "Text content to analyze"
          },
          %{
            name: "format",
            type: "string",
            required: false,
            description: "Content format (text, markdown, json)"
          },
          %{
            name: "include_style",
            type: "boolean",
            required: false,
            description: "Include stylometric analysis"
          }
        ],
        example_request: %{
          content:
            "This is a sample text for analysis. It contains multiple sentences to demonstrate the API capabilities.",
          format: "text",
          include_style: true
        },
        example_response: %{
          quality_score: 85,
          readability: %{score: 72, level: "Standard"},
          language: %{language: "English", confidence: 0.95},
          sentiment: %{sentiment: "Positive", score: 0.3},
          word_count: 18,
          character_count: 106
        }
      },
      %{
        id: "detect_language",
        name: "Language Detection",
        method: "POST",
        path: "/api/v1/detect-language",
        description: "Detect the language of text content with confidence scoring",
        parameters: [
          %{
            name: "content",
            type: "string",
            required: true,
            description: "Text content for language detection"
          }
        ],
        example_request: %{
          content: "Bonjour, comment allez-vous aujourd'hui?"
        },
        example_response: %{
          language: "French",
          confidence: 0.98,
          alternatives: [
            %{language: "Italian", confidence: 0.15},
            %{language: "Spanish", confidence: 0.08}
          ]
        }
      },
      %{
        id: "sentiment",
        name: "Sentiment Analysis",
        method: "POST",
        path: "/api/v1/sentiment",
        description: "Analyze the emotional tone and sentiment of text",
        parameters: [
          %{
            name: "content",
            type: "string",
            required: true,
            description: "Text content for sentiment analysis"
          }
        ],
        example_request: %{
          content: "I absolutely love this new product! It's amazing and works perfectly."
        },
        example_response: %{
          sentiment: "Positive",
          score: 0.87,
          confidence: 0.92,
          emotions: %{
            joy: 0.78,
            love: 0.65,
            excitement: 0.54
          }
        }
      },
      %{
        id: "conversation",
        name: "Conversation Rehearsal",
        method: "POST",
        path: "/api/v1/conversation",
        description: "Generate conversation scenarios and practice responses",
        parameters: [
          %{
            name: "scenario",
            type: "string",
            required: true,
            description: "Conversation scenario type"
          },
          %{
            name: "message",
            type: "string",
            required: true,
            description: "Current message or prompt"
          },
          %{
            name: "context",
            type: "object",
            required: false,
            description: "Additional conversation context"
          }
        ],
        example_request: %{
          scenario: "job_interview",
          message: "Tell me about your greatest weakness",
          context: %{position: "Software Engineer", company: "TechCorp"}
        },
        example_response: %{
          responses: [
            %{
              text:
                "I sometimes focus too much on perfection, but I've learned to balance quality with deadlines",
              strategy: "honest_improvement",
              effectiveness: 0.85
            }
          ]
        }
      }
    ]
  end

  defp fetch_organization(org_id) do

    import Ash.Query
    case Lang.Accounts.Organization
         |> filter(id == ^org_id)
         |> Ash.read_one() do
      {:ok, nil} ->
        %{
          id: org_id,
          name: "Organization",
          plan: :free,
          subscription_tier: :free,
          monthly_request_limit: 1000,
          monthly_request_count: 0
        }

      {:ok, org} ->
        %{
          id: org.id,
          name: org.name,
          plan: org.plan || org.subscription_tier || :free,
          subscription_tier: org.subscription_tier || org.plan || :free,
          monthly_request_limit: org.monthly_request_limit,
          monthly_request_count: org.monthly_request_count
        }

      {:error, _} ->
        %{
          id: org_id,
          name: "Organization",
          plan: :free,
          subscription_tier: :free,
          monthly_request_limit: 1000,
          monthly_request_count: 0
        }
    end
  end

  defp generate_api_key(user_id, name) do
    # Get user's organization
    case Lang.Accounts.User.by_id(user_id) do
      {:ok, user} ->
        attrs = %{
          name: name,
          user_id: user_id,
          organization_id: user.organization_id
        }

        case Lang.Accounts.ApiKey.create(attrs) do
          {:ok, api_key} ->
            {:ok,
             %{
               id: api_key.id,
               name: api_key.name,
               key: api_key.key,
               created_at: api_key.inserted_at,
               last_used_at: api_key.last_used_at,
               usage_count: api_key.usage_count,
               status: api_key.status
             }}

          {:error, _changeset} ->
            {:error, "Failed to create API key"}
        end

      {:error, _} ->
        {:error, "User not found"}
    end
  end

  defp revoke_api_key(key_id) do
    case Lang.Accounts.ApiKey.by_id(key_id) do
      {:ok, api_key} ->
        case Lang.Accounts.ApiKey.revoke(api_key) do
          {:ok, _updated_key} -> {:ok, :revoked}
          {:error, _changeset} -> {:error, "Failed to revoke API key"}
        end

      {:error, _} ->
        {:error, "API key not found"}
    end
  end

  defp test_api_endpoint(endpoint_id, _params, _user) do
    # TODO: Implement actual API endpoint testing
    case endpoint_id do
      "analyze" ->
        {:ok,
         %{
           quality_score: 78,
           readability: %{score: 65, level: "Standard"},
           language: %{language: "English", confidence: 0.92},
           processing_time_ms: 142
         }}

      "detect_language" ->
        {:ok,
         %{
           language: "English",
           confidence: 0.95,
           alternatives: []
         }}

      "sentiment" ->
        {:ok,
         %{
           sentiment: "Neutral",
           score: 0.05,
           confidence: 0.87
         }}

      _ ->
        {:error, "Unknown endpoint"}
    end
  end

  defp generate_daily_api_usage do
    # Generate last 30 days of API usage
    for day <- 29..0//-1 do
      date = Date.add(Date.utc_today(), -day)
      base_usage = :rand.uniform(1000) + 500

      %{
        date: Calendar.strftime(date, "%m/%d"),
        requests: base_usage,
        success_rate: :rand.uniform(5) + 95
      }
    end
  end

  defp format_api_key(key) do
    case String.length(key) do
      len when len > 12 ->
        prefix = String.slice(key, 0, 8)
        suffix = String.slice(key, -4, 4)
        "#{prefix}...#{suffix}"

      _ ->
        key
    end
  end

  defp status_badge_class(status) do
    case status do
      :active -> "bg-green-100 text-green-800"
      :revoked -> "bg-red-100 text-red-800"
      :expired -> "bg-yellow-100 text-yellow-800"
      _ -> "bg-gray-100 text-gray-800"
    end
  end

  defp method_badge_class(method) do
    case method do
      "GET" -> "bg-blue-100 text-blue-800"
      "POST" -> "bg-green-100 text-green-800"
      "PUT" -> "bg-yellow-100 text-yellow-800"
      "DELETE" -> "bg-red-100 text-red-800"
      _ -> "bg-gray-100 text-gray-800"
    end
  end

  defp format_datetime(datetime) do
    case datetime do
      nil -> "Never"
      dt -> Calendar.strftime(dt, "%b %d, %Y at %I:%M %p")
    end
  end

  defp format_number(number) when is_integer(number) do
    Number.Delimit.number_to_delimited(number, delimiter: ",")
  end

  defp format_number(number) when is_float(number) do
    :erlang.float_to_binary(number, decimals: 1)
  end

  defp format_number(number), do: to_string(number)
end
