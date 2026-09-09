defmodule GridMediaManager.Social.PerformanceTest do
  use GridMediaManager.DataCase
  alias GridMediaManager.{Campaigns, Repo}
  alias GridMediaManager.Campaigns.PostDraft
  alias GridMediaManager.Social.{Performance, PostMetric, Tracking, PostingSchedule}

  test "sync matches channel and external ID, reconciles sent posts and replaces cumulative metrics" do
    {:ok, campaign} =
      Campaigns.import_payload(
        %{
          "metadata" => %{"title" => "Knowledge", "url" => "https://rationalgrid.ai/g/knowledge"},
          "graph" => %{"nodes" => [], "edges" => []}
        },
        "metric-test"
      )

    draft =
      Repo.insert!(
        PostDraft.changeset(%PostDraft{}, %{
          campaign_id: campaign.id,
          platform: "x",
          angle: "discussion",
          body: "What would change your mind?",
          status: "scheduled",
          external_post_id: "sent-1"
        })
      )

    now = ~U[2026-09-09 12:00:00Z]

    post = %{
      id: "sent-1",
      status: "sent",
      sent_at: "2026-09-01T09:00:00Z",
      metrics_updated_at: nil,
      metrics: [
        %{type: "clicks", value: 3, unit: "count", name: "Clicks"},
        %{type: "reposts", value: 1, unit: "count", name: "Reposts"}
      ]
    }

    snapshot = %{
      fetched_at: now,
      platforms: %{
        "x" => %{posts: [post, %{post | id: "not-ours"}]},
        "facebook" => %{posts: [post]}
      }
    }

    assert {:ok, %{matched: 1}} = Performance.ingest(snapshot)
    assert Repo.get!(PostDraft, draft.id).status == "published"
    assert Repo.aggregate(PostMetric, :count) == 1
    assert [row] = Performance.results("x", now: now)
    assert row.clicks == 3
    assert row.shares == 1
    assert row.saves == nil
    assert row.exposure == nil

    assert {:ok, %{matched: 1}} = Performance.ingest(snapshot)
    assert Repo.aggregate(PostMetric, :count) == 1
    assert hd(Performance.results("x", now: now)).clicks == 3
    assert Performance.results("x", now: ~U[2026-09-02 12:00:00Z]) == []
  end

  test "tracking retains query targets and fragments, stays stable and leaves external sources untouched" do
    original = "https://rationalgrid.ai/g/knowledge?node=abc&highlight=42#claim"
    tagged = Tracking.url(original, "x", 12, "asset-7")
    assert Tracking.url(tagged, "x", 12, "asset-7") == tagged
    uri = URI.parse(tagged)
    assert uri.fragment == "claim"

    assert URI.decode_query(uri.query) == %{
             "node" => "abc",
             "highlight" => "42",
             "utm_campaign" => "grid-12",
             "utm_content" => "asset-7",
             "utm_source" => "x",
             "utm_medium" => "social"
           }

    assert Tracking.url("https://example.com/source", "x", 12, "asset-7") ==
             "https://example.com/source"
  end

  test "queue slots respect occupied days, weekdays and the future-time buffer" do
    now = ~U[2026-09-09 12:00:00Z]
    queued = [%{due_at: "2026-09-10T19:00:00Z"}]
    slots = PostingSchedule.slots("x", 8, queued, now: now)
    assert length(slots) == 8
    assert DateTime.to_date(hd(slots)) == ~D[2026-09-11]
    assert Enum.all?(slots, &(Date.day_of_week(DateTime.to_date(&1)) <= 5))
    assert length(Enum.uniq_by(slots, &DateTime.to_date/1)) == 8
    assert PostingSchedule.slots("x", 0, queued, now: now) == []
  end
end
