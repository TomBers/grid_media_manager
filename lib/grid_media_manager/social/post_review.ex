defmodule GridMediaManager.Social.PostReview do
  @moduledoc """
  Shapes post drafts into logical review packages and assigns suggested slots.

  A package represents one piece of copy shared by the platform group it targets,
  so three channel drafts appear as one item in the editorial review queue.
  """

  alias GridMediaManager.Campaigns
  alias GridMediaManager.Campaigns.Campaign
  alias GridMediaManager.Campaigns.MediaAsset
  alias GridMediaManager.Promotion.ArtifactStore
  alias GridMediaManager.Social.Platforms

  @text_hour 15
  @video_hour 18

  def packages(drafts, now \\ DateTime.utc_now()) when is_list(drafts) do
    drafts
    |> Enum.sort_by(&{&1.id || 0, &1.platform})
    |> Enum.group_by(&package_key/1)
    |> Map.values()
    |> Enum.sort_by(fn group -> {List.first(group).id || 0, List.first(group).platform} end)
    |> Enum.map_reduce(%{text: 0, video: 0}, &build_package(&1, &2, now))
    |> elem(0)
  end

  def pending?(%{reviewable_ids: ids}), do: ids != []

  def queueable?(draft),
    do: draft.status in ["draft", "copied", "approved", "scheduled", "published", "failed"]

  def valid_for_asset?(draft) do
    case draft.media_asset do
      nil -> false
      %{mime_type: "video/mp4"} -> draft.platform in Platforms.video_ids()
      _asset -> draft.platform in Platforms.text_ids()
    end
  end

  defp build_package(drafts, counters, now) do
    drafts = Enum.sort_by(drafts, &{&1.id || 0, &1.platform})
    kind = package_kind(drafts)
    day_index = Map.fetch!(counters, kind)

    scheduled_for =
      Enum.find_value(drafts, fn draft ->
        if draft.status == "scheduled", do: draft.scheduled_for
      end)

    stored_suggestion = Enum.find_value(drafts, & &1.suggested_for)
    suggested_for = scheduled_for || stored_suggestion || suggested_time(now, day_index, kind)
    asset = Enum.find_value(drafts, & &1.media_asset)
    copy_variants = copy_variants(drafts)
    campaign = campaign_for(drafts)
    preview_images = preview_images(asset, campaign)

    package = %{
      id: "post-review-package-#{List.first(drafts).campaign_id}-#{List.first(drafts).id}",
      drafts: drafts,
      asset: asset,
      preview_images: preview_images,
      artifacts_ready?: artifacts_ready?(asset),
      campaign: campaign,
      campaign_id: List.first(drafts).campaign_id,
      kind: kind,
      body: List.first(copy_variants).body,
      copy_variants: copy_variants,
      platforms: Enum.map(drafts, & &1.platform) |> Enum.uniq(),
      statuses: Enum.map(drafts, & &1.status) |> Enum.uniq(),
      status: package_status(drafts),
      reviewable_ids: Enum.filter(drafts, &reviewable_draft?/1) |> Enum.map(& &1.id),
      deletable_ids: Enum.filter(drafts, &deletable_draft?/1) |> Enum.map(& &1.id),
      suggested_for: suggested_for,
      suggested?: is_nil(scheduled_for)
    }

    {package, Map.update!(counters, kind, &(&1 + 1))}
  end

  defp package_key(draft) do
    {draft.campaign_id, draft.media_asset_id, draft.angle, draft_kind(draft)}
  end

  defp campaign_for(drafts) do
    case List.first(drafts).campaign do
      %Campaign{} = campaign -> campaign
      _ -> nil
    end
  end

  defp preview_images(%MediaAsset{kind: "curated_carousel"} = asset, %Campaign{}) do
    metadata = asset.metadata || %{}
    slide_count = Map.get(metadata, "slide_count", 0)

    indexes =
      case Map.get(metadata, "selected_slide_indexes") do
        indexes when is_list(indexes) and indexes != [] -> indexes
        _ -> if(slide_count > 0, do: Enum.to_list(1..slide_count), else: [])
      end

    Enum.map(indexes, fn index ->
      %{
        index: index,
        url: Campaigns.media_asset_artifact_url(asset, index)
      }
    end)
  end

  defp preview_images(%MediaAsset{mime_type: "video/mp4", id: id}, _campaign),
    do: [%{index: 1, url: "/media-assets/#{id}/artifact.mp4"}]

  defp preview_images(%MediaAsset{} = asset, _campaign),
    do: [%{index: 1, url: Campaigns.media_asset_artifact_url(asset)}]

  defp preview_images(nil, _campaign), do: []

  defp artifacts_ready?(%MediaAsset{} = asset) do
    ArtifactStore.ready?(asset, Campaigns.media_asset_slide_indexes(asset))
  end

  defp artifacts_ready?(nil), do: false

  defp package_kind(drafts) do
    draft_kind(List.first(drafts))
  end

  defp draft_kind(draft), do: if(video_draft?(draft), do: :video, else: :text)

  defp video_draft?(draft) do
    draft.platform in Platforms.video_ids() or
      match?(%{mime_type: "video/mp4"}, draft.media_asset)
  end

  defp reviewable_draft?(draft), do: draft.status in ["draft", "copied"]
  defp deletable_draft?(draft), do: draft.status in ["draft", "copied", "failed"]

  defp copy_variants(drafts) do
    drafts
    |> Enum.group_by(& &1.body)
    |> Map.values()
    |> Enum.map(fn variant_drafts ->
      %{
        body: List.first(variant_drafts).body,
        platforms: Enum.map(variant_drafts, & &1.platform)
      }
    end)
    |> Enum.sort_by(&List.first(&1.platforms))
  end

  defp package_status(drafts) do
    statuses = Enum.map(drafts, & &1.status)

    cond do
      Enum.all?(statuses, &(&1 == "published")) -> "published"
      Enum.any?(statuses, &(&1 == "scheduled")) -> "scheduled"
      Enum.all?(statuses, &(&1 == "approved")) -> "approved"
      Enum.any?(statuses, &(&1 == "failed")) -> "failed"
      true -> "draft"
    end
  end

  defp suggested_time(now, day_index, :text), do: suggested_time(now, day_index, @text_hour)
  defp suggested_time(now, day_index, :video), do: suggested_time(now, day_index, @video_hour)

  defp suggested_time(now, day_index, hour) do
    date = Date.add(DateTime.to_date(now), day_index + 1)
    {:ok, time} = Time.new(hour, 0, 0)
    {:ok, datetime} = DateTime.new(date, time, "Etc/UTC")
    datetime
  end
end
