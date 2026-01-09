defmodule JustoneWeb.PageController do
  use JustoneWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
