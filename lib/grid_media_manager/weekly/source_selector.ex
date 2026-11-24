defmodule GridMediaManager.Weekly.SourceSelector do
  @moduledoc false
  # Source selection is fixed by the exploration. Spend the model call on the
  # actual platform copy instead of asking another model to rediscover that source.
  def select_story(_topic, campaign, candidates) do
    nodes = Enum.filter(candidates, &(&1.type == "key_node"))
    origin = Enum.find(nodes, &(&1.node_class == "origin"))

    answer =
      Enum.find(nodes, &(&1.node_class == "synthesis")) ||
        Enum.find(nodes, &(&1.node_class == "answer"))

    selected = Enum.reject([origin, answer], &is_nil/1) |> Enum.uniq_by(& &1.key)
    selected = if length(selected) < 2, do: Enum.take(candidates, 2), else: selected

    {:ok,
     %{
       "selected_keys" => Enum.map(selected, & &1.key),
       "hook" => campaign.title,
       "video_script" => nil,
       "text_visual_key" => List.last(selected).key,
       "text_visual_role" => "evidence",
       "rationale" => "Use the originating question and a complete generated argument.",
       "recommended_format" => "long_form",
       "format_rationale" => "Prepare one complete package for all six destinations.",
       "visual_style" => "newsprint",
       "visual_rationale" => "Clear typography with an editorial photograph.",
       "cover_mode" => "photo",
       "cover_search_query" => campaign.title,
       "cover_brief" => "An editorial photograph that supports the specific tension.",
       "confidence" => 0.8
     }}
  end
end
