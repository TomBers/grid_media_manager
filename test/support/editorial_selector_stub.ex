defmodule GridMediaManager.EditorialSelectorStub do
  @behaviour GridMediaManager.Automation.Selector

  @impl true
  def select_topics(count, _theme, candidates) do
    topics =
      candidates
      |> Enum.take(count)
      |> Enum.map(fn source ->
        %{
          "topic" => source.title,
          "source_slug" => source.slug,
          "confidence" => 0.9,
          "rationale" => "A strong source for this publishing run."
        }
      end)

    {:ok, %{"topics" => topics}}
  end

  @impl true
  def select_grid(_topic, [source | _sources]) do
    {:ok,
     %{
       "source_slug" => source.slug,
       "confidence" => 0.91,
       "rationale" => "This is the closest grounded source."
     }}
  end

  @impl true
  def select_story(topic, _campaign, candidates) do
    selected_keys = candidates |> Enum.take(3) |> Enum.map(& &1.key)

    visual_rationale =
      if topic == "NUL metadata",
        do: "A reflective palette supports\0 the subject.",
        else: "A reflective analytical palette supports the subject."

    {:ok,
     %{
       "selected_keys" => selected_keys,
       "hook" => "A grounded question worth following",
       "text_visual_key" => List.first(selected_keys),
       "text_visual_role" => "question",
       "rationale" => "The selected moments form a question, explanation, and implication.",
       "recommended_format" => "combined_carousel",
       "format_rationale" => "The mixed material works as both video and an image sequence.",
       "visual_style" => "deep_ocean",
       "visual_rationale" => visual_rationale,
       "cover_mode" => "photo",
       "cover_search_query" => "lone figure ocean horizon blue dusk negative space",
       "cover_brief" => "A contemplative portrait composition with room for a short title.",
       "confidence" => 0.88
     }}
  end

  def revise_story(topic, campaign, candidates, _current_plan, _review) do
    {:ok, choice} = select_story(topic, campaign, candidates)

    {:ok,
     choice
     |> Map.put("hook", "A sharper Editor-guided opening")
     |> Map.put(
       "rationale",
       "The revised sequence foregrounds the most shareable implication."
     )}
  end

  @impl true
  def select_cover(_topic, _hook, _cover_brief, [photo | _photos]) do
    {:ok,
     %{
       "photo_id" => to_string(photo.id),
       "rationale" => "The strongest portrait composition for the story."
     }}
  end
end
