defmodule Lang.Native.FSWatcher do
  @moduledoc """
  Native filesystem watcher (Rust NIF scaffold).

  Notes
  - Intended to provide OS-level change notifications (inotify/FSEvents/kqueue).
  - This module is a scaffold; functions raise until the NIF is implemented.
  - For bounded, polling-style watching, prefer `Lang.Native.FSScanner` with
    the `lang.fs.watch` Dispatch helper already implemented.
  """

  # NIF is intentionally not auto-loaded yet to avoid build failures while the
  # Rust export surface is being aligned. When ready, uncomment below and ensure
  # Rust exports match these functions.
  # use Rustler, otp_app: :lang, crate: "fs_watcher"

  # Minimal functions (return errors until NIF wired)
  def start_watch(_path, _opts), do: {:error, :nif_not_loaded}
  def stop_watch(_watch_id), do: {:error, :nif_not_loaded}
  def subscribe(_watch_id), do: {:error, :nif_not_loaded}

  @doc """
  Desired Elixir-side API shape once NIF exists.

  Returns `{:ok, %{watch_id: id, topic: topic}}` and emits PubSub events:
  - `{:fs_event, watch_id, %{path: path, kind: :modified|:created|:deleted}}`
  - `{:fs_watch_complete, watch_id}` when stopped.
  """
  def watch(path, opts \\ []) when is_binary(path) do
    start_watch(path, normalize_opts(opts))
  end

  defp normalize_opts(opts) do
    %{
      include_globs: Keyword.get(opts, :include_globs, []),
      exclude_globs: Keyword.get(opts, :exclude_globs, []),
      max_depth: Keyword.get(opts, :max_depth, 0),
      topic: Keyword.get(opts, :topic)
    }
  end
end
