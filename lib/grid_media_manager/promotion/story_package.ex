defmodule GridMediaManager.Promotion.StoryPackage do
  @moduledoc """
  Defines the single canonical frame sequence for visual stories.

  Stories normally start with a thumbnail-ready cover, contain one or more
  editorial cards, and end with the same conversion-focused CTA. The explicit
  X destination contract omits the redundant cover and uses one content card
  followed by the CTA. Image carousels and videos render these sequences at
  their target dimensions.
  """

  @cta_title "Where do you stand?"
  @cta_body "Explore the complete map, follow the connections, and contribute your perspective on RationalGrid."

  def build(title, content_slides, opts \\ [])
      when is_binary(title) and is_list(content_slides) and is_list(opts) do
    cover = %{
      "kind" => "cover",
      "label" => Keyword.get(opts, :cover_label, "RationalGrid story"),
      "title" => title,
      "body" => Keyword.get(opts, :cover_body, "")
    }

    content_slides =
      Enum.reject(content_slides, &(Map.get(&1, "kind") in ["cover", "node_title", "cta"]))

    if Keyword.get(opts, :include_cover, true) do
      [cover | content_slides] ++ [cta_slide()]
    else
      content_slides ++ [cta_slide()]
    end
  end

  def cta_slide do
    %{
      "kind" => "cta",
      "label" => "Join the conversation",
      "title" => @cta_title,
      "body" => @cta_body
    }
  end
end
