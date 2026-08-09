defmodule GridMediaManager.Promotion.CarouselVideoTest do
  use ExUnit.Case, async: true

  alias GridMediaManager.Campaigns.MediaAsset
  alias GridMediaManager.Promotion.CarouselVideo

  test "holds text-heavy frames longer than concise frames" do
    concise = %{"kind" => "cover", "title" => "A concise opening", "body" => ""}

    detailed = %{
      "kind" => "node_text",
      "title" => "",
      "body" => String.duplicate("Evidence needs enough time to be read clearly. ", 6)
    }

    assert CarouselVideo.slide_duration(concise) == 4.5
    assert CarouselVideo.slide_duration(detailed) > CarouselVideo.slide_duration(concise)
    assert CarouselVideo.slide_duration(detailed) <= 14.0
  end

  test "does not count hidden supporting copy on quote frames" do
    quote = %{
      "kind" => "highlight",
      "label" => "Highlight",
      "title" => "A concise quotation",
      "body" => String.duplicate("This supporting subtitle is not rendered. ", 10)
    }

    without_subtitle = Map.put(quote, "body", "")

    assert CarouselVideo.slide_duration(quote) == CarouselVideo.slide_duration(without_subtitle)
  end

  test "calculates an asset duration from its selected slide order" do
    slides = [
      %{"kind" => "cover", "title" => "Short", "body" => ""},
      %{"kind" => "node_text", "title" => "", "body" => String.duplicate("word ", 24)},
      %{"kind" => "cta", "title" => "Continue", "body" => "Learn more"}
    ]

    asset = %MediaAsset{metadata: %{"slides" => slides}}
    expected = slides |> CarouselVideo.slide_durations([2, 3]) |> CarouselVideo.duration_seconds()

    assert CarouselVideo.asset_duration_seconds(asset, [2, 3]) == expected
    assert expected > CarouselVideo.asset_duration_seconds(asset, [1, 3])
  end
end
