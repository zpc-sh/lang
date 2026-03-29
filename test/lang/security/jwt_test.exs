defmodule Lang.Security.JWTTest do
  use ExUnit.Case, async: true

  test "sign and verify with HS256 secret" do
    # Ensure a deterministic HS256 env for the test
    secret = :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)
    prev = System.get_env("LSP_JWT_HS256_SECRET")
    System.put_env("LSP_JWT_HS256_SECRET", secret)

    on_exit(fn ->
      if prev, do: System.put_env("LSP_JWT_HS256_SECRET", prev), else: System.delete_env("LSP_JWT_HS256_SECRET")
    end)

    claims = %{"sub" => "user_1", "org" => "org_1", "scope" => "lsp_ws"}
    assert {:ok, token} = Lang.Security.JWT.sign_ticket(claims, ttl: 60)
    assert is_binary(token)

    assert {:ok, fields} = Lang.Security.JWT.verify_ticket(token)
    assert fields["sub"] == "user_1"
    assert fields["org"] == "org_1"
    assert fields["scope"] == "lsp_ws"
    assert is_integer(fields["exp"]) and is_integer(fields["iat"]) and fields["exp"] > fields["iat"]
  end
end

