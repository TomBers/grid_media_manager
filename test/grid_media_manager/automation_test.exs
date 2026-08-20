defmodule GridMediaManager.AutomationTest do
  use GridMediaManager.DataCase

  alias GridMediaManager.Automation
  alias GridMediaManager.Campaigns
  alias GridMediaManager.EditorialSelectorStub
  alias GridMediaManager.RationalGrid.GridIndex

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

  test "autopilot records a useful failure when no source grids are available" do
    assert {:ok, batch} = Automation.create_autopilot_batch(1, nil)

    assert {:error, :no_matching_grids} =
             Automation.run_batch(batch, selector: EditorialSelectorStub)

    failed = Automation.get_batch(batch.id)
    assert failed.status == "failed"
    assert failed.error_message == "No RationalGrid sources are available."
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
