defmodule GridMediaManagerWeb.RationalGridOAuthController do
  use GridMediaManagerWeb, :controller
  alias GridMediaManager.RationalGrid.Accounts

  plug :no_cache

  def connect(conn, _params) do
    callback = url(~p"/rationalgrid/callback")

    case Accounts.begin_link(callback) do
      {:ok, location, pending} ->
        conn |> put_session(:rational_grid_pending, pending) |> redirect(external: location)

      _ ->
        conn
        |> put_flash(:error, "Could not start RationalGrid authorization.")
        |> redirect(to: ~p"/explorations")
    end
  end

  def callback(conn, params) do
    result = Accounts.finish_link(get_session(conn, :rational_grid_pending), params)
    conn = delete_session(conn, :rational_grid_pending)

    case result do
      {:ok, _} ->
        conn |> put_flash(:info, "RationalGrid connected.") |> redirect(to: ~p"/explorations")

      _ ->
        conn
        |> put_flash(:error, "Authorization expired or was declined. Connect again.")
        |> redirect(to: ~p"/explorations")
    end
  end

  def disconnect(conn, _params) do
    result = Accounts.disconnect()

    message =
      case result do
        {:ok, :ok} ->
          "RationalGrid disconnected."

        _ ->
          "Local credentials removed. Revoke Publishing Studio in RationalGrid connections to finish disconnecting."
      end

    conn |> put_flash(:info, message) |> redirect(to: ~p"/explorations")
  end

  defp no_cache(conn, _), do: put_resp_header(conn, "cache-control", "no-store")
end
