defmodule GridMediaManagerWeb.Plugs.RequireStudioAccess do
  @moduledoc """
  Protects the standalone studio until RationalGrid supplies its user session.

  Development and test may omit credentials. Production runtime configuration
  requires them so publishing credentials are never exposed by an anonymous app.
  """

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    case Application.get_env(:grid_media_manager, :studio_basic_auth, []) do
      [username: username, password: password]
      when is_binary(username) and username != "" and is_binary(password) and password != "" ->
        Plug.BasicAuth.basic_auth(conn, username: username, password: password)

      _credentials ->
        conn
    end
  end
end
