defmodule GridMediaManager.Studio.PackageBuilder do
  @moduledoc """
  Builds a media package from an approved definition for either UI or autonomous callers.
  """

  alias GridMediaManager.Campaigns.Campaign
  alias GridMediaManager.Campaigns
  alias GridMediaManager.Studio.PackageDefinition
  alias GridMediaManager.Studio.VisualDirection
  alias GridMediaManager.Studio.Workflow
  @complete_package_formats ~w(long_form x_post story_video)

  def generate_complete_plan(%Campaign{} = campaign, plan, all_candidates, opts \\ [])
      when is_list(all_candidates) do
    @complete_package_formats
    |> Enum.map(&generate_plan(campaign, plan, all_candidates, Keyword.put(opts, :format, &1)))
    |> Enum.reduce(%{assets: [], errors: []}, &merge_results/2)
  end

  def generate_plan(%Campaign{} = campaign, plan, all_candidates, opts \\ [])
      when is_list(all_candidates) do
    mode = PackageDefinition.mode_for_plan(plan)
    style = VisualDirection.style_for_plan(plan, nil)

    cover =
      VisualDirection.cover_for_plan(
        plan,
        Campaigns.pexels_background(campaign),
        Campaigns.title_card_mode(campaign)
      )

    generate(campaign, all_candidates, plan.selected_keys,
      content_mode: mode,
      style: style,
      format: Keyword.get(opts, :format, PackageDefinition.format_for_mode(mode)),
      cover: cover,
      text_visual_key: Map.get(plan.selection_details || %{}, "text_visual_key")
    )
  end

  def generate(%Campaign{} = campaign, all_candidates, selected_order, opts \\ [])
      when is_list(all_candidates) and is_list(selected_order) do
    mode = Keyword.fetch!(opts, :content_mode)
    style = Keyword.fetch!(opts, :style)
    cover = Keyword.get(opts, :cover, %{"mode" => "text"})

    format = Keyword.get(opts, :format, PackageDefinition.format_for_mode(mode))

    candidates =
      all_candidates
      |> Workflow.selected_candidates(selected_order)
      |> candidates_for_output(
        mode,
        format,
        all_candidates,
        Keyword.get(opts, :text_visual_key)
      )

    case VisualDirection.apply(campaign, cover) do
      {:ok, campaign} ->
        Workflow.generate(campaign, candidates, style: style, format: format)

      {:error, reason} ->
        %{
          assets: [],
          errors: [%{candidate: List.first(candidates), reason: {:visual_direction, reason}}]
        }
    end
  end

  defp candidates_for_output(candidates, _mode, format, _all_candidates, text_visual_key)
       when format in ["portrait", "x_post"] and is_binary(text_visual_key) do
    case Enum.find(candidates, &(&1.key == text_visual_key)) do
      nil -> candidates
      candidate -> [candidate]
    end
  end

  defp candidates_for_output(candidates, "text", "portrait", all_candidates, _text_visual_key) do
    quote_candidates = Enum.filter(candidates, &quote_candidate?/1)

    cond do
      quote_candidates != [] ->
        quote_candidates

      Enum.any?(all_candidates, &quote_candidate?/1) ->
        Enum.filter(all_candidates, &quote_candidate?/1) |> Enum.take(1)

      true ->
        candidates
    end
  end

  defp candidates_for_output(candidates, _mode, _format, _all_candidates, _text_visual_key),
    do: candidates

  defp quote_candidate?(%{type: type}) when type in ["question", "highlight", "key_node"],
    do: true

  defp quote_candidate?(_candidate), do: false

  defp merge_results(result, merged) do
    %{
      assets: Enum.uniq_by(merged.assets ++ result.assets, & &1.id),
      errors: merged.errors ++ result.errors
    }
  end
end
