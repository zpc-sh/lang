defmodule Lang.Documents do
  use Ash.Domain

  resources do
    resource(Lang.Documents.Document)
  end
end
