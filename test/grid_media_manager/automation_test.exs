defmodule GridMediaManager.AutomationTest do
  use GridMediaManager.DataCase

  alias GridMediaManager.Automation
  alias GridMediaManager.Automation.EditorialBatch
  alias GridMediaManager.AutomationRendererStub
  alias GridMediaManager.Campaigns
  alias GridMediaManager.EditorialSelectorStub
  alias GridMediaManager.RationalGrid.GridIndex
  alias GridMediaManager.Repo

  test "plans three grounded stories and persists their selected candidate keys" do
    topics = ["Collective intelligence", "Digital identity", "Future education"]

    Enum.each(topics, fn topic ->
      slug = slug(topic)
      assert {:ok, _campaign} = Campaigns.import_payload(payload(topic, slug), slug)
    end)

    assert {:ok, _summaries} =
             GridIndex.replace_all(
               Enum.map(topics, fn topic ->
                 %{
                   slug: slug(topic),
                   title: topic,
                   url: "https://rationalgrid.ai/g/#{slug(topic)}",
                   graph_url: nil,
                   tags: [topic],
                   node_count: 3,
                   source: slug(topic)
                 }
               end)
             )

    assert {:ok, batch} = Automation.create_batch(topics)
    assert {:ok, completed} = Automation.run_batch(batch, selector: EditorialSelectorStub)

    assert completed.status == "completed"
    assert Enum.map(completed.plans, & &1.topic) == topics
    assert Enum.all?(completed.plans, &(&1.status == "planned"))
    assert Enum.all?(completed.plans, &(length(&1.selected_keys) == 3))
    assert Enum.all?(completed.plans, &(&1.confidence == 0.88))
    assert Enum.all?(completed.plans, &(&1.campaign_id != nil))
    assert Enum.all?(completed.plans, &(&1.recommended_format == "combined_carousel"))

    assert Enum.all?(completed.plans, fn plan ->
             plan.selection_details["visual_style"] == "deep_ocean" and
               plan.selection_details["cover_search_query"] ==
                 "lone figure ocean horizon blue dusk negative space" and
               plan.selection_details["cover"] == %{
                 "mode" => "photo",
                 "status" => "not_searched"
               }
           end)

    assert Enum.all?(completed.plans, fn plan ->
             plan.recommended_platforms ==
               ["x", "linkedin", "facebook", "tiktok", "instagram", "youtube"]
           end)

    assert Enum.all?(completed.plans, fn plan ->
             plan.selection_details["moments"] != [] and
               Enum.all?(plan.selection_details["moments"], &is_binary(&1["provenance"]))
           end)

    first_plan = List.first(completed.plans)
    assert %{assets: assets, errors: []} = Automation.generate_plan_package(first_plan.id)
    assert assets != []
    assert Enum.all?(assets, &(&1.style == "deep_ocean"))
  end

  test "accepts one to ten distinct explicit topics" do
    assert {:error, changeset} = Automation.create_batch("One topic\nOne topic\nThird topic")
    assert "must be different" in errors_on(changeset).topics

    assert {:ok, batch} = Automation.create_batch("Only one\nOnly two")
    assert batch.requested_count == 2

    assert {:error, changeset} = Automation.create_batch(Enum.map(1..11, &"Topic #{&1}"))
    assert "must be less than or equal to 10" in errors_on(changeset).requested_count

    assert {:error, changeset} = Automation.create_batch(nil)
    assert "can't be blank" in errors_on(changeset).topics
  end

  test "does not start a batch that another runner has already claimed" do
    assert {:ok, batch} = Automation.create_batch(["Claimed topic"])

    batch
    |> EditorialBatch.changeset(%{status: "planning"})
    |> Repo.update!()

    assert {:error, :editorial_batch_already_running} = Automation.run_batch(batch)
    assert Automation.get_batch(batch.id).status == "planning"
  end

  test "autopilot chooses the requested number of topics and preserves the theme" do
    topics = ["Agency", "Trust", "Learning"]

    Enum.each(topics, fn topic ->
      assert {:ok, _campaign} = Campaigns.import_payload(payload(topic, slug(topic)), slug(topic))
    end)

    assert {:ok, _summaries} =
             GridIndex.replace_all(
               Enum.map(topics, fn topic ->
                 %{
                   slug: slug(topic),
                   title: topic,
                   url: "https://rationalgrid.ai/g/#{slug(topic)}",
                   graph_url: nil,
                   tags: [topic],
                   node_count: 3,
                   source: slug(topic)
                 }
               end)
             )

    assert {:ok, batch} = Automation.create_autopilot_batch(2, "human agency")
    assert {:ok, completed} = Automation.run_batch(batch, selector: EditorialSelectorStub)

    assert completed.status == "completed"
    assert completed.requested_count == 2
    assert completed.theme == "human agency"
    assert length(completed.topics) == 2
    assert length(completed.plans) == 2
  end

  test "removes NUL characters from model metadata before persistence" do
    topic = "NUL metadata"
    prepare_source(topic)

    assert {:ok, batch} = Automation.create_batch([topic])
    assert {:ok, completed} = Automation.run_batch(batch, selector: EditorialSelectorStub)

    plan = List.first(completed.plans)
    refute String.contains?(plan.selection_details["visual_rationale"], <<0>>)

    assert plan.selection_details["visual_rationale"] ==
             "A reflective palette supports the subject."
  end

  test "autopilot records a useful failure when no source grids are available" do
    assert {:ok, batch} = Automation.create_autopilot_batch(1, nil)

    assert {:error, :no_matching_grids} =
             Automation.run_batch(batch, selector: EditorialSelectorStub)

    failed = Automation.get_batch(batch.id)
    assert failed.status == "failed"
    assert failed.error_message == "No RationalGrid sources are available."
  end

  test "plans and generates a complete batch through one resumable entrypoint" do
    topic = "Programmatic generation"
    prepare_source(topic)

    assert {:ok, batch} = Automation.create_batch([topic])

    assert {:ok, result} =
             Automation.generate_batch_assets(batch,
               selector: EditorialSelectorStub,
               renderer: AutomationRendererStub,
               renderer_options: [status: :complete]
             )

    assert result.batch_id == batch.id
    assert result.status == :complete
    assert [%{status: :complete, assets: assets, errors: []}] = result.plans
    assert length(assets) == 3
    assert Enum.all?(assets, &(&1.status == :complete))

    completed = Automation.get_batch(batch.id)
    completed_plan = List.first(completed.plans)
    campaign = completed_plan.campaign
    assert Campaigns.list_post_drafts(campaign) != []

    assert completed_plan.selection_details["generated_asset_ids"] ==
             Enum.map(assets, & &1.asset_id)

    assert completed_plan.selection_details["package_generation_version"] == 8
    assert is_binary(completed_plan.selection_details["campaign_visual_fingerprint"])

    assert {:ok, resumed} =
             Automation.generate_batch_assets(batch.id,
               renderer: AutomationRendererStub,
               renderer_options: [status: :complete]
             )

    assert Enum.map(List.first(resumed.plans).assets, & &1.asset_id) ==
             completed_plan.selection_details["generated_asset_ids"]

    assert {:ok, review_result} =
             Automation.review_batch(batch.id, editor: GridMediaManager.EditorStub)

    assert review_result.status == :complete
    assert [%{status: :complete, review: review}] = review_result.plans
    assert review["verdict"] == "revise"
    assert review["summary"] =~ "3 assets"

    reviewed_plan = Automation.get_batch(batch.id).plans |> List.first()
    assert reviewed_plan.selection_details["editor_review"]["overall_score"] == 74
  end

  test "bulk scheduling rejects an invalid start date before contacting Buffer" do
    topic = "Invalid publishing date"
    prepare_source(topic)

    assert {:ok, batch} = Automation.create_batch([topic])
    assert Automation.schedule_batch(batch.id, "not-a-date") == {:error, :invalid_start_date}
  end

  test "queue fill previews only vacancies, requires review and never schedules during preview" do
    previous = Application.get_env(:grid_media_manager, :buffer)
    previous_store = Application.get_env(:grid_media_manager, :artifact_store_path)
    root = Path.join(System.tmp_dir!(), "queue-fill-test-#{System.unique_integer([:positive])}")
    Application.put_env(:grid_media_manager, :artifact_store_path, root)

    on_exit(fn ->
      Application.put_env(:grid_media_manager, :buffer, previous)

      if previous_store,
        do: Application.put_env(:grid_media_manager, :artifact_store_path, previous_store),
        else: Application.delete_env(:grid_media_manager, :artifact_store_path)

      File.rm_rf!(root)
    end)

    platforms = GridMediaManager.Social.Platforms.ids()

    Application.put_env(:grid_media_manager, :buffer,
      text_api_key: "test-key",
      video_api_key: "test-key",
      text_organization_id: "test-org",
      video_organization_id: "test-org",
      text_channels: Map.new(platforms, &{&1, &1}),
      video_channels: Map.new(platforms, &{&1, &1}),
      endpoint: "https://buffer.test/graphql",
      plug: {Req.Test, __MODULE__}
    )

    Req.Test.stub(__MODULE__, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      request = Jason.decode!(body)
      assert request["query"] =~ "query BufferQueuePosts"

      posts =
        for platform <- request["variables"]["input"]["filter"]["channelIds"],
            index <- 1..if(platform == "x", do: 10, else: 9) do
          %{
            "node" => %{
              "id" => "#{platform}-#{index}",
              "channelId" => platform,
              "status" => "scheduled",
              "dueAt" => "2090-09-09T09:00:00Z"
            }
          }
        end

      Req.Test.json(conn, %{
        "data" => %{
          "posts" => %{
            "edges" => posts,
            "pageInfo" => %{"hasNextPage" => false, "endCursor" => nil}
          }
        }
      })
    end)

    topic = "Reviewable queue fill"
    prepare_source(topic)
    {:ok, batch} = Automation.create_batch([topic])
    {:ok, batch} = Automation.run_batch(batch, selector: EditorialSelectorStub)
    plan = hd(batch.plans)

    details =
      Map.put(plan.selection_details, "video_script", [
        "A first complete thought.",
        "A second complete thought.",
        "What would change your mind?"
      ])

    Repo.update!(Automation.EditorialPlan.changeset(plan, %{selection_details: details}))
    {:ok, _} = Automation.generate_batch_assets(batch.id, renderer: AutomationRendererStub)
    plan = hd(Automation.get_batch(batch.id).plans)

    assets =
      Enum.map(plan.selection_details["generated_asset_ids"], &Campaigns.get_media_asset!/1)

    campaign = Campaigns.get_campaign!(plan.campaign_id)

    assert {:error, :editor_review_required} =
             Automation.queue_fill_plan(batch.id, ~D[2090-09-08])

    for asset <- assets, index <- Campaigns.media_asset_slide_indexes(asset) do
      {:ok, _} =
        Campaigns.store_client_artifact(
          Campaigns.get_media_asset!(asset.id),
          index,
          <<137, 80, 78, 71, 13, 10, 26, 10, 0>>
        )
    end

    for draft <- Campaigns.list_post_drafts_for_assets(campaign, Enum.map(assets, & &1.id)) do
      {:ok, _} = Campaigns.approve_post_draft(draft.id)
    end

    assert {:ok, %{jobs: jobs}} = Automation.queue_fill_plan(batch.id, ~D[2090-09-08])
    assert length(jobs) == 5
    refute Enum.any?(jobs, &(&1.platform == "x"))

    assert Enum.all?(
             jobs,
             &(Date.compare(DateTime.to_date(&1.scheduled_for), ~D[2090-09-09]) == :gt)
           )

    assert Enum.all?(jobs, &is_nil(&1.draft.external_post_id))
  end

  test "quality preparation revises a weak package once and reuses the final review" do
    topic = "Editor guided refinement"
    prepare_source(topic)

    assert {:ok, batch} = Automation.create_batch([topic])

    opts = [
      selector: EditorialSelectorStub,
      editor: GridMediaManager.EditorStub,
      renderer: AutomationRendererStub,
      renderer_options: [status: :complete],
      max_revisions: 1
    ]

    assert {:ok, result} = Automation.prepare_quality_batch(batch.id, opts)
    assert [%{status: :revised}] = result.refinements
    assert result.generation.status == :complete
    assert result.review.status == :complete

    revised_plan = Automation.get_batch(batch.id).plans |> List.first()
    assert revised_plan.hook == "A sharper Editor-guided opening"
    assert revised_plan.selection_details["quality_revision_count"] == 1
    assert length(revised_plan.selection_details["quality_history"]) == 1

    assert {:ok, resumed} = Automation.prepare_quality_batch(batch.id, opts)
    assert [%{status: :limit_reached}] = resumed.refinements

    assert Automation.get_batch(batch.id).plans |> List.first() |> Map.fetch!(:hook) ==
             revised_plan.hook
  end

  test "reports browser artifacts as resumable work" do
    topic = "Browser artifact boundary"
    prepare_source(topic)

    assert {:ok, batch} = Automation.create_batch([topic])

    assert {:ok, result} =
             Automation.generate_batch_assets(batch,
               selector: EditorialSelectorStub,
               renderer: AutomationRendererStub,
               renderer_options: [status: :pending]
             )

    assert result.status == :awaiting_artifacts

    assert [%{status: :awaiting_artifacts, assets: assets, errors: []}] = result.plans

    assert Enum.all?(assets, fn asset ->
             asset.status == :awaiting_artifacts and asset.output.missing_indexes == [1]
           end)

    assert {:ok, resumed} =
             Automation.generate_batch_assets(batch.id,
               renderer: AutomationRendererStub,
               renderer_options: [status: :complete]
             )

    assert resumed.status == :complete
    assert [%{status: :complete}] = resumed.plans
  end

  test "contains renderer failures in a uniform per-plan result" do
    topic = "Contained renderer failure"
    prepare_source(topic)

    assert {:ok, batch} = Automation.create_batch([topic])

    assert {:ok, result} =
             Automation.generate_batch_assets(batch,
               selector: EditorialSelectorStub,
               renderer: AutomationRendererStub,
               renderer_options: [status: :failed]
             )

    assert result.status == :failed
    assert [%{status: :failed, assets: assets, errors: errors}] = result.plans
    assert Enum.all?(assets, &(&1.status == :failed))
    assert Enum.all?(errors, &(&1.stage == :rendering))
  end

  defp prepare_source(topic) do
    source_slug = slug(topic)
    assert {:ok, _campaign} = Campaigns.import_payload(payload(topic, source_slug), source_slug)

    assert {:ok, _summaries} =
             GridIndex.replace_all([
               %{
                 slug: source_slug,
                 title: topic,
                 url: "https://rationalgrid.ai/g/#{source_slug}",
                 graph_url: nil,
                 tags: [topic],
                 node_count: 3,
                 source: source_slug
               }
             ])
  end

  defp slug(topic), do: topic |> String.downcase() |> String.replace(" ", "-")

  defp payload(topic, slug) do
    %{
      "metadata" => %{
        "title" => topic,
        "slug" => slug,
        "url" => "https://rationalgrid.ai/g/#{slug}",
        "node_count" => 3,
        "tags" => [topic]
      },
      "graph" => %{
        "nodes" => [
          %{"id" => "1", "class" => "origin", "content" => "What matters about #{topic}?"},
          %{
            "id" => "2",
            "class" => "answer",
            "title" => "A central explanation",
            "content" => "A specific explanation of #{topic} and why it matters."
          },
          %{
            "id" => "3",
            "class" => "thesis",
            "title" => "A practical implication",
            "content" => "A grounded implication that follows from the explanation."
          }
        ],
        "edges" => [
          %{"data" => %{"source" => "1", "target" => "2"}},
          %{"data" => %{"source" => "1", "target" => "3"}}
        ]
      },
      "highlights" => [
        %{"id" => 1, "node_id" => "2", "text" => "A memorable point about #{topic}."}
      ]
    }
  end
end
