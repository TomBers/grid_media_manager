defmodule GridMediaManager.Social.Performance do
  @moduledoc "Persists Buffer's reported metrics for posts created by this studio."

  import Ecto.Query
  alias GridMediaManager.Repo
  alias GridMediaManager.Campaigns.PostDraft
  alias GridMediaManager.Social.{Buffer, Platforms, PostMetric}

  def sync(opts \\ []) do
    buffer = Keyword.get(opts, :buffer, Buffer)

    with {:ok, snapshot} <- buffer.performance_snapshot(Platforms.ids(), []) do
      ingest(snapshot)
    end
  end

  def refresh_if_stale do
    latest = latest_sync()

    if is_nil(latest) or DateTime.diff(DateTime.utc_now(), latest, :hour) >= 6 do
      sync()
    else
      {:ok, :current}
    end
  end

  def ingest(snapshot) do
    fetched_at = DateTime.truncate(snapshot.fetched_at, :second)

    Repo.transact(fn ->
      drafts =
        Repo.all(from d in PostDraft, where: not is_nil(d.external_post_id))
        |> Map.new(&{{&1.platform, &1.external_post_id}, &1})

      matched =
        for {platform, channel} <- snapshot.platforms,
            post <- channel.posts,
            post.status == "sent",
            draft = drafts[{platform, post.id}],
            not is_nil(draft),
            sent_at = datetime(post.sent_at),
            not is_nil(sent_at) do
          metrics = Map.new(post.metrics, &{&1.type, Map.take(&1, [:value, :unit, :name])})

          row = %{
            post_draft_id: draft.id,
            external_post_id: post.id,
            platform: platform,
            metrics: metrics,
            sent_at: sent_at,
            metrics_updated_at: datetime(post.metrics_updated_at),
            fetched_at: fetched_at
          }

          # A missing metric remains missing. Never add counters across refreshes.
          Repo.insert_all(PostMetric, [row],
            conflict_target: [:post_draft_id],
            on_conflict:
              {:replace,
               [:external_post_id, :metrics, :sent_at, :metrics_updated_at, :fetched_at]}
          )

          # Only an explicit sent response reconciles status. No media cleanup is triggered.
          Repo.update_all(
            from(d in PostDraft,
              where:
                d.id == ^draft.id and d.external_post_id == ^post.id and d.status == "scheduled"
            ),
            set: [status: "published", published_at: sent_at, error_message: nil]
          )

          draft.id
        end

      {:ok, %{matched: length(matched), fetched_at: fetched_at}}
    end)
  end

  def results(platform, opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    cutoff = DateTime.add(now, -72, :hour)
    since = DateTime.add(now, -90, :day)

    Repo.all(
      from m in PostMetric,
        where: m.platform == ^platform and m.sent_at <= ^cutoff and m.sent_at >= ^since,
        preload: [post_draft: [:campaign, :media_asset]],
        order_by: [desc: m.sent_at]
    )
    |> Enum.map(fn metric ->
      %{
        id: metric.id,
        campaign_id: metric.post_draft.campaign_id,
        title: metric.post_draft.campaign.title,
        hook: metric.post_draft.body |> String.split("\n") |> List.first(),
        sent_at: metric.sent_at,
        fetched_at: metric.fetched_at,
        metrics_updated_at: metric.metrics_updated_at,
        exposure: value(metric, "impressions") || value(metric, "views"),
        exposure_label:
          if(is_nil(value(metric, "impressions")), do: "views", else: "impressions"),
        clicks: value(metric, "clicks"),
        saves: value(metric, "saves"),
        shares: value(metric, "shares") || value(metric, "reposts"),
        comments: value(metric, "comments"),
        reactions: value(metric, "reactions"),
        watch_seconds: value(metric, "averageTimeWatched")
      }
    end)
    |> Enum.sort_by(&{actions(&1), &1.exposure || 0}, :desc)
  end

  def actions(row), do: Enum.sum(Enum.map([:clicks, :saves, :shares, :comments], &(row[&1] || 0)))

  def latest_sync, do: Repo.one(from m in PostMetric, select: max(m.fetched_at))

  def editorial_feedback do
    Map.new(Platforms.ids(), fn platform ->
      rows = results(platform)

      {platform,
       %{
         sample_size: length(rows),
         note:
           "Directional, cumulative metrics for studio posts aged 72h–90d; not causal evidence. Missing metrics are unavailable.",
         examples:
           rows
           |> Enum.filter(&(actions(&1) > 0))
           |> Enum.take(3)
           |> Enum.map(
             &Map.take(&1, [:title, :hook, :exposure, :clicks, :saves, :shares, :comments])
           )
       }}
    end)
  end

  defp value(metric, type) do
    case metric.metrics[type] do
      %{"value" => value} when is_number(value) and value >= 0 -> value
      _ -> nil
    end
  end

  defp datetime(%DateTime{} = value), do: DateTime.truncate(value, :second)

  defp datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, value, _} -> DateTime.truncate(value, :second)
      _ -> nil
    end
  end

  defp datetime(_), do: nil
end
