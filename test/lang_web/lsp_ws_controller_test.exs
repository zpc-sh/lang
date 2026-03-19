defmodule LangWeb.LspWsControllerTest do
  use LangWeb.ConnCase, async: true

  setup do
    # Ensure HS256 path for predictable tests
    prev = System.get_env("LSP_JWT_HS256_SECRET")
    System.put_env("LSP_JWT_HS256_SECRET", "test-secret-0123456789abcdef")
    on_exit(fn -> if prev, do: System.put_env("LSP_JWT_HS256_SECRET", prev), else: System.delete_env("LSP_JWT_HS256_SECRET") end)
    :ok
  end

  test "returns 401 when ticket is missing", %{conn: conn} do
    conn = get(conn, "/ws/lsp")
    assert json_response(conn, 401)["error"] == "invalid_or_missing_ticket"
  end

  test "returns 401 when ticket is invalid", %{conn: conn} do
    conn = get(conn, "/ws/lsp?ticket=not-a-token")
    assert json_response(conn, 401)["error"] == "invalid_or_missing_ticket"
  end
end

