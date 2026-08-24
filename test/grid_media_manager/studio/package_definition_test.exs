defmodule GridMediaManager.Studio.PackageDefinitionTest do
  use ExUnit.Case, async: true

  alias GridMediaManager.Campaigns.MediaAsset
  alias GridMediaManager.Studio.PackageDefinition

  test "maps package modes, formats, platforms, and generated assets consistently" do
    assert PackageDefinition.format_for_mode("video") == "story_video"
    assert PackageDefinition.format_for_mode("bundle") == "combined_carousel"
    assert PackageDefinition.mode_for_format("long_form") == "long_form"
    assert PackageDefinition.platforms_for_mode("video") == ["tiktok", "instagram", "youtube"]

    video = %MediaAsset{mime_type: "video/mp4", recommended_platforms: []}

    image = %MediaAsset{
      mime_type: "image/png",
      recommended_platforms: ["x", "linkedin", "facebook"]
    }

    assert PackageDefinition.mode_for_assets([video, image]) == "bundle"

    assert PackageDefinition.platforms_for_assets([video, image]) == [
             "x",
             "linkedin",
             "facebook",
             "tiktok",
             "instagram",
             "youtube"
           ]
  end

  test "filters requested destinations against the package's available platforms" do
    assert PackageDefinition.requested_platforms(
             %{"platform" => "youtube,linkedin,unknown"},
             ["linkedin", "youtube"]
           ) == ["linkedin", "youtube"]
  end
end
