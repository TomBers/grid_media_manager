defmodule GridMediaManagerWeb.PageController do
  use GridMediaManagerWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
