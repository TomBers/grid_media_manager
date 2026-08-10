defmodule GridMediaManager.Campaigns.BufferSchedulingTest do
  use GridMediaManager.DataCase, async: false

  alias GridMediaManager.Campaigns
  alias GridMediaManager.Campaigns.PostDraft
  alias GridMediaManager.Repo

  @s3_environment_variables [
    "S3_BUCKET",
    "AWS_REGION",
    "AWS_ACCESS_KEY_ID",
    "AWS_SECRET_ACCESS_KEY",
    "AWS_SESSION_TOKEN",
    "S3_ENDPOINT",
    "S3_PUBLIC_BASE_URL"
  ]

  setup do
    previous_config = Application.get_env(:grid_media_manager, :buffer)
    previous_s3_config = Application.get_env(:grid_media_manager, :s3)
    previous_public_base_url = System.get_env("PUBLIC_BASE_URL")
    previous_s3_environment = Map.new(@s3_environment_variables, &{&1, System.get_env(&1)})

    System.delete_env("PUBLIC_BASE_URL")
    Enum.each(@s3_environment_variables, &System.delete_env/1)
    Application.delete_env(:grid_media_manager, :s3)

    Application.put_env(:grid_media_manager, :buffer,
      api_key: "buffer-test-key",
      endpoint: "https://buffer.test/graphql",
      channels: %{"x" => "x-channel"},
      plug: {Req.Test, __MODULE__}
    )

    Req.Test.verify_on_exit!()

    on_exit(fn ->
      if is_nil(previous_config) do
        Application.delete_env(:grid_media_manager, :buffer)
      else
        Application.put_env(:grid_media_manager, :buffer, previous_config)
      end

      if previous_s3_config do
        Application.put_env(:grid_media_manager, :s3, previous_s3_config)
      else
        Application.delete_env(:grid_media_manager, :s3)
      end

      if previous_public_base_url do
        System.put_env("PUBLIC_BASE_URL", previous_public_base_url)
      else
        System.delete_env("PUBLIC_BASE_URL")
      end

      Enum.each(previous_s3_environment, fn
        {name, nil} -> System.delete_env(name)
        {name, value} -> System.put_env(name, value)
      end)
    end)

    :ok
  end

  test "schedules a bounded draft through Buffer and persists the external post" do
    assert {:ok, campaign} = Campaigns.import_payload(payload(), "buffer-scheduling")
    draft = insert_text_draft(campaign)

    scheduled_for =
      DateTime.utc_now()
      |> DateTime.add(3_600, :second)
      |> DateTime.truncate(:second)
      |> then(&%{&1 | second: 0})

    Req.Test.expect(__MODULE__, fn conn ->
      {:ok, raw_body, conn} = Plug.Conn.read_body(conn)
      input = Jason.decode!(raw_body)["variables"]["input"]

      assert input["channelId"] == "x-channel"
      assert input["dueAt"] == DateTime.to_iso8601(scheduled_for)
      assert input["text"] == draft.body

      Req.Test.json(conn, %{
        "data" => %{
          "createPost" => %{
            "post" => %{
              "id" => "buffer-post-1",
              "status" => "scheduled",
              "dueAt" => DateTime.to_iso8601(scheduled_for)
            }
          }
        }
      })
    end)

    browser_datetime_value =
      scheduled_for
      |> DateTime.to_naive()
      |> NaiveDateTime.to_iso8601()
      |> String.slice(0, 16)

    assert {:ok, scheduled} =
             Campaigns.schedule_post_draft(draft.id, browser_datetime_value)

    assert scheduled.status == "scheduled"
    assert scheduled.scheduled_for == scheduled_for
    assert scheduled.external_post_id == "buffer-post-1"
    assert scheduled.error_message == nil
  end

  test "does not expose authenticated browser artifacts through PUBLIC_BASE_URL" do
    assert {:ok, campaign} = Campaigns.import_payload(payload(), "buffer-public-media")
    assert {:ok, asset} = Campaigns.generate_grid_asset(campaign)

    [draft] =
      Campaigns.list_post_drafts(campaign, platform: "x", media_asset_id: asset.id)

    System.put_env("PUBLIC_BASE_URL", "https://studio.example.com")
    assert {:error, message} = Campaigns.schedule_post_draft(draft.id, future_schedule_time())
    assert message == "Browser-rendered media requires S3 publishing before it can be scheduled."
  end

  test "rejects generated images when the server only has a local URL" do
    assert {:ok, campaign} = Campaigns.import_payload(payload(), "buffer-local-media")
    assert {:ok, asset} = Campaigns.generate_grid_asset(campaign)

    [draft] =
      Campaigns.list_post_drafts(campaign, platform: "x", media_asset_id: asset.id)

    assert {:error, message} = Campaigns.schedule_post_draft(draft.id, future_schedule_time())
    assert message =~ "requires S3 publishing"
  end

  test "rejects over-limit copy before calling Buffer" do
    assert {:ok, campaign} = Campaigns.import_payload(payload(), "buffer-over-limit")
    draft = insert_text_draft(campaign)

    assert {:ok, draft} =
             Campaigns.update_post_draft(draft, %{body: String.duplicate("a", 281)})

    scheduled_for = DateTime.utc_now() |> DateTime.add(3_600, :second)

    assert Campaigns.schedule_post_draft(draft.id, scheduled_for) ==
             {:error, "The draft is over the X character limit."}
  end

  defp future_schedule_time do
    DateTime.utc_now()
    |> DateTime.add(3_600, :second)
    |> DateTime.truncate(:second)
    |> then(&%{&1 | second: 0})
  end

  defp insert_text_draft(campaign) do
    %PostDraft{}
    |> PostDraft.changeset(%{
      campaign_id: campaign.id,
      platform: "x",
      angle: "discussion",
      body: "A bounded text-only post.",
      status: "draft"
    })
    |> Repo.insert!()
  end

  defp payload do
    %{
      "metadata" => %{
        "title" => "How should we preserve agency?",
        "slug" => "preserve-agency-buffer",
        "url" => "https://rationalgrid.ai/g/preserve-agency-buffer",
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
