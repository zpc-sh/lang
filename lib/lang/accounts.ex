defmodule Lang.Accounts do
  use Ash.Domain

  resources do
    resource(Lang.Accounts.Organization)
    resource(Lang.Accounts.User)
    resource(Lang.Accounts.Token)
    resource(Lang.Accounts.APIUsage)
  end
end
