defmodule GridMediaManagerWeb.PageControllerTest do
  use GridMediaManagerWeb.ConnCase

  test "GET / shows the import workbench", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Turn argument maps into copy-ready social assets"
    assert html_response(conn, 200) =~ "grid-import-form"
  end
end
