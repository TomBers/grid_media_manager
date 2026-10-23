defmodule GridMediaManager.Promotion.CarouselVideoTest do
  use ExUnit.Case, async: true

  alias GridMediaManager.Campaigns.MediaAsset
  alias GridMediaManager.Promotion.CarouselVideo
  alias GridMediaManager.Promotion.ArtifactStore

  @tag timeout: 60_000
  @tag skip: is_nil(System.find_executable("ffmpeg")) or is_nil(System.find_executable("ffprobe"))
  test "exports looped theme audio for the full video and trims it for short selections" do
    frame =
      Application.app_dir(:grid_media_manager, "priv/static/images/rationalgrid-cta-story.png")

    bytes = File.read!(frame)

    artifact = %{
      "path" => frame,
      "sha256" => Base.encode16(:crypto.hash(:sha256, bytes)),
      "byte_size" => byte_size(bytes),
      "renderer_version" => ArtifactStore.renderer_version()
    }

    asset = %MediaAsset{
      id: System.unique_integer([:positive]),
      metadata: %{
        "slides" => [
          %{"kind" => "cover", "title" => "Soundtrack"},
          %{"kind" => "node_text", "body" => String.duplicate("word ", 30)},
          %{"kind" => "cta", "title" => "Explore"}
        ],
        "artifacts" => Map.new(1..3, &{to_string(&1), artifact})
      }
    }

    assert {:ok, path} = CarouselVideo.render_artifacts(asset, [1, 2, 3])
    on_exit(fn -> File.rm(path) end)
    assert {:ok, ^path} = CarouselVideo.render_artifacts(asset, [1, 2, 3])
    assert_soundtrack(path, CarouselVideo.asset_duration_seconds(asset, [1, 2, 3]))

    # The supplied theme is shorter than this export. Decode audio after its first loop.
    {samples, 0} =
      System.cmd("ffmpeg", [
        "-v",
        "error",
        "-ss",
        "14",
        "-i",
        path,
        "-t",
        "0.25",
        "-map",
        "0:a:0",
        "-f",
        "s16le",
        "-ac",
        "1",
        "pipe:1"
      ])

    assert byte_size(samples) > 1_000
    assert Enum.any?(:binary.bin_to_list(samples), &(&1 != 0))

    assert {:ok, short_path} = CarouselVideo.render_artifacts(asset, [1])
    on_exit(fn -> File.rm(short_path) end)
    refute short_path == path
    assert_soundtrack(short_path, 3.0)
  end

  defp assert_soundtrack(path, expected_duration) do
    {json, 0} =
      System.cmd("ffprobe", [
        "-v",
        "error",
        "-show_entries",
        "stream=codec_type,codec_name,width,height,duration",
        "-of",
        "json",
        path
      ])

    streams = Jason.decode!(json)["streams"]
    video = Enum.find(streams, &(&1["codec_type"] == "video"))
    audio = Enum.find(streams, &(&1["codec_type"] == "audio"))
    assert video["codec_name"] == "h264"
    assert {video["width"], video["height"]} == {1080, 1920}
    assert audio["codec_name"] == "aac"
    assert_in_delta String.to_float(audio["duration"]), expected_duration, 0.15
    assert_in_delta String.to_float(video["duration"]), expected_duration, 0.15
  end

  test "holds text-heavy frames longer than concise frames" do
    concise = %{"kind" => "cover", "title" => "A concise opening", "body" => ""}

    detailed = %{
      "kind" => "node_text",
      "title" => "",
      "body" => String.duplicate("Evidence needs enough time to be read clearly. ", 6)
    }

    assert CarouselVideo.slide_duration(concise) == 3.0
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
