defmodule GridMediaManager.Promotion.SlideSequence do
  @moduledoc """
  Builds the canonical ordered slide sequence used by image carousels and videos.

  Content selection belongs here; rendering and video encoding consume the resulting
  slides without making further editorial decisions.
  """

  alias GridMediaManager.Campaigns.Campaign
  alias GridMediaManager.Promotion.ShareCard

  def build(%Campaign{} = campaign, candidates) when is_list(candidates) do
    cover = %{
      "kind" => "cover",
      "label" => "RationalGrid story",
      "title" => campaign.title,
      "body" => ""
    }

    closing = %{
      "kind" => "cta",
      "label" => "Learn more",
      "title" => "Continue on RationalGrid.ai",
      "body" => ""
    }

    [cover] ++ Enum.flat_map(candidates, &candidate_slides(campaign, &1)) ++ [closing]
  end

  defp candidate_slides(
         %Campaign{} = campaign,
         %{type: "key_node", source_id: node_id} = candidate
       ) do
    case ShareCard.find_key_node(campaign, node_id) do
      node when is_map(node) ->
        ShareCard.node_reading_slides(campaign, node)
        |> Enum.drop(1)
        |> Enum.reject(&(Map.get(&1, "label") == "Learn more"))
        |> Enum.map(&persisted_slide/1)

      _ ->
        [fallback_slide(candidate)]
    end
  end

  defp candidate_slides(_campaign, %{type: type} = candidate)
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

  defp candidate_slides(_campaign, candidate), do: [fallback_slide(candidate)]

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
