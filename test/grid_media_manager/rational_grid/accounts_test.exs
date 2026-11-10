defmodule GridMediaManager.RationalGrid.AccountsTest do
  use GridMediaManager.DataCase
  import GridMediaManager.RationalGridMCPHelpers
  alias GridMediaManager.RationalGrid.Accounts

  setup do
    setup_http()
    :ok
  end

  test "PKCE callback validates state and issuer and encrypts rotating credentials" do
    stub(fn conn ->
      case conn.request_path do
        "/oauth/register" ->
          Req.Test.json(conn, %{client_id: "registered-client"})

        "/oauth/token" ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          params = URI.decode_query(body)
          assert params["code_verifier"] != nil
          assert params["resource"] == "https://rationalgrid.ai/mcp"

          Req.Test.json(conn, %{
            access_token: "secret-access",
            refresh_token: "secret-refresh",
            expires_in: 3600
          })
      end
    end)

    assert {:ok, url, pending} =
             Accounts.begin_link("http://localhost:4001/rationalgrid/callback")

    params = URI.decode_query(URI.parse(url).query)
    assert params["code_challenge_method"] == "S256"

    callback = %{
      "code" => "code-1",
      "state" => params["state"],
      "iss" => "https://rationalgrid.ai"
    }

    assert {:error, :authorization_failed} =
             Accounts.finish_link(pending, %{callback | "state" => "wrong"})

    assert {:error, :authorization_failed} =
             Accounts.finish_link(pending, %{callback | "iss" => "https://attacker.example"})

    assert {:ok, conn} = Accounts.finish_link(pending, callback)
    refute String.contains?(conn.credentials, "secret-access")
    assert {:ok, "secret-access"} = Accounts.access_token()
  end

  test "renews once, stores both rotated tokens, and reuses the new access token" do
    connected(-1)

    stub(fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert URI.decode_query(body)["refresh_token"] == "refresh-1"
      send(self(), :renewed)

      Req.Test.json(conn, %{
        access_token: "access-2",
        refresh_token: "refresh-2",
        expires_in: 3600
      })
    end)

    assert {:ok, "access-2"} = Accounts.access_token()
    assert_receive :renewed
    assert {:ok, "access-2"} = Accounts.access_token()
    refute_receive :renewed

    {:ok, tokens} =
      Phoenix.Token.decrypt(
        GridMediaManagerWeb.Endpoint,
        "rg-credentials",
        Accounts.connection().credentials, max_age: :infinity)

    assert tokens["refresh_token"] == "refresh-2"
  end

  test "revoked refresh token requires reauthorization and erases credentials" do
    connected(-1)

    stub(fn conn ->
      conn |> Plug.Conn.put_status(400) |> Req.Test.json(%{error: "invalid_grant"})
    end)

    assert {:error, :reauthorization_required} = Accounts.access_token()
    assert Accounts.connection().credentials == nil
    assert Accounts.connection().status == "reauthorization_required"
  end

  test "transient renewal errors retain credentials and disconnect removes them" do
    connected(-1)
    stub(fn conn -> Plug.Conn.send_resp(conn, 503, "unavailable") end)
    assert {:error, :token_renewal_unavailable} = Accounts.access_token()
    assert Accounts.connection().credentials != nil
    assert {:ok, :local_only} = Accounts.disconnect()
    assert Accounts.connection().credentials == nil
    assert {:error, :reauthorization_required} = Accounts.access_token()
  end
end
