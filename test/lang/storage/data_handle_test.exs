defmodule Lang.Storage.DataHandleTest do
  use ExUnit.Case, async: true

  alias Lang.Storage.DataHandle

  setup do
    prev_handles = Application.get_env(:lang, :storage_data_handles)
    prev_policy = Application.get_env(:lang, :storage_data_handle_policy)

    on_exit(fn ->
      if prev_handles == nil,
        do: Application.delete_env(:lang, :storage_data_handles),
        else: Application.put_env(:lang, :storage_data_handles, prev_handles)

      if prev_policy == nil,
        do: Application.delete_env(:lang, :storage_data_handle_policy),
        else: Application.put_env(:lang, :storage_data_handle_policy, prev_policy)
    end)

    :ok
  end

  test "resolve applies remap and backend preferences" do
    Application.put_env(:lang, :storage_data_handles, %{
      "logical_b" => [
        %{backend: :csv, adapter: Lang.InMemory.Store, path: "csv.records"},
        %{backend: :pg, adapter: Lang.InMemory.Store, path: "pg.records"}
      ]
    })

    resolution =
      DataHandle.resolve("logical_a", %{
        data_handle_policy: %{remap: %{"logical_a" => "logical_b"}, prefer_backends: [:pg, :csv]}
      })

    assert resolution.logical_handle == "logical_a"
    assert resolution.resolved_handle == "logical_b"
    assert Enum.map(resolution.chain, & &1.backend) == [:pg, :csv]
    assert resolution.resolved_backend_path == "pg.records -> csv.records"
  end

  test "execute fails over and annotates success payload" do
    Application.put_env(:lang, :storage_data_handles, %{
      "patterns" => [
        %{backend: :csv, adapter: Lang.InMemory.Store, path: "csv.patterns"},
        %{backend: :pg, adapter: Lang.InMemory.Store, path: "pg.patterns"}
      ]
    })

    assert {:ok, result} =
             DataHandle.execute("patterns", "store_patterns", fn entry ->
               case entry.backend do
                 :csv -> {:error, :csv_unavailable}
                 :pg -> {:ok, %{stored: 2}}
               end
             end)

    assert result.stored == 2
    assert result._data_handle.logical_handle == "patterns"
    assert result._data_handle.resolved_backend == :pg
    assert result._data_handle.resolved_backend_path == "csv.patterns -> pg.patterns"
  end
end
