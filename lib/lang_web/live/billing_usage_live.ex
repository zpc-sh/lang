defmodule LangWeb.BillingUsageLive do
  use LangWeb, :live_view
  import Ash.Query

  @impl true
  def mount(_params, _session, socket) do
    org = socket.assigns[:current_org]
    filters = %{granularity: :day, kind: :api_requests}
    {summary, aggregates} = load_data(org && org.id, filters)

    {:ok,
     socket
     |> assign(:page_title, "Billing Usage")
     |> assign(:filters, filters)
     |> assign(:form, to_form(filters, as: :filters))
     |> assign(:summary, summary)
     |> assign(:aggregates, aggregates)}
  end

  defp load_data(nil, _filters), do: {%{}, []}

  defp load_data(org_id, filters) do
    now = DateTime.utc_now()
    month_start = DateTime.beginning_of_month(now)

    gran = filters.granularity || :day
    kind = filters.kind || :api_requests

    api = read_aggregates(org_id, gran, :api_requests, month_start, now)
    mcp = read_aggregates(org_id, gran, :mcp_connections, month_start, now)

    api_total = Enum.reduce(api, 0, &(&1.total_requests + &2))
    mcp_total = Enum.reduce(mcp, 0, &(&1.total_mcp_connections + &2))
    size_total = Enum.reduce(api, 0, &(&1.total_content_size_bytes + &2))

    summary = %{
      api_requests: api_total,
      mcp_connections: mcp_total,
      api_content_size_bytes: size_total
    }

    {summary, api ++ mcp}
  end

  defp read_aggregates(org_id, granularity, kind, from, to) do
    case Lang.Billing.Aggregate
         |> Ash.Query.for_read(:by_org_and_period)
         |> Ash.Query.set_arguments(%{
           organization_id: org_id,
           granularity: granularity,
           kind: kind,
           from: from,
           to: to
         })
         |> Ash.read() do
      {:ok, list} -> list
      _ -> []
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={assigns[:current_user]} current_scope={assigns[:current_scope]}>
      <.header>
        Billing Usage
        <:subtitle>Current month usage summary for your organization.</:subtitle>
      </.header>

      <div class="mb-4">
        <.form for={@form} phx-change="filter" id="usage-filter-form">
          <.input
            field={@form[:granularity]}
            type="select"
            label="Granularity"
            options={[{"Hour", :hour}, {"Day", :day}, {"Month", :month}]}
          />
          <.input
            field={@form[:kind]}
            type="select"
            label="Kind"
            options={[{"API Requests", :api_requests}, {"MCP Connections", :mcp_connections}]}
          />
        </.form>
      </div>

      <div class="grid grid-cols-3 gap-4 my-4">
        <div class="p-4 rounded bg-gray-800 text-white">
          <div class="text-sm text-gray-400">API Requests</div>
          <div class="text-2xl font-semibold">{@summary[:api_requests] || 0}</div>
        </div>
        <div class="p-4 rounded bg-gray-800 text-white">
          <div class="text-sm text-gray-400">MCP Connections</div>
          <div class="text-2xl font-semibold">{@summary[:mcp_connections] || 0}</div>
        </div>
        <div class="p-4 rounded bg-gray-800 text-white">
          <div class="text-sm text-gray-400">API Content (bytes)</div>
          <div class="text-2xl font-semibold">{@summary[:api_content_size_bytes] || 0}</div>
        </div>
      </div>

      <h3 class="text-lg font-semibold mt-6">Recent Aggregates</h3>
      <div class="mt-2 space-y-2">
        <%= for a <- @aggregates do %>
          <div class="p-3 rounded border border-gray-200">
            <div class="text-sm text-gray-500">
              Period: {a.period_start} – {a.period_end} | {a.granularity} | {a.kind}
            </div>
            <div class="text-sm">
              Requests: {a.total_requests} | MCP: {a.total_mcp_connections} | Size(bytes): {a.total_content_size_bytes}
            </div>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("filter", %{"filters" => params}, socket) do
    filters = %{
      granularity: parse_atom(params["granularity"]) || :day,
      kind: parse_atom(params["kind"]) || :api_requests
    }

    org = socket.assigns[:current_org]
    {summary, aggregates} = load_data(org && org.id, filters)

    {:noreply,
     socket
     |> assign(:filters, filters)
     |> assign(:form, to_form(filters, as: :filters))
     |> assign(:summary, summary)
     |> assign(:aggregates, aggregates)}
  end

  defp parse_atom(nil), do: nil

  defp parse_atom(str) when is_binary(str) do
    String.to_existing_atom(str)
  rescue
    ArgumentError -> String.to_atom(str)
  end
end
