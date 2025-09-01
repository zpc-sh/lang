defmodule Lang.Storage.Config do
  @moduledoc """
  Config helpers for storage integration, with safe defaults and env overrides.
  """

  def folder_enabled? do
    env_flag("LANG_FOLDER_ENABLED", false)
  end

  def inline_text_max_bytes do
    env_int("LANG_STORAGE_INLINE_TEXT_MAX_BYTES", 1_048_576)
  end

  def force_inline_binaries? do
    env_flag("LANG_STORAGE_FORCE_INLINE_BINARIES", false)
  end

  def preview_max_lines do
    env_int("LANG_STORAGE_PREVIEW_MAX_LINES", 500)
  end

  def preview_max_bytes do
    env_int("LANG_STORAGE_PREVIEW_MAX_BYTES", 65_536)
  end

  def manifest_cache_ttl do
    env_int("LANG_STORAGE_MANIFEST_CACHE_TTL", 60)
  end

  defp env_flag(key, default) do
    case System.get_env(key) do
      nil -> default
      v -> String.downcase(v) in ["1", "true", "yes", "on"]
    end
  end

  defp env_int(key, default) do
    case System.get_env(key) do
      nil -> default
      v ->
        case Integer.parse(v) do
          {i, _} when i >= 0 -> i
          _ -> default
        end
    end
  end
end
