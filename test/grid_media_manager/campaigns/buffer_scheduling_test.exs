defmodule GridMediaManager.Campaigns.BufferSchedulingTest do
  use GridMediaManager.DataCase, async: false

  alias GridMediaManager.Campaigns

  setup do
    previous_config = Application.get_env(:grid_media_manager, :buffer)

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
    end)

    :ok
  end

  test "schedules a bounded draft through Buffer and persists the external post" do
    assert {:ok, campaign} = Campaigns.import_payload(payload(), "buffer-scheduling")

    [draft | _] =
      Campaigns.list_post_drafts(campaign, platform: "x", media_asset_id: "campaign")

    scheduled_for =
      DateTime.utc_now() |> DateTime.add(3_600, :second) |> DateTime.truncate(:second)

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

    assert {:ok, scheduled} =
             Campaigns.schedule_post_draft(draft.id, DateTime.to_iso8601(scheduled_for))

    assert scheduled.status == "scheduled"
    assert scheduled.scheduled_for == scheduled_for
    assert scheduled.external_post_id == "buffer-post-1"
    assert scheduled.error_message == nil
  end

  test "rejects over-limit copy before calling Buffer" do
    assert {:ok, campaign} = Campaigns.import_payload(payload(), "buffer-over-limit")

    [draft | _] =
      Campaigns.list_post_drafts(campaign, platform: "x", media_asset_id: "campaign")

    assert {:ok, draft} =
             Campaigns.update_post_draft(draft, %{body: String.duplicate("a", 281)})

    scheduled_for = DateTime.utc_now() |> DateTime.add(3_600, :second)

    assert Campaigns.schedule_post_draft(draft.id, scheduled_for) ==
             {:error, "The draft is over the X character limit."}
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
