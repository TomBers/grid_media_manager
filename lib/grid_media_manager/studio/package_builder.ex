defmodule GridMediaManager.Studio.PackageBuilder do
  @moduledoc """
  Builds a media package from an approved definition for either UI or autonomous callers.
  """

  alias GridMediaManager.Campaigns.Campaign
  alias GridMediaManager.Campaigns
  alias GridMediaManager.Studio.PackageDefinition
  alias GridMediaManager.Studio.VisualDirection
  alias GridMediaManager.Studio.Workflow

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
end
