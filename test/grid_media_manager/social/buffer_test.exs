defmodule GridMediaManager.Social.BufferTest do
  use ExUnit.Case, async: false

  alias GridMediaManager.Campaigns.PostDraft
  alias GridMediaManager.Social.Buffer

  @scheduled_for ~U[2026-08-20 15:30:00Z]

  setup do
    previous_config = Application.get_env(:grid_media_manager, :buffer)
    previous_youtube_category_id = System.get_env("BUFFER_YOUTUBE_CATEGORY_ID")

    System.delete_env("BUFFER_YOUTUBE_CATEGORY_ID")

    on_exit(fn ->
      if is_nil(previous_config) do
        Application.delete_env(:grid_media_manager, :buffer)
      else
        Application.put_env(:grid_media_manager, :buffer, previous_config)
      end

      if previous_youtube_category_id do
        System.put_env("BUFFER_YOUTUBE_CATEGORY_ID", previous_youtube_category_id)
      else
        System.delete_env("BUFFER_YOUTUBE_CATEGORY_ID")
      end
    end)

    Application.put_env(:grid_media_manager, :buffer,
      api_key: "test-api-key",
      endpoint: "https://buffer.test/graphql",
      plug: {Req.Test, __MODULE__}
    )

    Req.Test.verify_on_exit!()
    :ok
  end

  test "configured?/0 requires a non-blank API key" do
    assert Buffer.configured?()

    Application.put_env(:grid_media_manager, :buffer, api_key: "   ")

    refute Buffer.configured?()
  end

  test "routes text and video platforms to their respective accounts" do
    Application.put_env(:grid_media_manager, :buffer,
      api_key: "video-api-key",
      text_api_key: "text-api-key",
      video_channels: %{"instagram" => "video-instagram"},
      text_channels: %{
        "x" => "text-x",
        "linkedin" => "text-linkedin",
        "facebook" => "text-facebook"
      }
    )

    assert Buffer.account_for("instagram") == %{
             api_key: "video-api-key",
             channel_id: "video-instagram"
           }

    assert Buffer.account_for("x") == %{api_key: "text-api-key", channel_id: "text-x"}

    assert Buffer.account_for("linkedin") == %{
             api_key: "text-api-key",
             channel_id: "text-linkedin"
           }

    assert Buffer.account_for("facebook") == %{
             api_key: "text-api-key",
             channel_id: "text-facebook"
           }
  end

  test "returns paginated queue counts and vacancies for all six platforms" do
    configure_snapshot_accounts()

    Req.Test.expect(__MODULE__, 3, fn conn ->
      {:ok, raw_body, conn} = Plug.Conn.read_body(conn)
      request = Jason.decode!(raw_body)
      variables = request["variables"]
      authorization = Plug.Conn.get_req_header(conn, "authorization")

      assert request["query"] =~ "query BufferQueuePosts"
      assert variables["first"] == 50
      assert variables["input"]["filter"]["status"] == ["scheduled"]

      case {authorization, variables["after"]} do
        {["Bearer text-api-key"], nil} ->
          posts_response(
            conn,
            [
              post_node("text-x-post", "text-x", "scheduled"),
              post_node("text-linkedin-post", "text-linkedin", "scheduled")
            ],
            true,
            "text-page-2"
          )

        {["Bearer text-api-key"], "text-page-2"} ->
          posts_response(
            conn,
            [post_node("text-facebook-post", "text-facebook", "scheduled")],
            false,
            nil
          )

        {["Bearer video-api-key"], nil} ->
          posts_response(
            conn,
            [
              post_node("video-tiktok-post", "video-tiktok", "scheduled"),
              post_node("video-youtube-post", "video-youtube", "scheduled")
            ],
            false,
            nil
          )
      end
    end)

    assert {:ok, snapshot} =
             Buffer.queue_snapshot(~w(x linkedin facebook tiktok instagram youtube))

    assert snapshot.queue_limit == 10
    assert snapshot.platforms["x"].scheduled_count == 1
    assert snapshot.platforms["linkedin"].vacancies == 9
    assert snapshot.platforms["facebook"].post_count == 1
    assert snapshot.platforms["tiktok"].scheduled_count == 1
    assert snapshot.platforms["instagram"].scheduled_count == 0
    assert snapshot.platforms["instagram"].vacancies == 10

    assert snapshot.platforms["youtube"].posts |> List.first() |> Map.fetch!(:id) ==
             "video-youtube-post"
  end

  test "returns paginated sent posts with metrics for a requested window" do
    configure_snapshot_accounts()
    since = ~U[2026-05-01 00:00:00Z]
    until = ~U[2026-08-01 00:00:00Z]

    Req.Test.expect(__MODULE__, 2, fn conn ->
      {:ok, raw_body, conn} = Plug.Conn.read_body(conn)
      request = Jason.decode!(raw_body)
      variables = request["variables"]
      filter = variables["input"]["filter"]

      assert request["query"] =~ "query BufferPerformancePosts"
      assert request["query"] =~ "metricsUpdatedAt"
      assert filter["status"] == ["sent"]
      assert filter["startDate"] == "2026-05-01T00:00:00Z"
      assert filter["endDate"] == "2026-08-01T00:00:00Z"

      post =
        post_node("sent-#{variables["after"] || "first"}", "text-x", "sent")
        |> Map.put("metrics", [
          %{
            "type" => "impressions",
            "name" => "Impressions",
            "value" => 1250,
            "unit" => "count"
          }
        ])
        |> Map.put("metricsUpdatedAt", "2026-08-02T00:00:00Z")

      if variables["after"] do
        posts_response(conn, [post], false, nil)
      else
        posts_response(conn, [post], true, "next-page")
      end
    end)

    assert {:ok, snapshot} =
             Buffer.performance_snapshot(["x"], since: since, until: until)

    assert snapshot.since == since
    assert snapshot.until == until
    assert snapshot.platforms["x"].post_count == 2

    assert [%{type: "impressions", value: 1250}] =
             snapshot.platforms["x"].posts |> List.first() |> Map.fetch!(:metrics)
  end

  test "discovers a single organization when no organization ID is configured" do
    Application.put_env(:grid_media_manager, :buffer,
      text_api_key: "text-api-key",
      text_channels: %{"x" => "text-x"},
      endpoint: "https://buffer.test/graphql",
      plug: {Req.Test, __MODULE__}
    )

    Req.Test.expect(__MODULE__, 2, fn conn ->
      {:ok, raw_body, conn} = Plug.Conn.read_body(conn)
      request = Jason.decode!(raw_body)

      if request["query"] =~ "query BufferOrganizations" do
        Req.Test.json(conn, %{
          "data" => %{
            "account" => %{
              "organizations" => [%{"id" => "discovered-org", "name" => "RationalGrid"}]
            }
          }
        })
      else
        assert request["variables"]["input"]["organizationId"] == "discovered-org"
        posts_response(conn, [], false, nil)
      end
    end)

    assert {:ok, snapshot} = Buffer.queue_snapshot(["x"])
    assert snapshot.platforms["x"].vacancies == 10
  end

  test "requires every requested snapshot platform to be configured" do
    Application.put_env(:grid_media_manager, :buffer,
      text_api_key: "text-api-key",
      text_organization_id: "text-org",
      text_channels: %{"x" => "text-x"},
      endpoint: "https://buffer.test/graphql",
      plug: {Req.Test, __MODULE__}
    )

    assert Buffer.queue_snapshot(["x", "linkedin", "youtube"]) ==
             {:error, {:platforms_not_configured, ["linkedin", "youtube"]}}
  end

  test "returns GraphQL failures from snapshot queries" do
    Application.put_env(:grid_media_manager, :buffer,
      text_api_key: "text-api-key",
      text_organization_id: "text-org",
      text_channels: %{"x" => "text-x"},
      endpoint: "https://buffer.test/graphql",
      plug: {Req.Test, __MODULE__}
    )

    Req.Test.expect(__MODULE__, fn conn ->
      Req.Test.json(conn, %{"errors" => [%{"message" => "Insights access is required"}]})
    end)

    assert Buffer.performance_snapshot(["x"],
             since: ~U[2026-07-01 00:00:00Z],
             until: ~U[2026-08-01 00:00:00Z]
           ) == {:error, "Buffer GraphQL error: Insights access is required"}
  end

  test "rejects performance windows longer than Buffer supports" do
    assert Buffer.performance_snapshot(["x"],
             since: ~U[2025-01-01 00:00:00Z],
             until: ~U[2026-08-01 00:00:00Z]
           ) == {:error, :invalid_performance_window}
  end

  test "schedules a draft with custom scheduling and an image asset" do
    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.method == "POST"
      assert conn.host == "buffer.test"
      assert conn.request_path == "/graphql"
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer test-api-key"]

      {:ok, raw_body, conn} = Plug.Conn.read_body(conn)
      body = Jason.decode!(raw_body)

      assert body["query"] =~ "mutation CreatePost($input: CreatePostInput!)"
      assert body["query"] =~ "... on MutationError"

      assert body["variables"] == %{
               "input" => %{
                 "assets" => [
                   %{"image" => %{"url" => "https://cdn.example.com/share-card.png"}}
                 ],
                 "channelId" => "channel-123",
                 "dueAt" => "2026-08-20T15:30:00Z",
                 "mode" => "customScheduled",
                 "schedulingType" => "automatic",
                 "text" => "A focused campaign post"
               }
             }

      Req.Test.json(conn, %{
        "data" => %{
          "createPost" => %{
            "post" => %{
              "id" => "post-456",
              "status" => "scheduled",
              "dueAt" => "2026-08-20T15:30:00.000Z"
            }
          }
        }
      })
    end)

    assert Buffer.schedule(draft(),
             channel_id: "channel-123",
             media_url: "https://cdn.example.com/share-card.png",
             mime_type: "image/png"
           ) ==
             {:ok,
              %{
                id: "post-456",
                status: "scheduled",
                due_at: "2026-08-20T15:30:00.000Z"
              }}
  end

  test "schedules two ordered image assets and keeps Instagram post metadata" do
    Req.Test.expect(__MODULE__, fn conn ->
      {:ok, raw_body, conn} = Plug.Conn.read_body(conn)
      input = Jason.decode!(raw_body)["variables"]["input"]

      assert input["assets"] == [
               %{"image" => %{"url" => "https://cdn.example.com/first.png"}},
               %{"image" => %{"url" => "https://cdn.example.com/second.jpg"}}
             ]

      assert input["metadata"] == %{
               "instagram" => %{"type" => "carousel", "shouldShareToFeed" => true}
             }

      success_response(conn)
    end)

    instagram_draft = %{draft() | platform: "instagram"}

    assert {:ok, %{id: "post-456"}} =
             Buffer.schedule(instagram_draft,
               channel_id: "instagram-channel",
               media: [
                 [url: "https://cdn.example.com/first.png", mime_type: "image/png"],
                 %{"image" => %{"url" => "https://cdn.example.com/second.jpg"}}
               ]
             )
  end

  test "uses a video asset for an mp4 MIME type" do
    Req.Test.expect(__MODULE__, fn conn ->
      {:ok, raw_body, conn} = Plug.Conn.read_body(conn)
      input = Jason.decode!(raw_body)["variables"]["input"]

      assert input["assets"] == [
               %{"video" => %{"url" => "https://cdn.example.com/promo.mp4"}}
             ]

      success_response(conn)
    end)

    assert {:ok, %{id: "post-456"}} =
             Buffer.schedule(draft(),
               channel_id: "channel-123",
               media_url: "https://cdn.example.com/promo.mp4",
               mime_type: "video/mp4"
             )
  end

  test "sets Instagram post metadata for image assets" do
    Req.Test.expect(__MODULE__, fn conn ->
      {:ok, raw_body, conn} = Plug.Conn.read_body(conn)
      input = Jason.decode!(raw_body)["variables"]["input"]

      assert input["metadata"] == %{
               "instagram" => %{"type" => "post", "shouldShareToFeed" => true}
             }

      success_response(conn)
    end)

    instagram_draft = %{draft() | platform: "instagram"}

    assert {:ok, _post} =
             Buffer.schedule(instagram_draft,
               channel_id: "instagram-channel",
               media_url: "https://cdn.example.com/post.png",
               mime_type: "image/png"
             )
  end

  test "sets Instagram reel metadata for video assets" do
    Req.Test.expect(__MODULE__, fn conn ->
      {:ok, raw_body, conn} = Plug.Conn.read_body(conn)
      input = Jason.decode!(raw_body)["variables"]["input"]

      assert input["metadata"] == %{
               "instagram" => %{"type" => "reel", "shouldShareToFeed" => true}
             }

      success_response(conn)
    end)

    instagram_draft = %{draft() | platform: "instagram"}

    assert {:ok, _post} =
             Buffer.schedule(instagram_draft,
               channel_id: "instagram-channel",
               media_url: "https://cdn.example.com/reel.mp4",
               mime_type: "video/mp4"
             )
  end

  test "sets Facebook post metadata for image assets" do
    Req.Test.expect(__MODULE__, fn conn ->
      {:ok, raw_body, conn} = Plug.Conn.read_body(conn)
      input = Jason.decode!(raw_body)["variables"]["input"]

      assert input["metadata"] == %{"facebook" => %{"type" => "post"}}

      success_response(conn)
    end)

    facebook_draft = %{draft() | platform: "facebook"}

    assert {:ok, _post} =
             Buffer.schedule(facebook_draft,
               channel_id: "facebook-channel",
               media_url: "https://cdn.example.com/post.png",
               mime_type: "image/png"
             )
  end

  test "supports an explicit Instagram story type" do
    Req.Test.expect(__MODULE__, fn conn ->
      {:ok, raw_body, conn} = Plug.Conn.read_body(conn)
      input = Jason.decode!(raw_body)["variables"]["input"]

      assert input["metadata"] == %{
               "instagram" => %{"type" => "story", "shouldShareToFeed" => false}
             }

      success_response(conn)
    end)

    instagram_draft = %{draft() | platform: "instagram"}

    assert {:ok, _post} =
             Buffer.schedule(instagram_draft,
               channel_id: "instagram-channel",
               media_url: "https://cdn.example.com/story.png",
               mime_type: "image/png",
               instagram_type: "story"
             )
  end

  test "sets required YouTube title and category metadata" do
    Req.Test.expect(__MODULE__, fn conn ->
      {:ok, raw_body, conn} = Plug.Conn.read_body(conn)
      input = Jason.decode!(raw_body)["variables"]["input"]

      assert input["metadata"] == %{
               "youtube" => %{
                 "title" => "A RationalGrid Short",
                 "categoryId" => "27"
               }
             }

      success_response(conn)
    end)

    youtube_draft = %{draft() | platform: "youtube"}

    assert {:ok, _post} =
             Buffer.schedule(youtube_draft,
               channel_id: "youtube-channel",
               media_url: "https://cdn.example.com/short.mp4",
               mime_type: "video/mp4",
               title: "A RationalGrid Short"
             )
  end

  test "allows the YouTube category to be configured" do
    System.put_env("BUFFER_YOUTUBE_CATEGORY_ID", "22")

    Req.Test.expect(__MODULE__, fn conn ->
      {:ok, raw_body, conn} = Plug.Conn.read_body(conn)
      youtube = Jason.decode!(raw_body)["variables"]["input"]["metadata"]["youtube"]

      assert youtube["categoryId"] == "22"
      success_response(conn)
    end)

    youtube_draft = %{draft() | platform: "youtube"}

    assert {:ok, _post} =
             Buffer.schedule(youtube_draft,
               channel_id: "youtube-channel",
               media_url: "https://cdn.example.com/short.mp4",
               mime_type: "video/mp4",
               title: "A RationalGrid Short"
             )
  end

  test "defaults the endpoint and media type to Buffer and image" do
    Application.put_env(:grid_media_manager, :buffer,
      api_key: "test-api-key",
      plug: {Req.Test, __MODULE__}
    )

    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.host == "api.buffer.com"

      {:ok, raw_body, conn} = Plug.Conn.read_body(conn)
      input = Jason.decode!(raw_body)["variables"]["input"]

      assert input["assets"] == [
               %{"image" => %{"url" => "https://cdn.example.com/default.jpg"}}
             ]

      success_response(conn)
    end)

    assert {:ok, _post} =
             Buffer.schedule(draft(),
               channel_id: "channel-123",
               media_url: "https://cdn.example.com/default.jpg"
             )
  end

  test "returns MutationError messages" do
    Req.Test.expect(__MODULE__, fn conn ->
      Req.Test.json(conn, %{
        "data" => %{
          "createPost" => %{
            "message" => "The selected channel queue is full"
          }
        }
      })
    end)

    assert Buffer.schedule(draft(), channel_id: "channel-123") ==
             {:error, "The selected channel queue is full"}
  end

  test "deletes a Buffer post by id" do
    Req.Test.expect(__MODULE__, fn conn ->
      {:ok, raw_body, conn} = Plug.Conn.read_body(conn)
      request = Jason.decode!(raw_body)

      assert request["query"] =~ "mutation DeletePost"
      assert request["variables"]["input"] == %{"id" => "post-123"}

      Req.Test.json(conn, %{
        "data" => %{"deletePost" => %{"id" => "post-123"}}
      })
    end)

    assert Buffer.delete_post("post-123") == {:ok, %{id: "post-123"}}
  end

  test "returns deletePost errors" do
    Req.Test.expect(__MODULE__, fn conn ->
      Req.Test.json(conn, %{
        "data" => %{"deletePost" => %{"message" => "Post cannot be deleted"}}
      })
    end)

    assert Buffer.delete_post("post-123") == {:error, "Post cannot be deleted"}
  end

  test "returns top-level GraphQL errors" do
    Req.Test.expect(__MODULE__, fn conn ->
      Req.Test.json(conn, %{
        "errors" => [
          %{"message" => "Not authorized"},
          %{"message" => "Channel could not be loaded"}
        ]
      })
    end)

    assert Buffer.schedule(draft(), channel_id: "channel-123") ==
             {:error, "Buffer GraphQL error: Not authorized; Channel could not be loaded"}
  end

  test "parses HTTP error bodies and does not retry createPost" do
    Req.Test.expect(__MODULE__, 1, fn conn ->
      conn
      |> Plug.Conn.put_status(503)
      |> Req.Test.json(%{
        "errors" => [%{"message" => "Buffer is temporarily unavailable"}]
      })
    end)

    assert Buffer.schedule(draft(), channel_id: "channel-123") ==
             {:error, "Buffer API request failed (HTTP 503): Buffer is temporarily unavailable"}
  end

  test "validates required scheduling input before making a request" do
    assert Buffer.schedule(draft(), []) == {:error, "channel_id is required"}

    assert Buffer.schedule(%PostDraft{body: "Post without a time"}, channel_id: "channel-123") ==
             {:error, "post draft scheduled_for must be a UTC DateTime"}

    assert Buffer.schedule(%PostDraft{scheduled_for: @scheduled_for}, channel_id: "channel-123") ==
             {:error, "post draft body is required"}
  end

  test "rejects unsupported or incomplete media input" do
    assert Buffer.schedule(draft(),
             channel_id: "channel-123",
             media_url: "https://cdn.example.com/promo.mov",
             mime_type: "video/quicktime"
           ) ==
             {:error,
              "unsupported media MIME type: video/quicktime; expected image/* or video/mp4"}

    assert Buffer.schedule(draft(), channel_id: "channel-123", mime_type: "image/png") ==
             {:error, "media_url is required when mime_type is provided"}

    assert Buffer.schedule(%{draft() | platform: "instagram"},
             channel_id: "channel-123",
             instagram_type: "unsupported"
           ) == {:error, "instagram_type must be post, story, reel, or carousel"}
  end

  test "rejects invalid items in a media list" do
    assert Buffer.schedule(draft(),
             channel_id: "channel-123",
             media: [[url: "https://cdn.example.com/missing-type.png"]]
           ) == {:error, "media item 1: mime_type is required"}

    assert Buffer.schedule(draft(),
             channel_id: "channel-123",
             media: [
               %{url: "https://cdn.example.com/valid.png", mime_type: "image/png"},
               %{url: "https://cdn.example.com/invalid.mov", mime_type: "video/quicktime"}
             ]
           ) ==
             {:error,
              "media item 2: unsupported media MIME type: video/quicktime; expected image/* or video/mp4"}

    assert Buffer.schedule(draft(), channel_id: "channel-123", media: ["invalid"]) ==
             {:error, "media item 1: must be a keyword list or map"}
  end

  test "returns a configuration error without an API key" do
    Application.put_env(:grid_media_manager, :buffer,
      endpoint: "https://buffer.test/graphql",
      plug: {Req.Test, __MODULE__}
    )

    assert Buffer.schedule(draft(), channel_id: "channel-123") ==
             {:error, "Buffer is not configured; set :grid_media_manager, :buffer, :api_key"}
  end

  defp draft do
    %PostDraft{
      body: "A focused campaign post",
      scheduled_for: @scheduled_for
    }
  end

  defp configure_snapshot_accounts do
    Application.put_env(:grid_media_manager, :buffer,
      text_api_key: "text-api-key",
      video_api_key: "video-api-key",
      text_organization_id: "text-org",
      video_organization_id: "video-org",
      text_channels: %{
        "x" => "text-x",
        "linkedin" => "text-linkedin",
        "facebook" => "text-facebook"
      },
      video_channels: %{
        "tiktok" => "video-tiktok",
        "instagram" => "video-instagram",
        "youtube" => "video-youtube"
      },
      endpoint: "https://buffer.test/graphql",
      plug: {Req.Test, __MODULE__}
    )
  end

  defp post_node(id, channel_id, status) do
    %{
      "id" => id,
      "text" => "A Buffer post",
      "status" => status,
      "dueAt" => "2026-08-22T10:00:00Z",
      "sentAt" => if(status == "sent", do: "2026-08-22T10:00:00Z"),
      "createdAt" => "2026-08-20T10:00:00Z",
      "channelId" => channel_id
    }
  end

  defp posts_response(conn, nodes, has_next_page, end_cursor) do
    Req.Test.json(conn, %{
      "data" => %{
        "posts" => %{
          "edges" => Enum.map(nodes, &%{"node" => &1}),
          "pageInfo" => %{
            "hasNextPage" => has_next_page,
            "endCursor" => end_cursor
          }
        }
      }
    })
  end

  defp success_response(conn) do
    Req.Test.json(conn, %{
      "data" => %{
        "createPost" => %{
          "post" => %{
            "id" => "post-456",
            "status" => "scheduled",
            "dueAt" => "2026-08-20T15:30:00.000Z"
          }
        }
      }
    })
  end
end
