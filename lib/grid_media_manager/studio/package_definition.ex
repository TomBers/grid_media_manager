defmodule GridMediaManager.Studio.PackageDefinition do
  @moduledoc """
  Pure package-shape decisions shared by guided and autonomous publishing flows.
  """

  alias GridMediaManager.Campaigns.MediaAsset
  alias GridMediaManager.Social.Platforms

  @modes ~w(video bundle text long_form)

  def modes, do: @modes

  def format_for_mode("video"), do: "story_video"
  def format_for_mode("bundle"), do: "combined_carousel"
  def format_for_mode("long_form"), do: "long_form"
  def format_for_mode(_mode), do: "portrait"

  def mode_for_format("story_video"), do: "video"
  def mode_for_format("portrait"), do: "text"
  def mode_for_format("long_form"), do: "long_form"
  def mode_for_format(_format), do: "bundle"

  def mode_for_plan(nil), do: "video"
  def mode_for_plan(plan), do: mode_for_format(plan.recommended_format)

  def mode_for_assets(assets) when is_list(assets) do
    video? = Enum.any?(assets, &video_asset?/1)
    visual? = Enum.any?(assets, &(not video_asset?(&1)))

    cond do
      video? and visual? -> "bundle"
      video? -> "video"
      Enum.any?(assets, &(&1.kind == "long_form_post")) -> "long_form"
      true -> "text"
    end
  end

  def platforms_for_mode("text"), do: Platforms.text_ids()
  def platforms_for_mode("bundle"), do: Platforms.ids()
  def platforms_for_mode("long_form"), do: Platforms.long_form_ids()
  def platforms_for_mode("video"), do: Platforms.video_ids()
  def platforms_for_mode(_mode), do: []

  def platforms_for_assets(assets) when is_list(assets) do
    assets
    |> Enum.flat_map(fn asset ->
      cond do
        video_asset?(asset) ->
          Platforms.video_ids()

        is_list(asset.recommended_platforms) and asset.recommended_platforms != [] ->
          asset.recommended_platforms

        true ->
          Platforms.text_ids()
      end
    end)
    |> Enum.uniq()
    |> then(fn platforms -> Enum.filter(Platforms.ids(), &(&1 in platforms)) end)
  end

  def requested_platforms(params, available_platforms)

  def requested_platforms(%{"platform" => platforms}, available_platforms)
      when is_binary(platforms) do
    requested = platforms |> String.split(",", trim: true) |> MapSet.new()
    Enum.filter(available_platforms, &MapSet.member?(requested, &1))
  end

  def requested_platforms(_params, _available_platforms), do: []

  def video_asset?(%MediaAsset{mime_type: "video/mp4"}), do: true
  def video_asset?(_asset), do: false
end
