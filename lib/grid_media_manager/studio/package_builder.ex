defmodule GridMediaManager.Studio.PackageBuilder do
  @moduledoc """
  Builds a media package from an approved definition for either UI or autonomous callers.
  """

  alias GridMediaManager.Campaigns.Campaign
  alias GridMediaManager.Campaigns
  alias GridMediaManager.Studio.PackageDefinition
  alias GridMediaManager.Studio.VisualDirection
  alias GridMediaManager.Studio.Workflow
  alias GridMediaManager.Social.Platforms

  def generate_complete_plan(%Campaign{} = campaign, plan, all_candidates, opts \\ [])
      when is_list(all_candidates) do
    primary = generate_plan(campaign, plan, all_candidates, opts)
    available_platforms = PackageDefinition.platforms_for_assets(primary.assets)

    companion_formats =
      []
      |> maybe_add_companion(
        not Enum.all?(Platforms.text_ids(), &(&1 in available_platforms)),
        "portrait"
      )
      |> maybe_add_companion(
        not Enum.all?(Platforms.video_ids(), &(&1 in available_platforms)),
        "story_video"
      )

    companion_formats
    |> Enum.map(&generate_plan(campaign, plan, all_candidates, Keyword.put(opts, :format, &1)))
    |> Enum.reduce(primary, &merge_results/2)
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

    selected_keys = prioritize_text_visual(plan.selected_keys, plan.selection_details)

    generate(campaign, all_candidates, selected_keys,
      content_mode: mode,
      style: style,
      format: Keyword.get(opts, :format, PackageDefinition.format_for_mode(mode)),
      cover: cover
    )
  end

  def generate(%Campaign{} = campaign, all_candidates, selected_order, opts \\ [])
      when is_list(all_candidates) and is_list(selected_order) do
    mode = Keyword.fetch!(opts, :content_mode)
    style = Keyword.fetch!(opts, :style)
    cover = Keyword.get(opts, :cover, %{"mode" => "text"})

    candidates =
      all_candidates
      |> Workflow.selected_candidates(selected_order)
      |> candidates_for_mode(mode, all_candidates)

    format = Keyword.get(opts, :format, PackageDefinition.format_for_mode(mode))

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

  defp candidates_for_mode(candidates, "text", all_candidates) do
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

  defp candidates_for_mode(candidates, _mode, _all_candidates), do: candidates

  defp quote_candidate?(%{type: type}) when type in ["question", "highlight", "key_node"],
    do: true

  defp quote_candidate?(_candidate), do: false

  defp prioritize_text_visual(selected_keys, details)
       when is_list(selected_keys) and is_map(details) do
    case Map.get(details, "text_visual_key") do
      key when is_binary(key) ->
        if key in selected_keys, do: [key | List.delete(selected_keys, key)], else: selected_keys

      _key ->
        selected_keys
    end
  end

  defp prioritize_text_visual(selected_keys, _details), do: selected_keys

  defp maybe_add_companion(formats, true, format), do: formats ++ [format]
  defp maybe_add_companion(formats, false, _format), do: formats

  defp merge_results(result, merged) do
    %{
      assets: Enum.uniq_by(merged.assets ++ result.assets, & &1.id),
      errors: merged.errors ++ result.errors
    }
  end
end
