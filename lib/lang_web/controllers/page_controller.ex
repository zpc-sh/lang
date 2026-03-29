defmodule LangWeb.PageController do
  use LangWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
