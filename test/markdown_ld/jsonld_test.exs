defmodule MarkdownLD.JSONLDTest do
  use ExUnit.Case, async: true
  alias MarkdownLD.JSONLD

  describe "normalize/1" do
    test "extracts @context when it is a map" do
      input = %{"@context" => %{"name" => "http://schema.org/name"}, "name" => "Alice"}
      assert JSONLD.normalize(input) == {input, %{"name" => "http://schema.org/name"}}
    end

    test "defaults @context to empty map when it is not a map" do
      input = %{"@context" => "http://schema.org", "name" => "Alice"}
      assert JSONLD.normalize(input) == {input, %{}}
    end

    test "defaults @context to empty map when missing" do
      input = %{"name" => "Alice"}
      assert JSONLD.normalize(input) == {input, %{}}
    end

    test "handles non-map input" do
      assert JSONLD.normalize("string") == {"string", %{}}
      assert JSONLD.normalize(123) == {123, %{}}
      assert JSONLD.normalize(["list"]) == {["list"], %{}}
      assert JSONLD.normalize(nil) == {nil, %{}}
    end
  end

  describe "get/3" do
    test "returns the value for a term present in the map" do
      map = %{"name" => "Alice"}
      assert JSONLD.get(map, "name") == "Alice"
    end

    test "returns the value using IRI from context if term is not in map" do
      map = %{
        "@context" => %{"name" => "http://schema.org/name"},
        "http://schema.org/name" => "Alice"
      }

      assert JSONLD.get(map, "name") == "Alice"
    end

    test "returns default when term and IRI are not present" do
      map = %{"@context" => %{"name" => "http://schema.org/name"}}
      assert JSONLD.get(map, "name", "default_val") == "default_val"
      assert JSONLD.get(map, "missing", "default_val") == "default_val"
    end

    test "returns default when map has no context and key is missing" do
      assert JSONLD.get(%{"other" => 1}, "name", "default_val") == "default_val"
    end
  end

  describe "get_list/2" do
    test "returns an empty list when value is nil" do
      assert JSONLD.get_list(%{}, "name") == []
    end

    test "returns the value as is if it is already a list" do
      assert JSONLD.get_list(%{"name" => ["Alice", "Bob"]}, "name") == ["Alice", "Bob"]
    end

    test "wraps the value in a list if it is not a list" do
      assert JSONLD.get_list(%{"name" => "Alice"}, "name") == ["Alice"]
    end
  end

  describe "types/1" do
    test "extracts @type when it is a list of strings" do
      assert JSONLD.types(%{"@type" => ["Person", "Organization"]}) == ["Person", "Organization"]
    end

    test "extracts @type when it is a single string" do
      assert JSONLD.types(%{"@type" => "Person"}) == ["Person"]
    end

    test "extracts @type and converts non-strings to strings" do
      assert JSONLD.types(%{"@type" => [123, :atom]}) == ["123", "atom"]
      assert JSONLD.types(%{"@type" => 123}) == ["123"]
    end

    test "falls back to type when @type is missing" do
      assert JSONLD.types(%{"type" => ["Person", "Organization"]}) == ["Person", "Organization"]
      assert JSONLD.types(%{"type" => "Person"}) == ["Person"]
      assert JSONLD.types(%{"type" => 123}) == ["123"]
    end

    test "returns empty list when neither @type nor type are present" do
      assert JSONLD.types(%{"name" => "Alice"}) == []
    end

    test "handles non-map input" do
      assert JSONLD.types("string") == []
      assert JSONLD.types(nil) == []
    end
  end

  describe "compact/2" do
    test "compacts keys using the provided context" do
      doc = %{"http://schema.org/name" => "Alice"}
      context = %{"name" => "http://schema.org/name"}
      {compacted, ctx} = JSONLD.compact(doc, context)

      assert compacted == %{"name" => "Alice"}
      assert ctx == context
    end

    test "compacts recursively within lists and maps" do
      doc = %{
        "http://schema.org/author" => [
          %{"http://schema.org/name" => "Alice"},
          %{"http://schema.org/name" => "Bob"}
        ]
      }
      context = %{
        "author" => "http://schema.org/author",
        "name" => "http://schema.org/name"
      }
      {compacted, ctx} = JSONLD.compact(doc, context)

      assert compacted == %{
        "author" => [
          %{"name" => "Alice"},
          %{"name" => "Bob"}
        ]
      }
      assert ctx == context
    end

    test "ignores keys that are not in the context" do
      doc = %{"http://schema.org/unknown" => "value"}
      context = %{"name" => "http://schema.org/name"}
      {compacted, _} = JSONLD.compact(doc, context)

      assert compacted == %{"http://schema.org/unknown" => "value"}
    end
  end

  describe "expand/2" do
    test "expands keys using the provided context" do
      doc = %{"name" => "Alice"}
      context = %{"name" => "http://schema.org/name"}
      {expanded, ctx} = JSONLD.expand(doc, context)

      assert expanded == %{"http://schema.org/name" => "Alice"}
      assert ctx == context
    end

    test "expands recursively within lists and maps" do
      doc = %{
        "author" => [
          %{"name" => "Alice"},
          %{"name" => "Bob"}
        ]
      }
      context = %{
        "author" => "http://schema.org/author",
        "name" => "http://schema.org/name"
      }
      {expanded, ctx} = JSONLD.expand(doc, context)

      assert expanded == %{
        "http://schema.org/author" => [
          %{"http://schema.org/name" => "Alice"},
          %{"http://schema.org/name" => "Bob"}
        ]
      }
      assert ctx == context
    end

    test "does not expand keys starting with @" do
      doc = %{"@id" => "123", "name" => "Alice"}
      context = %{"name" => "http://schema.org/name", "@id" => "http://schema.org/id"}
      {expanded, _} = JSONLD.expand(doc, context)

      assert expanded == %{"@id" => "123", "http://schema.org/name" => "Alice"}
    end

    test "ignores keys that are not in the context" do
      doc = %{"unknown" => "value"}
      context = %{"name" => "http://schema.org/name"}
      {expanded, _} = JSONLD.expand(doc, context)

      assert expanded == %{"unknown" => "value"}
    end
  end
end
