defmodule GridMediaManagerWeb.PostReviewLiveTest do
  use GridMediaManagerWeb.ConnCase

  import Phoenix.LiveViewTest

  alias GridMediaManager.Campaigns
  alias GridMediaManager.Campaigns.MediaAsset
  alias GridMediaManager.Repo
  alias GridMediaManager.Social.Platforms

  @png <<137, 80, 78, 71, 13, 10, 26, 10, 0, 1, 2, 3>>

  setup do
    previous_root = Application.get_env(:grid_media_manager, :artifact_store_path)

    root =
      Path.join(
        System.tmp_dir!(),
        "grid-media-manager-review-test-#{System.unique_integer([:positive])}"
      )

    Application.put_env(:grid_media_manager, :artifact_store_path, root)

    on_exit(fn ->
      File.rm_rf!(root)

      if previous_root do
        Application.put_env(:grid_media_manager, :artifact_store_path, previous_root)
      else
        Application.delete_env(:grid_media_manager, :artifact_store_path)
      end
    end)

    :ok
  end

  test "shows proposed posts once per logical package and approves the global queue", %{
    conn: conn
  } do
    assert {:ok, campaign} = Campaigns.import_payload(simplified_payload(), "post-review-queue")
    add_video_asset(campaign)

    {:ok, view, _html} = live(conn, ~p"/posts/review")

    assert has_element?(view, "#post-review-summary")
    assert has_element?(view, "#post-review-packages article")
    assert has_element?(view, "#approve-all-posts", "Approve")
    assert has_element?(view, "[id^='open-post-page-']", campaign.title)
    assert has_element?(view, "[id^='open-post-page-'][href='/campaigns/#{campaign.id}/studio']")
    assert has_element?(view, "#post-review-packages", "Suggested publish time")
    refute has_element?(view, "#post-review-packages", "Text-only post")

    assert Campaigns.list_post_drafts(campaign)
           |> Enum.filter(& &1.media_asset_id)
           |> Enum.all?(&is_nil(&1.suggested_for))

    view |> element("#approve-all-posts") |> render_click()

    drafts = Campaigns.list_post_drafts(campaign)
    media_drafts = Enum.filter(drafts, & &1.media_asset_id)
    assert Enum.all?(media_drafts, &(&1.platform in Platforms.video_ids()))
    assert Enum.all?(media_drafts, &(&1.status == "approved"))
    assert has_element?(view, "#approve-all-posts[disabled]")
    assert has_element?(view, "#flash-info", "Approved")
    assert has_element?(view, "#empty-post-review-packages")

    view |> element("#post-review-filter-approved") |> render_click()
    assert has_element?(view, "#post-review-packages", "Approved")
    assert has_element?(view, "#post-review-summary", "Up to date")
    refute has_element?(view, "#post-review-packages button[id^='remove-post-package-']")
  end

  test "removes a proposed post package from the global queue", %{conn: conn} do
    assert {:ok, campaign} = Campaigns.import_payload(simplified_payload(), "post-review-delete")
    add_video_asset(campaign)

    {:ok, view, _html} = live(conn, ~p"/posts/review")

    before_count = length(Campaigns.list_post_drafts(campaign))

    remove_button =
      element(
        view,
        "#post-review-packages article:first-of-type button[id^='remove-post-package-']"
      )

    assert render_click(remove_button) =~ "Removed the proposal"
    assert length(Campaigns.list_post_drafts(campaign)) < before_count
    assert has_element?(view, "#flash-info", "Removed the proposal")
  end

  test "shows every selected carousel image in order", %{conn: conn} do
    assert {:ok, campaign} =
             Campaigns.import_payload(simplified_payload(), "post-review-carousel")

    asset = add_text_asset(campaign)

    draft =
      Campaigns.list_post_drafts(campaign, media_asset_id: asset.id)
      |> Enum.min_by(& &1.id)

    {:ok, view, _html} = live(conn, ~p"/posts/review")

    package_id = "post-review-package-#{campaign.id}-#{draft.id}"
    assert has_element?(view, "##{package_id}-carousel-previews")
    assert has_element?(view, "##{package_id}-carousel-slide-1")
    assert has_element?(view, "##{package_id}-carousel-slide-2")
    assert has_element?(view, "##{package_id}-carousel-slide-4")
    refute has_element?(view, "##{package_id}-carousel-slide-3")
  end

  defp add_video_asset(campaign) do
    asset =
      %MediaAsset{}
      |> MediaAsset.changeset(%{
        campaign_id: campaign.id,
        title: "Generated video",
        kind: "curated_carousel_video",
        url: "/campaigns/#{campaign.id}/test-video.mp4",
        mime_type: "video/mp4",
        recommended_platforms: Platforms.video_ids()
      })
      |> Repo.insert!()

    assert :ok =
             Campaigns.ensure_post_drafts_for_platforms(campaign, [asset], Platforms.video_ids())

    assert {:ok, asset} = Campaigns.store_client_artifact(asset, 1, @png)
    asset
  end

  defp add_text_asset(campaign) do
    asset =
      %MediaAsset{}
      |> MediaAsset.changeset(%{
        campaign_id: campaign.id,
        title: "Generated carousel",
        kind: "curated_carousel",
        url: "/campaigns/#{campaign.id}/curated-carousels/test/slides/1/image.png",
        mime_type: "image/png",
        source_type: "curated_carousel",
        source_id: "test",
        style: "editorial_dark",
        recommended_platforms: Platforms.text_ids(),
        metadata: %{
          "slide_count" => 4,
          "selected_slide_indexes" => [1, 2, 4],
          "slides" => [%{}, %{}, %{}, %{}]
        }
      })
      |> Repo.insert!()

    assert :ok =
             Campaigns.ensure_post_drafts_for_platforms(campaign, [asset], Platforms.text_ids())

    asset =
      Enum.reduce([1, 2, 4], asset, fn index, asset ->
        assert {:ok, asset} = Campaigns.store_client_artifact(asset, index, @png)
        asset
      end)

    asset
  end

  defp simplified_payload do
    %{
      "metadata" => %{
        "title" => "A post review queue",
        "slug" => "post-review-queue",
        "url" => "https://rationalgrid.ai/g/post-review-queue",
        "node_count" => 1,
        "tags" => ["Reasoning"]
      },
      "graph" => %{
        "nodes" => [
          %{
            "id" => "1",
            "class" => "answer",
            "title" => "A useful idea",
            "content" => "A coherent explanation can become a useful post."
          }
        ],
        "edges" => []
      },
      "highlights" => []
    }
  end
end
