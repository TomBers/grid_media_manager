defmodule GridMediaManagerWeb.AutonomousPlannerLiveTest do
  use GridMediaManagerWeb.ConnCase

  import Phoenix.LiveViewTest

  alias GridMediaManager.Automation
  alias GridMediaManager.Campaigns
  alias GridMediaManager.EditorialSelectorStub
  alias GridMediaManager.RationalGrid.GridIndex

  test "shows three completed editorial plans with studio handoffs", %{conn: conn} do
    topics = ["Agency", "Trust", "Learning"]

    Enum.each(topics, fn topic ->
      slug = String.downcase(topic)
      assert {:ok, _campaign} = Campaigns.import_payload(payload(topic, slug), slug)
    end)

    assert {:ok, _summaries} =
             GridIndex.replace_all(
               Enum.map(topics, fn topic ->
                 slug = String.downcase(topic)

                 %{
                   slug: slug,
                   title: topic,
                   url: "https://rationalgrid.ai/g/#{slug}",
                   graph_url: nil,
                   tags: [topic],
                   node_count: 3,
                   source: slug
                 }
               end)
             )

    assert {:ok, batch} = Automation.create_batch(topics)
    assert {:ok, completed} = Automation.run_batch(batch, selector: EditorialSelectorStub)

    {:ok, view, _html} = live(conn, ~p"/automation/#{completed.id}")

    assert has_element?(view, "#autonomous-planner")
    assert has_element?(view, "#editorial-batch-status", "completed")
    assert has_element?(view, "#editorial-plans > article", "A grounded question worth following")
    assert has_element?(view, "#editorial-plans", "Video + carousel")
    assert has_element?(view, "#editorial-plans", "AI answer")
    assert has_element?(view, "#editorial-plans", "Deep ocean")
    assert has_element?(view, "#editorial-plans", "A reflective analytical palette")
    assert has_element?(view, "#render-editorial-batch")

    Enum.each(completed.plans, fn plan ->
      assert has_element?(view, "#open-editorial-plan-#{plan.id}")
      assert has_element?(view, "#plan-moments-#{plan.id} > li")
      assert has_element?(view, "#plan-visual-#{plan.id}")
    end)
  end

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
          %{"id" => "1", "class" => "origin", "content" => "What about #{topic}?"},
          %{
            "id" => "2",
            "class" => "answer",
            "title" => "Why it matters",
            "content" => "An explanation."
          },
          %{
            "id" => "3",
            "class" => "answer",
            "title" => "What follows",
            "content" => "An implication."
          }
        ],
        "edges" => [
          %{"data" => %{"source" => "1", "target" => "2"}},
          %{"data" => %{"source" => "1", "target" => "3"}}
        ]
      },
      "highlights" => []
    }
  end
end
