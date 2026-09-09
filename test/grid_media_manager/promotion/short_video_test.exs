defmodule GridMediaManager.Promotion.ShortVideoTest do
  use ExUnit.Case, async: true
  alias GridMediaManager.Promotion.{ShortVideo, StoryPackage, CarouselVideo}
  alias GridMediaManager.Campaigns.MediaAsset

  test "a concise three-beat story stays readable and below the duration limit" do
    script = [
      "An observation can challenge an assumption.",
      "But one observation may have several explanations.",
      "Which alternative would you test first?"
    ]

    assert ShortVideo.valid_script?(script)
    slides = StoryPackage.build("What would change your mind?", ShortVideo.script_slides(script))
    assert ShortVideo.issues(slides) == []
    assert CarouselVideo.slide_duration(hd(slides)) < 4
    assert CarouselVideo.duration_seconds(CarouselVideo.slide_durations(slides)) <= 45
  end

  test "publishing rejects dense quotes and ignores deselected frames" do
    slides =
      StoryPackage.build("A question", [
        %{"kind" => "highlight", "label" => "Quote", "title" => String.duplicate("word ", 30)},
        %{"kind" => "node_text", "body" => "A complete first thought."},
        %{"kind" => "node_text", "body" => "A complete second thought."}
      ])

    asset = %MediaAsset{mime_type: "video/mp4", metadata: %{"slides" => slides}}
    assert {:error, message} = ShortVideo.validate_asset(asset)
    assert message =~ "Frame 2"

    assert :ok =
             ShortVideo.validate_asset(%{
               asset
               | metadata: Map.put(asset.metadata, "selected_slide_indexes", [1, 3, 4, 5])
             })

    refute ShortVideo.valid_script?([String.duplicate("word ", 23), "A complete thought."])
  end
end
