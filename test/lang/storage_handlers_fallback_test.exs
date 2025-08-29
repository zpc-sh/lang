defmodule Lang.StorageHandlersFallbackTest do
  use ExUnit.Case, async: true

  alias Elixir.Lang.LSP.Lang.Lang.Storage.{StorePatterns, GetPatterns, UpdateConfidence}
  alias Elixir.Lang.LSP.Lang.Lang.Storage.{UpdateUserContext, GetUserContext}

  setup do
    # Ensure Dirup is disabled for fallback tests
    prev = System.get_env("DIRUP_ENABLED")
    System.put_env("DIRUP_ENABLED", "0")
    on_exit(fn -> if prev, do: System.put_env("DIRUP_ENABLED", prev), else: System.delete_env("DIRUP_ENABLED") end)

    :ok
  end

  test "store/get patterns via ETS-backed Ash resource" do
    patterns = [
      %{content: %{name: "pat1", data: 1}},
      %{content: %{name: "pat2", data: 2}}
    ]

    {:ok, %{stored: 2, pattern_ids: ids}} = StorePatterns.handle(%{"patterns" => patterns}, %{})
    assert length(ids) == 2

    {:ok, %{patterns: fetched}} = GetPatterns.handle(%{"pattern_ids" => ids}, %{})
    assert length(fetched) == 2
    assert Enum.all?(fetched, &(&1[:id] in ids))
  end

  test "update confidence on stored pattern" do
    {:ok, %{stored: 1, pattern_ids: [id]}} =
      StorePatterns.handle(%{"patterns" => [%{content: %{foo: "bar"}}]}, %{})

    assert {:ok, _} = UpdateConfidence.handle(%{"pattern_id" => id, "confidence" => 0.9}, %{})
  end

  test "user context read/write fallback" do
    user_id = Ecto.UUID.generate()
    ctx = %{"prefs" => %{"theme" => "dark"}}

    assert {:ok, %{updated: true, user_id: ^user_id}} =
             UpdateUserContext.handle(%{"user_id" => user_id, "context" => ctx}, %{})

    assert {:ok, %{user_id: ^user_id, context: ^ctx}} =
             GetUserContext.handle(%{"user_id" => user_id}, %{})
  end
end

