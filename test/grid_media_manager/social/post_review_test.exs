defmodule GridMediaManager.Social.PostReviewTest do
  use ExUnit.Case, async: true

  alias GridMediaManager.Campaigns.MediaAsset
  alias GridMediaManager.Campaigns.PostDraft
  alias GridMediaManager.Social.PostReview

  @now ~U[2026-08-20 12:00:00Z]

  test "groups shared channel drafts into logical posts with daily text and video slots" do
    text_asset = %MediaAsset{id: 11, title: "Text card", mime_type: "image/png"}
    second_text_asset = %MediaAsset{id: 13, title: "Text card two", mime_type: "image/png"}
    video_asset = %MediaAsset{id: 12, title: "Video", mime_type: "video/mp4"}

    drafts =
      [
        draft(1, "x", text_asset, "Text post one"),
        draft(2, "linkedin", text_asset, "Text post one"),
        draft(3, "facebook", text_asset, "Text post one"),
        draft(4, "tiktok", video_asset, "Video post one"),
        draft(5, "instagram", video_asset, "Video post one"),
        draft(6, "youtube", video_asset, "Video post one"),
        draft(7, "x", second_text_asset, "Text post two"),
        draft(8, "linkedin", second_text_asset, "Text post two"),
        draft(9, "facebook", second_text_asset, "Text post two")
      ]

    [text_one, video_one, text_two] = PostReview.packages(drafts, @now)

    assert length(PostReview.packages(drafts, @now)) == 3
    assert text_one.kind == :text
    assert video_one.kind == :video
    assert text_one.platforms == ["x", "linkedin", "facebook"]
    assert video_one.platforms == ["tiktok", "instagram", "youtube"]
    assert text_one.suggested_for == ~U[2026-08-21 15:00:00Z]
    assert video_one.suggested_for == ~U[2026-08-21 18:00:00Z]
    assert text_two.suggested_for == ~U[2026-08-22 15:00:00Z]
    assert PostReview.pending?(text_one)
  end

  test "uses an existing scheduled time instead of replacing it with a suggestion" do
    scheduled_for = ~U[2026-08-25 16:30:00Z]
    asset = %MediaAsset{id: 11, title: "Text card", mime_type: "image/png"}

    draft = %{
      draft(1, "x", asset, "Scheduled copy")
      | scheduled_for: scheduled_for,
        status: "scheduled"
    }

    [package] = PostReview.packages([draft], @now)

    assert package.suggested_for == scheduled_for
    refute package.suggested?
    refute PostReview.pending?(package)
  end

  defp draft(id, platform, asset, body) do
    %PostDraft{
      id: id,
      platform: platform,
      angle: "visual",
      body: body,
      status: "draft",
      media_asset_id: asset.id,
      media_asset: asset
    }
  end
end
