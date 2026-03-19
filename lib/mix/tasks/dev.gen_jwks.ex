defmodule Mix.Tasks.Dev.GenJwks do
  use Mix.Task
  @shortdoc "Generate a static JWKS file from LSP_JWT_RS256_PUB_PEM into assets/static/.well-known/jwks.json"

  def run(_args) do
    Mix.Task.run("app.start")
    pem = System.get_env("LSP_JWT_RS256_PUB_PEM") || System.get_env("LSP_JWT_RS256_PRIV_PEM")
    path = Path.join(["assets", "static", ".well-known", "jwks.json"])
    File.mkdir_p!(Path.dirname(path))

    cond do
      is_nil(pem) or String.trim(pem) == "" ->
        Mix.shell().error("No RS256 PEM found in env (LSP_JWT_RS256_PUB_PEM or LSP_JWT_RS256_PRIV_PEM)")
        :ok
      Code.ensure_loaded?(JOSE) ->
        jwk = JOSE.JWK.from_pem(pem)
        {map, _} = JOSE.JWK.to_map(jwk)
        jwks = %{"keys" => [Map.put(map, "alg", "RS256")]}
        File.write!(path, Jason.encode!(jwks, pretty: true))
        Mix.shell().info("Wrote #{path}")
      true ->
        Mix.shell().error("JOSE library not available; cannot generate JWKS")
    end
  end
end

