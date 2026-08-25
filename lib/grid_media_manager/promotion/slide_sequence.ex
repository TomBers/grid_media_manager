defmodule GridMediaManager.Promotion.SlideSequence do
  @moduledoc """
  Builds the canonical ordered slide sequence used by image carousels and videos.

  Content selection belongs here; rendering and video encoding consume the resulting
  slides without making further editorial decisions.
  """

  alias GridMediaManager.Campaigns.Campaign
  alias GridMediaManager.Promotion.ShareCard
  alias GridMediaManager.Promotion.StoryPackage

  def build(%Campaign{} = campaign, candidates, opts \\ [])
      when is_list(candidates) and is_list(opts) do
    reading_mode = Keyword.get(opts, :reading_mode, :full)

    slide_groups = Enum.map(candidates, &candidate_slides(campaign, &1, reading_mode))

    content_slides =
      if reading_mode == :short_video do
        short_video_slides(slide_groups)
      else
        Enum.flat_map(slide_groups, & &1)
      end

    StoryPackage.build(campaign.title, content_slides,
      include_cover: Keyword.get(opts, :include_cover, true)
    )
  end

  defp candidate_slides(
         _campaign,
         %{type: "key_node"} = candidate,
         :x_post
       ),
       do: [fallback_slide(candidate)]

  defp candidate_slides(
         %Campaign{} = campaign,
         %{type: "key_node", source_id: node_id} = candidate,
         reading_mode
       ) do
    case ShareCard.find_key_node(campaign, node_id) do
      node when is_map(node) ->
        reading_slides(campaign, node, reading_mode)
        |> Enum.map(&persisted_slide/1)

      _ ->
        [fallback_slide(candidate)]
    end
  end

  defp candidate_slides(_campaign, %{type: type} = candidate, _reading_mode)
       when type in ["question", "highlight"] do
    [
      %{
        "kind" => if(type == "highlight", do: "highlight", else: "quote"),
        "label" => Map.get(candidate, :label) || humanize(type),
        "title" => candidate.title,
        "body" => ""
      }
    ]
  end

  defp candidate_slides(_campaign, candidate, _reading_mode), do: [fallback_slide(candidate)]

  defp reading_slides(campaign, node, :short_video),
    do: ShareCard.node_short_video_slides(campaign, node)

  defp reading_slides(campaign, node, _reading_mode),
    do: ShareCard.node_reading_slides(campaign, node)

  defp persisted_slide(slide) when is_map(slide) do
    %{
      "kind" => "node_text",
      "label" => Map.get(slide, "label", ""),
      "title" => Map.get(slide, "title", ""),
      "body" => Map.get(slide, "body", ""),
      "blocks" => Enum.map(Map.get(slide, "blocks", []), &persisted_block/1)
    }
  end

  defp fallback_slide(candidate) do
    %{
      "kind" => "node_text",
      "label" => Map.get(candidate, :label) || humanize(candidate.type),
      "title" => candidate.title,
      "body" => Map.get(candidate, :excerpt) || ""
    }
  end

  defp short_video_slides(slide_groups) do
    primary_slides =
      slide_groups |> Enum.map(&List.first/1) |> Enum.reject(&is_nil/1) |> Enum.take(4)

    remaining_count = 4 - length(primary_slides)

    extra_slides =
      slide_groups
      |> Enum.flat_map(&Enum.drop(&1, 1))
      |> Enum.take(remaining_count)

    primary_slides ++ extra_slides
  end

  defp persisted_block(block) do
    block
    |> Enum.reduce(%{}, fn {key, value}, persisted ->
      key = to_string(key)

      if key in ["type", "text", "level", "marker"] do
        Map.put(persisted, key, to_string(value))
      else
        persisted
      end
    end)
  end

  defp humanize(type), do: type |> to_string() |> String.replace("_", " ") |> String.capitalize()
end
