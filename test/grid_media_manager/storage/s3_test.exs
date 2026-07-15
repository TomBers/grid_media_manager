defmodule GridMediaManager.Storage.S3Test do
  use ExUnit.Case, async: false

  alias GridMediaManager.Storage.S3

  @environment_variables [
    "S3_BUCKET",
    "AWS_REGION",
    "AWS_ACCESS_KEY_ID",
    "AWS_SECRET_ACCESS_KEY",
    "AWS_SESSION_TOKEN",
    "S3_ENDPOINT",
    "S3_PUBLIC_BASE_URL"
  ]

  setup do
    previous_config = Application.get_env(:grid_media_manager, :s3)
    previous_environment = Map.new(@environment_variables, &{&1, System.get_env(&1)})

    Enum.each(@environment_variables, &System.delete_env/1)

    Application.put_env(:grid_media_manager, :s3,
      bucket: "media-bucket",
      region: "eu-west-2",
      access_key_id: "AKIATEST",
      secret_access_key: "test-secret",
      endpoint: "https://media-bucket.s3.eu-west-2.amazonaws.com",
      public_base_url: "https://media.example.com",
      plug: {Req.Test, __MODULE__}
    )

    Req.Test.verify_on_exit!()

    on_exit(fn ->
      if previous_config do
        Application.put_env(:grid_media_manager, :s3, previous_config)
      else
        Application.delete_env(:grid_media_manager, :s3)
      end

      Enum.each(previous_environment, fn
        {name, nil} -> System.delete_env(name)
        {name, value} -> System.put_env(name, value)
      end)
    end)

    :ok
  end

  test "uploads an object with AWS Signature V4 and returns its public URL" do
    body = "png-binary"

    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.method == "PUT"
      assert conn.host == "media-bucket.s3.eu-west-2.amazonaws.com"
      assert conn.request_path == "/campaigns/a-grid/card%20one.png"
      assert Plug.Conn.get_req_header(conn, "content-type") == ["image/png"]

      [authorization] = Plug.Conn.get_req_header(conn, "authorization")
      assert authorization =~ "AWS4-HMAC-SHA256 Credential=AKIATEST/"
      assert authorization =~ "/eu-west-2/s3/aws4_request"
      assert authorization =~ "SignedHeaders=content-type;host;x-amz-content-sha256;x-amz-date"

      assert Plug.Conn.get_req_header(conn, "x-amz-content-sha256") == [
               :crypto.hash(:sha256, body) |> Base.encode16(case: :lower)
             ]

      {:ok, request_body, conn} = Plug.Conn.read_body(conn)
      assert request_body == body
      Plug.Conn.send_resp(conn, 200, "")
    end)

    assert S3.put_object("campaigns/a-grid/card one.png", body, "image/png") ==
             {:ok, "https://media.example.com/campaigns/a-grid/card%20one.png"}
  end

  test "environment credentials take precedence over application config" do
    System.put_env("AWS_ACCESS_KEY_ID", "ENVKEY")

    Req.Test.expect(__MODULE__, fn conn ->
      [authorization] = Plug.Conn.get_req_header(conn, "authorization")
      assert authorization =~ "Credential=ENVKEY/"
      Plug.Conn.send_resp(conn, 200, "")
    end)

    assert {:ok, _url} = S3.put_object("test.txt", "data", "text/plain")
  end

  test "reports missing configuration without making a request" do
    Application.delete_env(:grid_media_manager, :s3)

    refute S3.configured?()

    assert S3.put_object("test.txt", "data", "text/plain") ==
             {:error,
              "S3 is not configured. Set S3_BUCKET, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY."}
  end
end
