defmodule Lang.Proxy.SessionTransformer do
  @moduledoc """
  Transform a validated JSON-LD Session into a proxy pipeline route.

  Returns {:ok, route} or {:error, reason}.
  """

  alias Lang.Proxy.Intent

  @spec to_route(map(), map()) :: {:ok, [map()]} | {:error, term()}
  def to_route(%{"protocol" => "ssh"} = sess, assigns) do
    host = sess["host"]
    user = sess["user"]
    cmd = sess["cmd"] || sess["command"]

    hop = %{
      service: "lsp",
      method: "lsp.bootstrap_ssh",
      params: %{"host" => host, "user" => user, "cmd" => cmd}
    }

    {:ok, [maybe_attach_intent(hop, assigns)]}
  end

  def to_route(%{"protocol" => "lsp", "operation" => op} = sess, assigns) do
    case String.downcase(to_string(op)) do
      "symbols" ->
        file_path = sess["file_path"] || sess["path"]
        {:ok, [%{service: "lsp", method: "lsp.symbols", params: %{"file_path" => file_path}}]}

      other -> {:error, {:unsupported_lsp_operation, other}}
    end
  end

  def to_route(_sess, _assigns), do: {:ok, []}

  defp maybe_attach_intent(hop, assigns) do
    if Application.get_env(:lang, :require_intent_for_sensitive, false) do
      org_id = assigns[:current_org] && assigns.current_org.id
      user_id = assigns[:current_user] && assigns.current_user.id
      claims = %{
        "org_id" => org_id,
        "user_id" => user_id,
        "service" => hop.service,
        "method" => hop.method,
        "scope" => ["ssh:bootstrap"],
        "exp" => System.os_time(:second) + 300,
        "nonce" => Base.encode64(:crypto.strong_rand_bytes(12))
      }

      case Intent.sign(claims) do
        {:ok, tok} -> put_in(hop, [:params, "intent"], tok)
        _ -> hop
      end
    else
      hop
    end
  end
end

