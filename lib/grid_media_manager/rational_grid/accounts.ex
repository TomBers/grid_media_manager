defmodule GridMediaManager.RationalGrid.Accounts do
  @moduledoc "OAuth connection for this shared, access-protected publishing studio."
  import Ecto.Query
  alias GridMediaManager.Repo
  alias GridMediaManager.RationalGrid.{Connection, HTTP}
  alias GridMediaManagerWeb.Endpoint

  @scopes "grids:create grids:read grids:append"
  def connection, do: Repo.get_by(Connection, key: "studio")

  def begin_link(callback) do
    with {:ok, conn} <- registered_connection(callback) do
      state = random()
      verifier = random()
      pending = %{state: state, verifier: verifier, callback: callback, client_id: conn.client_id}

      query =
        URI.encode_query(%{
          response_type: "code",
          client_id: conn.client_id,
          redirect_uri: callback,
          scope: @scopes,
          resource: HTTP.resource(),
          state: state,
          code_challenge: Base.url_encode64(:crypto.hash(:sha256, verifier), padding: false),
          code_challenge_method: "S256"
        })

      {:ok, HTTP.base_url() <> "/oauth/authorize?" <> query,
       Phoenix.Token.encrypt(Endpoint, "rg-pending", pending)}
    end
  end

  def finish_link(pending, params) when is_binary(pending) do
    with {:ok, p} <- Phoenix.Token.decrypt(Endpoint, "rg-pending", pending, max_age: 600),
         true <-
           is_binary(params["state"]) and Plug.Crypto.secure_compare(p.state, params["state"]),
         true <- params["iss"] == HTTP.base_url(),
         code when is_binary(code) <- params["code"],
         {:ok, %{status: 200, body: tokens}} <-
           HTTP.request(:post, "/oauth/token",
             form: [
               grant_type: "authorization_code",
               code: code,
               client_id: p.client_id,
               redirect_uri: p.callback,
               code_verifier: p.verifier,
               resource: HTTP.resource()
             ]
           ),
         {:ok, tokens} <- validate_tokens(tokens) do
      Repo.transaction(fn ->
        conn = Repo.one!(from c in Connection, where: c.key == "studio", lock: "FOR UPDATE")
        store_tokens(conn, tokens)
      end)
    else
      _ -> {:error, :authorization_failed}
    end
  end

  def finish_link(_, _), do: {:error, :authorization_failed}

  def access_token(force_token \\ nil) do
    Repo.transaction(fn ->
      case Repo.one(from c in Connection, where: c.key == "studio", lock: "FOR UPDATE") do
        %Connection{status: "connected"} = conn ->
          with {:ok, tokens} <- decrypt(conn) do
            refresh? =
              DateTime.diff(conn.expires_at, DateTime.utc_now()) < 60 or
                force_token == tokens["access_token"]

            if refresh?, do: renew(conn, tokens), else: {:ok, tokens["access_token"]}
          else
            _ -> invalidate(conn)
          end

        _ ->
          {:error, :reauthorization_required}
      end
    end)
    |> case do
      {:ok, result} -> result
      {:error, _} -> {:error, :connection_unavailable}
    end
  end

  def disconnect do
    Repo.transaction(fn ->
      case Repo.one(from c in Connection, where: c.key == "studio", lock: "FOR UPDATE") do
        nil ->
          :ok

        conn ->
          result =
            with {:ok, tokens} <- decrypt(conn) do
              HTTP.request(:post, "/oauth/revoke",
                form: [
                  token: tokens["refresh_token"],
                  client_id: conn.client_id
                ]
              )
            end

          save(conn, %{credentials: nil, expires_at: nil, status: "disconnected"})

          case result do
            {:ok, %{status: status}} when status in 200..299 -> :ok
            _ -> :local_only
          end
      end
    end)
  end

  defp registered_connection(callback) do
    case connection() do
      %Connection{} = conn ->
        {:ok, conn}

      nil ->
        with {:ok, %{status: status, body: %{"client_id" => client_id}}} when status in 200..299 <-
               HTTP.request(:post, "/oauth/register",
                 json: %{
                   client_name: "RationalGrid Publishing Studio",
                   redirect_uris: [callback],
                   grant_types: ["authorization_code", "refresh_token"],
                   response_types: ["code"],
                   token_endpoint_auth_method: "none"
                 }
               ) do
          Repo.insert(%Connection{key: "studio", client_id: client_id},
            on_conflict: :nothing,
            conflict_target: :key
          )

          {:ok, connection()}
        else
          _ -> {:error, :registration_failed}
        end
    end
  end

  defp renew(conn, tokens) do
    case HTTP.request(:post, "/oauth/token",
           form: [
             grant_type: "refresh_token",
             refresh_token: tokens["refresh_token"],
             client_id: conn.client_id,
             resource: HTTP.resource()
           ]
         ) do
      {:ok, %{status: 200, body: body}} ->
        case validate_tokens(body) do
          {:ok, next} ->
            store_tokens(conn, next)
            {:ok, next["access_token"]}

          _ ->
            invalidate(conn)
        end

      {:ok, %{body: %{"error" => error}}} when error in ["invalid_grant", "invalid_client"] ->
        invalidate(conn)

      _ ->
        {:error, :token_renewal_unavailable}
    end
  end

  defp validate_tokens(%{"access_token" => a, "refresh_token" => r, "expires_in" => e} = t)
       when is_binary(a) and byte_size(a) > 0 and is_binary(r) and byte_size(r) > 0 and
              is_integer(e) and e > 0,
       do: {:ok, t}

  defp validate_tokens(_), do: {:error, :invalid_tokens}

  defp store_tokens(conn, tokens) do
    save(conn, %{
      credentials: Phoenix.Token.encrypt(Endpoint, "rg-credentials", tokens),
      expires_at:
        DateTime.add(DateTime.utc_now(), tokens["expires_in"]) |> DateTime.truncate(:second),
      status: "connected"
    })
  end

  defp invalidate(conn) do
    save(conn, %{credentials: nil, expires_at: nil, status: "reauthorization_required"})
    {:error, :reauthorization_required}
  end

  defp decrypt(conn),
    do: Phoenix.Token.decrypt(Endpoint, "rg-credentials", conn.credentials, max_age: :infinity)

  defp save(conn, attrs), do: conn |> Ecto.Changeset.change(attrs) |> Repo.update!()
  defp random, do: Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
end
