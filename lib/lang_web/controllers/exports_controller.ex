defmodule LangWeb.ExportsController do
  use LangWeb, :controller
  require Logger

  # Authenticated via browser_json in authenticated live session scope
  def download(conn, %{"id" => id} = params) do
    if Code.ensure_loaded?(Redix) do
      case fetch_export(id) do
        {:ok, content} ->
          case String.downcase(to_string(Map.get(params, "format", "ndjson"))) do
            "zip" -> send_zip(conn, id, content)
            _ -> send_ndjson(conn, id, content)
          end
        :not_found -> conn |> put_status(:not_found) |> text("Export not found or expired")
        {:error, reason} ->
          Logger.warning("Export download failed", reason: inspect(reason))
          conn |> put_status(:internal_server_error) |> text("Failed to fetch export")
      end
    else
      conn |> put_status(:service_unavailable) |> text("Exports storage unavailable")
    end
  end

  # Bundle multiple export ids into a single ZIP
  def bundle(conn, %{"ids" => ids_param} = params) do
    ids =
      ids_param
      |> to_string()
      |> String.split([",", " "], trim: true)
      |> Enum.uniq()

    names =
      params
      |> Map.get("names", "")
      |> to_string()
      |> String.split([",", " "], trim: true)

    entries =
      ids
      |> Enum.with_index()
      |> Enum.reduce([], fn {id, idx}, acc ->
        case fetch_export(id) do
          {:ok, content} ->
            name = Enum.at(names, idx) || (id <> ".ndjson")
            [{to_charlist(name), content} | acc]
          _ -> acc
        end
      end)
      |> Enum.reverse()

    case entries do
      [] -> conn |> put_status(:not_found) |> text("No valid exports to bundle")
      entries -> send_zip_entries(conn, "bundle", entries)
    end
  end

  # Return a signed URL for an export id or bundle
  def sign(conn, params) do
    secret = System.get_env("EXPORTS_SIGNING_SECRET") || System.get_env("SECRET_KEY_BASE")
    if is_binary(secret) and byte_size(secret) > 0 do
      exp_secs = params |> Map.get("exp_secs", "600") |> to_string() |> String.to_integer()
      exp = System.os_time(:second) + exp_secs

      case params do
        %{"id" => id} ->
          sig = generate_signature(id <> ":" <> to_string(exp), secret)
          format = params |> Map.get("format", "ndjson") |> to_string()
          url = "/dl/exports/" <> id <> "?sig=" <> sig <> "&exp=" <> to_string(exp) <> "&format=" <> format
          json(conn, %{url: url, id: id, exp: exp})

        %{"ids" => ids_param} ->
          ids = ids_param |> to_string() |> String.split([",", " "], trim: true) |> Enum.uniq() |> Enum.join(",")
          sig = generate_signature(ids <> ":" <> to_string(exp), secret)
          url = "/dl/exports/bundle?ids=" <> URI.encode_www_form(ids) <> "&sig=" <> sig <> "&exp=" <> to_string(exp)
          json(conn, %{url: url, ids: ids, exp: exp})

        _ ->
          conn |> put_status(:bad_request) |> json(%{error: "id or ids required"})
      end
    else
      conn |> put_status(:service_unavailable) |> json(%{error: "signing secret unavailable"})
    end
  end

  # Public signed-download endpoint (no session required)
  def signed_download(conn, %{"id" => id} = params) do
    with :ok <- verify_sig(params),
         {:ok, content} <- fetch_export(id) do
      case String.downcase(to_string(Map.get(params, "format", "ndjson"))) do
        "zip" -> send_zip(conn, id, content)
        _ -> send_ndjson(conn, id, content)
      end
    else
      {:error, :unauthorized} -> conn |> put_status(:forbidden) |> text("invalid signature")
      :not_found -> conn |> put_status(:not_found) |> text("not found")
      {:error, _} -> conn |> put_status(:internal_server_error) |> text("error")
    end
  end

  def signed_bundle(conn, %{"ids" => ids_param} = params) do
    with :ok <- verify_sig(params) do
      bundle(conn, %{ids: ids_param, names: Map.get(params, "names")})
    else
      {:error, :unauthorized} -> conn |> put_status(:forbidden) |> text("invalid signature")
    end
  end

  defp fetch_export(id) do
    base = "export:" <> id
    with {:ok, parts} <- Redix.command(Lang.Redis, ["GET", base <> ":parts"]) do
      case parts do
        nil ->
          case Redix.command(Lang.Redis, ["GET", base]) do
            {:ok, nil} -> :not_found
            {:ok, content} -> {:ok, content}
            other -> other
          end

        parts_bin when is_binary(parts_bin) ->
          count = String.to_integer(parts_bin)
          chunks =
            for i <- 1..count do
              case Redix.command(Lang.Redis, ["GET", "#{base}:part:#{i}"]) do
                {:ok, bin} when is_binary(bin) -> bin
                _ -> <<>>
              end
            end

          {:ok, IO.iodata_to_binary(chunks)}
      end
    end
  end

  defp send_ndjson(conn, id, content) do
    conn
    |> put_resp_content_type("application/x-ndjson")
    |> put_resp_header("content-disposition", ~s(attachment; filename="#{id}.ndjson"))
    |> send_resp(200, content)
  end

  defp send_zip(conn, id, content) do
    filename = to_charlist(id <> ".ndjson")
    entries = [{filename, content}]
    case :zip.create('mem.zip', entries, [:memory]) do
      {:ok, {_, zipbin}} ->
        conn
        |> put_resp_content_type("application/zip")
        |> put_resp_header("content-disposition", ~s(attachment; filename="#{id}.zip"))
        |> send_resp(200, zipbin)
      {:error, reason} ->
        Logger.warning("Zip creation failed", reason: inspect(reason))
        send_ndjson(conn, id, content)
    end
  end

  defp send_zip_entries(conn, id, entries) do
    case :zip.create('mem.zip', entries, [:memory]) do
      {:ok, {_, zipbin}} ->
        conn
        |> put_resp_content_type("application/zip")
        |> put_resp_header("content-disposition", ~s(attachment; filename="#{id}.zip"))
        |> send_resp(200, zipbin)
      {:error, reason} ->
        Logger.warning("Zip creation failed", reason: inspect(reason))
        conn |> put_status(:internal_server_error) |> text("zip error")
    end
  end

  defp verify_sig(%{"sig" => sig, "exp" => exp} = params) do
    secret = System.get_env("EXPORTS_SIGNING_SECRET") || System.get_env("SECRET_KEY_BASE")
    with true <- is_binary(secret) and byte_size(secret) > 0,
         {:ok, exp_i} <- parse_int(exp),
         true <- System.os_time(:second) <= exp_i,
         payload <- build_payload(params),
         ^sig <- generate_signature(payload, secret) do
      :ok
    else
      _ -> {:error, :unauthorized}
    end
  end
  defp verify_sig(_), do: {:error, :unauthorized}

  defp build_payload(%{"id" => id, "exp" => exp}), do: id <> ":" <> to_string(exp)
  defp build_payload(%{"ids" => ids, "exp" => exp}), do: ids <> ":" <> to_string(exp)

  defp generate_signature(payload, secret) do
    :crypto.mac(:hmac, :sha256, secret, payload) |> Base.url_encode64(padding: false)
  end

  defp sign_payload(payload, secret) do
    generate_signature(payload, secret)
  end

  defp parse_int(val) do
    case Integer.parse(to_string(val)) do
      {n, _} -> {:ok, n}
      _ -> :error
    end
  end
end
