defmodule GridMediaManager.Promotion.StoryPackageTest do
  use ExUnit.Case, async: true

  alias GridMediaManager.Promotion.StoryPackage

  test "wraps every story with exactly one thumbnail cover and one canonical CTA" do
    content = [
      %{"kind" => "cover", "title" => "Old cover"},
      %{"kind" => "quote", "title" => "A useful question"},
      %{"kind" => "cta", "title" => "Old CTA"}
    ]

    slides = StoryPackage.build("Canonical title", content)

    assert [cover, card, cta] = slides

    assert cover == %{
             "kind" => "cover",
             "label" => "RationalGrid story",
             "title" => "Canonical title",
             "body" => ""
           }

    assert card["kind"] == "quote"
    assert cta["kind"] == "cta"
    assert cta["label"] == "RationalGrid"
    assert cta["title"] == "See what you think."
    assert cta["body"] =~ "Explore this idea at rationalgrid.ai."
  end
end
