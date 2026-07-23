defmodule GridMediaManager.Social.PlatformsTest do
  use ExUnit.Case, async: true

  alias GridMediaManager.Social.Platforms

  test "exposes only the supported text and video platform groups" do
    assert Platforms.text_ids() == ["x", "linkedin", "facebook"]
    assert Platforms.video_ids() == ["tiktok", "instagram", "youtube"]
    assert Platforms.ids() == Platforms.text_ids() ++ Platforms.video_ids()
    assert Enum.map(Platforms.all(), & &1.id) == Platforms.ids()
    refute "bluesky" in Platforms.ids()
    refute "substack" in Platforms.ids()
  end

  test "X character counts exclude hashtags" do
    text = "A post about maps #RationalGrid #Argument_Mapping"

    assert Platforms.character_count(text, "x") == String.length("A post about maps  ")
    assert Platforms.character_count(text, "linkedin") == String.length(text)
  end

  test "within_limit?/2 uses the platform-aware count" do
    assert Platforms.within_limit?(String.duplicate("a", 279) <> " #tag", "x")
    refute Platforms.within_limit?(String.duplicate("a", 301), "bluesky")
  end
end
