defmodule Lang.Workspace.ChatMessage do
  use Ash.Resource,
    domain: Lang.Workspaces,
    data_layer: Lang.Ash.RedisDataLayer

  attributes do
    uuid_primary_key(:id)

    attribute :from_agent, :string do
      allow_nil?(false)
    end

    attribute :to_agent, :string do
      description("nil for broadcasts")
    end

    attribute :channel, :atom do
      constraints(one_of: [:symbols, :patterns, :optimization, :general])
    end

    attribute(:content, :map)
    attribute(:timestamp, :utc_datetime_usec)

    # Performance tracking
    attribute :token_impact, :integer do
      description("Tokens saved/spent from this message")
    end
  end

  actions do
    defaults([:create, :read])

    create :broadcast do
      accept([:from_agent, :channel, :content])

      change(fn changeset, _context ->
        changeset
        |> Ash.Changeset.change_attribute(:timestamp, DateTime.utc_now())
        |> emit_jsonld_for_message()
      end)

      after_action(fn result, _context ->
        # Publish to PubSub so LiveViews can receive it
        Phoenix.PubSub.broadcast(
          Lang.PubSub,
          "workspace:#{result.result.channel}",
          {:chat_message, result.result}
        )

        {:ok, result}
      end)
    end

    create :notify do
      accept([:from_agent, :to_agent, :channel, :content])

      change(fn changeset, _context ->
        changeset
        |> Ash.Changeset.change_attribute(:timestamp, DateTime.utc_now())
        |> emit_jsonld_for_message()
      end)

      after_action(fn result, _context ->
        # Publish to PubSub targeted at specific agent
        Phoenix.PubSub.broadcast(
          Lang.PubSub,
          "agent:#{result.result.to_agent}",
          {:chat_message, result.result}
        )

        {:ok, result}
      end)
    end

    read :for_channel do
      argument(:channel, :atom, allow_nil?: false)

      filter(expr(channel == ^arg(:channel)))

      prepare(fn query, _context ->
        Ash.Query.sort(query, timestamp: :desc)
      end)

      prepare(fn query, _context ->
        query
        |> Ash.Query.limit(100)
      end)
    end

    read :for_agent do
      argument(:agent_id, :string, allow_nil?: false)

      filter(expr(to_agent == ^arg(:agent_id) or from_agent == ^arg(:agent_id)))

      prepare(fn query, _context ->
        Ash.Query.sort(query, timestamp: :desc)
      end)

      prepare(fn query, _context ->
        query
        |> Ash.Query.limit(100)
      end)
    end
  end

  code_interface do
    define(:broadcast!, action: :broadcast)
    define(:notify!, action: :notify)
    define(:list_for_channel, action: :for_channel, args: [:channel])
    define(:list_for_agent, action: :for_agent, args: [:agent_id])
  end

  # Redis configuration
  # Keep chat history for a day
  # 24 hours
  attributes do
    attribute(:ttl, :integer, public?: false, default: 86400)
  end

  identities do
    identity(:by_channel, [:channel])
    identity(:by_from_agent, [:from_agent])
    identity(:by_to_agent, [:to_agent])
  end

  # Private helper functions
  defp emit_jsonld_for_message(changeset) do
    # Add JSON-LD metadata to the message for potential embedding
    content = Ash.Changeset.get_attribute(changeset, :content)
    from_agent = Ash.Changeset.get_attribute(changeset, :from_agent)
    channel = Ash.Changeset.get_attribute(changeset, :channel)

    jsonld = %{
      "@context": "https://schema.org/",
      "@type": "Message",
      sender: from_agent,
      about: Atom.to_string(channel),
      dateCreated: DateTime.utc_now() |> DateTime.to_iso8601(),
      text: content |> Map.get(:message, "") |> to_string()
    }

    # Include the JSON-LD in the content for consumers that can use it
    updated_content = Map.put(content, :jsonld, jsonld)
    Ash.Changeset.change_attribute(changeset, :content, updated_content)
  end
end
