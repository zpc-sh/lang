defmodule Lang.Storage.Session do
  @moduledoc """
  Workspace session management for storage operations.

  This module provides a small in-memory session store used by LSP dispatch
  handlers and other features. It aligns with specs under `priv/lsp/specs` for
  `lang.storage.create_session`, `get_session`, `close_session`, and `sync_session`.
  """

  @store :storage_sessions

  @type session_id :: String.t()
  @type project_id :: String.t()
  @type session :: %{
          id: session_id(),
          project_id: project_id(),
          metadata: map(),
          created_at: DateTime.t()
        }

  @doc """
  Create a new session for a given project.
  """
  @spec create(project_id(), map()) :: {:ok, session()} | {:error, any()}
  def create(project_id, metadata \\ %{}) when is_binary(project_id) and is_map(metadata) do
    session = %{
      id: Ecto.UUID.generate(),
      project_id: project_id,
      metadata: metadata,
      created_at: DateTime.utc_now()
    }

    :ok = Lang.InMemory.Store.put(@store, session.id, session)
    {:ok, session}
  end

  @doc """
  Get an existing session by id.
  """
  @spec get(session_id()) :: {:ok, session()} | {:error, :not_found}
  def get(session_id) when is_binary(session_id) do
    case Lang.InMemory.Store.get(@store, session_id) do
      nil -> {:error, :not_found}
      session -> {:ok, session}
    end
  end

  @doc """
  Close (delete) a session by id.
  """
  @spec close(session_id()) :: :ok
  def close(session_id) when is_binary(session_id) do
    :ok = Lang.InMemory.Store.delete(@store, session_id)
  end

  @doc """
  Sync a session – currently a no-op that returns the stored session.
  """
  @spec sync(session_id()) :: {:ok, session()} | {:error, :not_found}
  def sync(session_id) when is_binary(session_id) do
    get(session_id)
  end
end
