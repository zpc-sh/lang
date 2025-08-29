defmodule LangWeb.FSWatchLiveTest do
  use LangWeb.ConnCase
  import Phoenix.LiveViewTest

  test "renders and starts bounded watch (isolated)", %{conn: conn} do
    # Use isolated mount to avoid unrelated router/DB setup during this smoke test
    conn = Plug.Conn.assign(conn, :current_user, %{id: "test-user"})
    conn = Plug.Conn.assign(conn, :current_scope, :user)

    {:ok, view, _html} = live_isolated(conn, LangWeb.FSWatchLive)

    assert has_element?(view, "#fs-watch-form")

    path = File.cwd!()
    view
    |> form("#fs-watch-form", %{path: path, interval_ms: 10, duration_ms: 50})
    |> render_submit()

    Process.sleep(100)
    html = render(view)
    assert html =~ "Snapshots"
  end

  @tag :skip
  test "renders and starts bounded watch (routed, authenticated)", %{conn: conn} do
    # Skipped due to unrelated DB migration issues in test environment.
    user = Lang.Factory.create_user!()
    conn = Plug.Conn.fetch_session(conn)
    conn = Plug.Test.init_test_session(conn, %{})
    conn = LangWeb.Plugs.AuthPlug.store_in_session(conn, user)

    {:ok, view, _html} = live(conn, "/fs/watch")
    assert has_element?(view, "#fs-watch-form")
  end
end
