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
