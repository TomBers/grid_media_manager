defmodule GridMediaManager.Weekly.ServicesTest do
  use GridMediaManager.DataCase
  alias GridMediaManager.{Automation, Campaigns, Weekly}
  alias GridMediaManager.Weekly.{Services, SourceSelector, Story, Run}
  import GridMediaManager.RationalGridMCPHelpers

  setup do
    connected()
    setup_http()
    :ok
  end

  defp campaign do
    {:ok, c} =
      Campaigns.import_payload(
        %{
          "metadata" => %{
            "id" => "weekly-service-source",
            "title" => "Can comfort make us less free?",
            "url" => "https://rationalgrid.ai/g/weekly-service-source"
          },
          "graph" => %{
            "nodes" => [
              %{
                "id" => "1",
                "class" => "origin",
                "content" => "## Can comfort make us less free?"
              },
              %{
                "id" => "2",
                "class" => "answer",
                "content" =>
                  "# Comfort and agency\n\n" <>
                    String.duplicate(
                      "Material security can give people room to reflect. Convenience can also displace deliberate choice. These effects depend on context.\n\n",
                      8
                    )
              }
            ],
            "edges" => [%{"from" => "1", "to" => "2"}]
          }
        },
        "weekly-service-source"
      )

    c
  end

  test "one applied package caches exact assets and preserves six tailored captions on resume" do
    c = campaign()
    {:ok, b} = Automation.create_batch([c.title])

    {:ok, p} =
      Automation.plan_campaign(b.id, c.id, 1, selector: SourceSelector, cover_search: false)

    details = Map.put(p.selection_details, "cover", %{"mode" => "text", "status" => "selected"})
    Weekly.save(p, %{selection_details: details})
    Weekly.save(b, %{status: "completed"})
    {:ok, copy} = GridMediaManager.WeeklyServicesStub.copy(nil, nil)
    story = %Story{plan_id: p.id, copy: copy}
    run = %Run{theme: "Philosophy unrelated to AI"}
    assert {:ok, review} = Services.apply_copy(run, story)
    story = %{story | review: Jason.decode!(Jason.encode!(review))}
    assert length(Services.drafts(story)) == 6
    assert length(Services.assets(story)) == 3

    for a <- Services.assets(story), a.mime_type != "video/mp4" do
      assert length(Campaigns.media_asset_slide_indexes(a)) == 2
    end

    before = Services.drafts(story) |> Map.new(&{&1.id, &1.body})
    assert {:ok, %{status: :awaiting_artifacts}} = Automation.generate_batch_assets(b.id)
    assert Map.new(Services.drafts(story), &{&1.id, &1.body}) == before
    assert Automation.get_plan(p.id).selection_details["generated_asset_ids"] == review.asset_ids
  end

  test "anonymous access must correspond to the requested grid, without owner credentials" do
    {:ok, e} =
      GridMediaManager.RationalGrid.Explorations.propose(
        %{question: "Can comfort make us less free?", rationale: "Test a clear tension."},
        %{}
      )

    Weekly.save(e, %{result: %{"grid" => %{"id" => "wanted-grid"}}})

    stub(fn conn ->
      assert Plug.Conn.get_req_header(conn, "authorization") == []

      rpc(conn, fn "read_grid", _ ->
        %{"grid" => %{"id" => "different-grid", "visibility" => "public"}}
      end)
    end)

    assert {:ok, false} = Services.public?(%Story{exploration_id: e.id})

    stub(fn conn ->
      rpc(conn, fn "read_grid", _ ->
        %{"grid" => %{"id" => "wanted-grid", "visibility" => "public"}}
      end)
    end)

    assert {:ok, true} = Services.public?(%Story{exploration_id: e.id})
  end

  test "anonymous publication checks also handle streamed MCP replies" do
    {:ok, e} =
      GridMediaManager.RationalGrid.Explorations.propose(
        %{question: "Can comfort make us less free?", rationale: "Test a clear tension."},
        %{}
      )

    Weekly.save(e, %{result: %{"grid" => %{"id" => "streamed-grid"}}})

    stub(fn conn ->
      assert Plug.Conn.get_req_header(conn, "authorization") == []
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      id = Jason.decode!(body)["id"]

      data =
        Jason.encode!(%{
          jsonrpc: "2.0",
          id: id,
          result: %{structuredContent: %{grid: %{id: "streamed-grid", visibility: "public"}}}
        })

      conn
      |> Plug.Conn.put_resp_content_type("text/event-stream")
      |> Plug.Conn.send_resp(200, "event: message\ndata: " <> data <> "\n\n")
    end)

    assert {:ok, true} = Services.public?(%Story{exploration_id: e.id})
  end
end
