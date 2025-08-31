defmodule Lang.Dev.Config do
  @moduledoc """
  Configuration helpers for the dev model pipeline within Lang.

  Allows swapping adapters later without refactoring call sites.
  """

  @app :lang

  @spec jsonld_dir() :: String.t()
  def jsonld_dir do
    :code.priv_dir(@app) |> to_string() |> Path.join(["dev", "jsonld"]) |> Path.expand()
  end

  @spec docs_dir() :: String.t()
  def docs_dir do
    :code.priv_dir(@app) |> to_string() |> Path.join(["docs", "rendered"]) |> Path.expand()
  end

  @spec events_prefix() :: String.t()
  def events_prefix, do: Application.get_env(@app, :dev_models_events_prefix, "dev:models")

  @spec fs_adapter() :: module()
  def fs_adapter, do: Application.get_env(@app, :dev_models_fs_adapter, Lang.Dev.FSAdapter.Default)

  @spec validator() :: module()
  def validator, do: Application.get_env(@app, :dev_models_validator, Lang.Dev.Validator.Schema)

  @spec injection_scanner() :: module()
  def injection_scanner, do: Application.get_env(@app, :dev_models_injection_scanner, Lang.Dev.InjectionScanner)

  @spec diff_engine() :: module()
  def diff_engine, do: Application.get_env(@app, :dev_models_diff_engine, Lang.Dev.Diff)

  @spec event_emitter() :: module()
  def event_emitter, do: Application.get_env(@app, :dev_models_event_emitter, Lang.Events)
end
