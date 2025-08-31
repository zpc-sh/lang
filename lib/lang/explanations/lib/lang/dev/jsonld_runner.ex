defmodule Lang.Dev.JSONLDRunner do
  @moduledoc """
  Dev-only JSON-LD action runner.

  Overview
  - Validates dev mode via `:dev_routes` and delegates dispatch to `Lang.DevKit.JSONLDActions`.
  - Keeps this app's concerns minimal so the DevKit can be extracted cleanly later.

  Typical flow
  - The Dev Hub or JSON‑LD Runner UI collects input.
  - `run/1` is called with a JSON map (already decoded).
  - `Lang.DevKit.JSONLDActions.dispatch/1` routes to a whitelisted action.

  See also
  - `Lang.DevKit.JSONLDActions` for registering custom actions at runtime.
  """

  def validate(env_enabled? \\ Application.get_env(:lang, :dev_routes)) do
    if env_enabled?, do: :ok, else: {:error, :dev_routes_disabled}
  end

  def allowed_actions, do: Codex.DevKit.JSONLDActions.allowed()

  def run(payload) when is_map(payload) do
    with :ok <- validate() do
      Lang.DevKit.JSONLDActions.dispatch(payload)
  end
end
end
