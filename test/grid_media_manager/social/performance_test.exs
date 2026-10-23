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

  test "queue slots fill both markets daily, preserve occupied windows and respect lead time" do
    now = ~U[2026-10-13 09:00:00Z]
    queued = [%{due_at: "2026-10-14T08:30:00Z"}]
    slots = PostingSchedule.market_slots("x", 8, queued, now: now)
    assert hd(slots) == %{market: :us, scheduled_for: ~U[2026-10-13 13:00:00Z]}
    assert Enum.at(slots, 1) == %{market: :us, scheduled_for: ~U[2026-10-14 13:00:00Z]}
    assert Enum.any?(slots, &(Date.day_of_week(DateTime.to_date(&1.scheduled_for)) == 6))

    assert Enum.all?(Enum.frequencies_by(slots, &DateTime.to_date(&1.scheduled_for)), fn {_, n} ->
             n <= 2
           end)

    assert PostingSchedule.slots("x", 0, queued, now: now) == []
    full_day = [%{due_at: "2026-10-14T08:00:00Z"}, %{due_at: "2026-10-14T13:00:00Z"}]

    assert PostingSchedule.slots("x", 1, full_day, now: now, start_date: ~D[2026-10-14]) == [
             ~U[2026-10-15 08:00:00Z]
           ]
  end

  test "UK and US windows follow their separate clock changes" do
    for {date, uk_hour, us_hour} <- [
          {~D[2026-03-07], 9, 14},
          {~D[2026-03-08], 9, 13},
          {~D[2026-03-29], 8, 13},
          {~D[2026-10-24], 8, 13},
          {~D[2026-10-25], 9, 13},
          {~D[2026-11-01], 9, 14}
        ] do
      [uk, us] = PostingSchedule.slots("x", 2, [], now: DateTime.new!(date, ~T[00:00:00]))
      assert uk.hour == uk_hour
      assert us.hour == us_hour
    end
  end

  test "market content stays in its window despite occupied slots and partial retries" do
    jobs = [
      %{id: 1, market: :uk},
      %{id: 2, market: :us},
      %{id: 3, market: :uk},
      %{id: 4, market: :us}
    ]

    queued = [%{due_at: "2026-10-14T08:00:00Z"}]
    opts = [now: ~U[2026-10-13 00:00:00Z], start_date: ~D[2026-10-14]]
    assigned = PostingSchedule.assign_jobs("x", jobs, queued, opts)
    assert Enum.map(assigned, & &1.id) == [2, 1, 4, 3]
    first = hd(assigned)
    remaining = Enum.reject(jobs, &(&1.id == first.id))

    retried =
      PostingSchedule.assign_jobs(
        "x",
        remaining,
        [%{due_at: DateTime.to_iso8601(first.scheduled_for)} | queued],
        opts
      )

    assert retried == tl(assigned)

    uk_only =
      PostingSchedule.assign_jobs("x", Enum.filter(jobs, &(&1.market == :uk)), queued, opts)

    assert length(uk_only) == 2
    assert Enum.all?(uk_only, &(&1.market == :uk))
  end
end
