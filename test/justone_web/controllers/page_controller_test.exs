defmodule JustoneWeb.PageControllerTest do
  use JustoneWeb.ConnCase

  test "GET / renders lobby", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Just One"
    assert html_response(conn, 200) =~ "Partidas disponibles"
  end
end
