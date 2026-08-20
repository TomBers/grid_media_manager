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
  def select_story(_topic, _campaign, candidates) do
    selected_keys = candidates |> Enum.take(3) |> Enum.map(& &1.key)

    {:ok,
     %{
       "selected_keys" => selected_keys,
       "hook" => "A grounded question worth following",
       "rationale" => "The selected moments form a question, explanation, and implication.",
       "recommended_format" => "combined_carousel",
       "format_rationale" => "The mixed material works as both video and an image sequence.",
       "confidence" => 0.88
     }}
  end
end
