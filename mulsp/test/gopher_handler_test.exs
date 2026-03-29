defmodule Mulsp.Gopher.HandlerTest do
  use ExUnit.Case, async: true

  alias Mulsp.Gopher.Handler

  describe "handle/3" do
    test "root menu contains node identity" do
      response = Handler.handle("", "localhost", 7070)
      assert response =~ "mulsp"
      assert response =~ ".\r\n"  # Gopher terminator
    end

    test "root menu has navigation links" do
      response = Handler.handle("/", "localhost", 7070)
      assert response =~ "LSP Methods"
      assert response =~ "DC Transfers"
      assert response =~ "Mesh Peers"
      assert response =~ "Finger .plan"
    end

    test "/lsp shows method routing" do
      response = Handler.handle("/lsp", "localhost", 7070)
      assert response =~ "LOCAL"
      assert response =~ "initialize"
    end

    test "/finger returns .plan text" do
      response = Handler.handle("/finger", "localhost", 7070)
      assert response =~ "kind: mulsp.plan"
      assert response =~ "node:"
    end

    test "/methods returns table" do
      response = Handler.handle("/methods", "localhost", 7070)
      assert response =~ "METHOD TABLE"
    end

    test "/partition returns config" do
      response = Handler.handle("/partition", "localhost", 7070)
      assert response =~ "PARTITION CONFIG"
      assert response =~ "node_id:"
    end

    test "unknown selector returns error" do
      response = Handler.handle("/nonexistent", "localhost", 7070)
      assert response =~ "Not found"
    end
  end
end
