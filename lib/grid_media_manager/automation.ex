defmodule GridMediaManager.Automation do
  @moduledoc """
  One-click content automation for a selected promotion grid.
  """

  alias GridMediaManager.Campaigns
  alias GridMediaManager.Social.Buffer
  alias GridMediaManager.Social.Platforms
  alias GridMediaManager.Studio.Workflow

  @video_platforms Platforms.video_ids()
  @text_platforms Platforms.text_ids()

  @doc """
  Generates a package for review without contacting Buffer.

  This is the default entry point for the home-page automation action. It imports
  the grid, creates both media variants and their drafts, and leaves publication
  to the explicit review action in the studio.
  """
  def preview_grid(source, opts \\ []) when is_binary(source) do
    scheduled_for = Keyword.get(opts, :scheduled_for, next_morning())
    builder = Keyword.get(opts, :builder, &build_package/1)

    with {:ok, package} <- builder.(source) do
      {:ok,
       package
       |> Map.put(:mode, :preview)
       |> Map.put(:scheduled_for, scheduled_for)
       |> Map.put(:scheduled, [])
       |> Map.put(:failed, [])}
    end
  end

  @doc """
  Publishes a generated package by scheduling its drafts through Buffer.

  Callers should prefer `preview_grid/2` and only invoke this function after the
  package has been reviewed by a person.
  """
  def publish_grid(source, opts \\ []) when is_binary(source) do
    scheduled_for = Keyword.get(opts, :scheduled_for, next_morning())

    with :ok <- ensure_buffer_accounts(),
         {:ok, package} <- build_package(source) do
      asset_ids = MapSet.new(package.assets, & &1.id)

      drafts =
        package.campaign
        |> Campaigns.list_post_drafts()
        |> Enum.filter(&(&1.media_asset_id in asset_ids))
        |> Enum.filter(&(&1.platform in (@video_platforms ++ @text_platforms)))

      {scheduled, failed} = schedule_drafts(drafts, scheduled_for)

      {:ok,
       Map.merge(package, %{
         mode: :live,
         scheduled_for: scheduled_for,
         scheduled: scheduled,
         failed: failed
       })}
    end
  end

  @doc """
  Compatibility alias for callers that explicitly request live scheduling.

  The web UI uses `preview_grid/2`; this function is intentionally named after
  the side effect it performs for non-UI callers.
  """
  def schedule_grid(source, opts \\ []) when is_binary(source), do: publish_grid(source, opts)

  defp build_package(source) do
    with {:ok, campaign} <- Campaigns.import_grid(source),
         {:ok, candidates} <- selected_candidates(campaign),
         {:ok, video_assets} <- generate_video(campaign, candidates),
         {:ok, text_assets} <- generate_text(campaign, candidates) do
      Campaigns.ensure_post_drafts_for_platforms(campaign, video_assets, @video_platforms)
      Campaigns.ensure_post_drafts_for_platforms(campaign, text_assets, @text_platforms)

      {:ok,
       %{
         campaign: campaign,
         grid: %{source: source, title: campaign.title},
         candidates: candidates,
         assets: video_assets ++ text_assets
       }}
    end
  end

  defp ensure_buffer_accounts do
    if Enum.all?(@video_platforms ++ @text_platforms, &(Buffer.account_for(&1) != nil)) do
      :ok
    else
      {:error, :buffer_accounts_not_configured}
    end
  end

  defp selected_candidates(campaign) do
    candidates = Workflow.candidates(campaign)
    selected_keys = Workflow.default_selection(candidates)

    selected = Workflow.selected_candidates(candidates, selected_keys)

    additional =
      Enum.filter(candidates, fn candidate ->
        candidate.type in ["question", "highlight", "key_node"] and
          candidate.key not in Enum.map(selected, & &1.key)
      end)

    selected = (selected ++ additional) |> Enum.uniq_by(& &1.key) |> Enum.take(2)

    if selected == [], do: {:error, :no_shareable_moments}, else: {:ok, selected}
  end

  defp generate_video(campaign, candidates) do
    case Workflow.generate(campaign, candidates, format: "story_video") do
      %{assets: assets} when assets != [] -> {:ok, assets}
      %{errors: errors} -> {:error, {:video_generation_failed, errors}}
    end
  end

  defp generate_text(campaign, candidates) do
    case Workflow.generate(campaign, candidates, format: "portrait") do
      %{assets: assets} when assets != [] -> {:ok, assets}
      %{errors: errors} -> {:error, {:text_generation_failed, errors}}
    end
  end

  defp schedule_drafts(drafts, scheduled_for) do
    drafts
    |> Enum.map(fn draft -> {draft, Campaigns.schedule_post_draft(draft.id, scheduled_for)} end)
    |> Enum.split_with(fn {_draft, result} -> match?({:ok, _}, result) end)
    |> then(fn {scheduled, failed} ->
      {Enum.map(scheduled, &elem(&1, 0)), Enum.map(failed, &elem(&1, 0))}
    end)
  end

  defp next_morning do
    tomorrow = Date.add(Date.utc_today(), 1)
    {:ok, scheduled_for} = DateTime.new(tomorrow, ~T[09:00:00], "Etc/UTC")
    scheduled_for
  end
end
