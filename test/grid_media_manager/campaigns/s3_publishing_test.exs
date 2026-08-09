defmodule GridMediaManager.Campaigns.S3PublishingTest do
  use GridMediaManager.DataCase, async: false

  alias GridMediaManager.Campaigns
  alias GridMediaManager.Studio.Workflow

  @png <<137, 80, 78, 71, 13, 10, 26, 10, 0, 1, 2, 3>>

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
    previous_s3 = Application.get_env(:grid_media_manager, :s3)
    previous_buffer = Application.get_env(:grid_media_manager, :buffer)
    previous_artifact_root = Application.get_env(:grid_media_manager, :artifact_store_path)
    previous_environment = Map.new(@environment_variables, &{&1, System.get_env(&1)})

    artifact_root =
      Path.join(
        System.tmp_dir!(),
        "grid-media-manager-s3-test-#{System.unique_integer([:positive])}"
      )

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

    Application.put_env(:grid_media_manager, :buffer,
      api_key: "buffer-key",
      endpoint: "https://buffer.test/graphql",
      channels: %{"x" => "x-channel", "instagram" => "instagram-channel"},
      plug: {Req.Test, __MODULE__}
    )

    Application.put_env(:grid_media_manager, :artifact_store_path, artifact_root)

    Req.Test.verify_on_exit!()

    on_exit(fn ->
      restore_config(:s3, previous_s3)
      restore_config(:buffer, previous_buffer)
      restore_config(:artifact_store_path, previous_artifact_root)
      File.rm_rf!(artifact_root)

      Enum.each(previous_environment, fn
        {name, nil} -> System.delete_env(name)
        {name, value} -> System.put_env(name, value)
      end)
    end)

    :ok
  end

  test "uploads local generated media to S3 before scheduling it through Buffer" do
    assert {:ok, campaign} = Campaigns.import_payload(payload(), "s3-buffer-publishing")
    assert {:ok, asset} = Campaigns.generate_grid_asset(campaign)
    assert {:ok, asset} = Campaigns.store_client_artifact(asset, 1, @png)

    [draft] = Campaigns.list_post_drafts(campaign, platform: "x", media_asset_id: asset.id)

    scheduled_for =
      DateTime.utc_now() |> DateTime.add(3_600, :second) |> DateTime.truncate(:second)

    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.host == "media-bucket.s3.eu-west-2.amazonaws.com"
      assert conn.method == "PUT"
      assert conn.request_path =~ "/campaigns/preserve-agency-s3/assets/#{asset.id}/"
      assert String.ends_with?(conn.request_path, ".png")

      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert binary_part(body, 0, 8) == <<137, 80, 78, 71, 13, 10, 26, 10>>
      Plug.Conn.send_resp(conn, 200, "")
    end)

    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.host == "buffer.test"
      {:ok, raw_body, conn} = Plug.Conn.read_body(conn)
      input = Jason.decode!(raw_body)["variables"]["input"]
      [%{"image" => %{"url" => media_url}}] = input["assets"]

      assert media_url =~
               "https://media.example.com/campaigns/preserve-agency-s3/assets/#{asset.id}/"

      assert String.ends_with?(media_url, ".png")

      Req.Test.json(conn, %{
        "data" => %{
          "createPost" => %{
            "post" => %{
              "id" => "buffer-s3-post",
              "status" => "scheduled",
              "dueAt" => DateTime.to_iso8601(scheduled_for)
            }
          }
        }
      })
    end)

    assert {:ok, scheduled} = Campaigns.schedule_post_draft(draft.id, scheduled_for)
    assert scheduled.external_post_id == "buffer-s3-post"

    published_asset = Campaigns.get_media_asset!(asset.id)
    assert published_asset.url == asset.url
    assert published_asset.metadata["published_url"] =~ "https://media.example.com/"
    assert published_asset.metadata["s3_key"] =~ "/assets/#{asset.id}/"
    assert String.length(published_asset.metadata["sha256"]) == 64
  end

  test "publishes every combined-carousel slide as one ordered Buffer post" do
    assert {:ok, campaign} = Campaigns.import_payload(payload(), "s3-combined-carousel")

    candidates = campaign |> Workflow.candidates() |> Enum.take(2)

    assert {:ok, asset} =
             Campaigns.generate_curated_carousel(campaign, candidates, "minimal_dark")

    asset =
      Enum.reduce(Campaigns.media_asset_slide_indexes(asset), asset, fn index, asset ->
        assert {:ok, asset} = Campaigns.store_client_artifact(asset, index, @png)
        asset
      end)

    assert asset.metadata["slide_count"] == 4

    [draft] =
      Campaigns.list_post_drafts(campaign,
        platform: "x",
        media_asset_id: asset.id
      )

    scheduled_for =
      DateTime.utc_now() |> DateTime.add(3_600, :second) |> DateTime.truncate(:second)

    Req.Test.expect(__MODULE__, 4, fn conn ->
      assert conn.host == "media-bucket.s3.eu-west-2.amazonaws.com"
      assert conn.method == "PUT"
      assert conn.request_path =~ "/assets/#{asset.id}/"
      Plug.Conn.send_resp(conn, 200, "")
    end)

    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.host == "buffer.test"
      {:ok, raw_body, conn} = Plug.Conn.read_body(conn)
      input = Jason.decode!(raw_body)["variables"]["input"]

      assert length(input["assets"]) == 4

      refute Map.has_key?(input, "metadata")

      assert Enum.all?(input["assets"], &match?(%{"image" => %{"url" => _}}, &1))

      Req.Test.json(conn, %{
        "data" => %{
          "createPost" => %{
            "post" => %{
              "id" => "buffer-carousel-post",
              "status" => "scheduled",
              "dueAt" => DateTime.to_iso8601(scheduled_for)
            }
          }
        }
      })
    end)

    assert {:ok, scheduled} = Campaigns.schedule_post_draft(draft.id, scheduled_for)
    assert scheduled.external_post_id == "buffer-carousel-post"

    published_asset = Campaigns.get_media_asset!(asset.id)
    assert length(published_asset.metadata["published_urls"]) == 4
    assert length(published_asset.metadata["s3_keys"]) == 4
  end

  defp restore_config(key, nil), do: Application.delete_env(:grid_media_manager, key)
  defp restore_config(key, value), do: Application.put_env(:grid_media_manager, key, value)

  defp payload do
    %{
      "metadata" => %{
        "title" => "How should we preserve agency?",
        "slug" => "preserve-agency-s3",
        "url" => "https://rationalgrid.ai/g/preserve-agency-s3",
        "tags" => ["Agency"],
        "node_count" => 1
      },
      "graph" => %{
        "nodes" => [
          %{
            "id" => "origin-1",
            "class" => "origin",
            "content" => "How should we preserve agency?"
          }
        ],
        "edges" => []
      },
      "highlights" => []
    }
  end
end
