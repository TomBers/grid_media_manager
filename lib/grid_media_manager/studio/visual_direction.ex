defmodule GridMediaManager.Studio.VisualDirection do
  @moduledoc """
  Resolves and applies editable visual direction without coupling editorial computation to UI.
  """

  alias GridMediaManager.Campaigns
  alias GridMediaManager.Campaigns.Campaign
  alias GridMediaManager.Pexels.Client, as: Pexels
  alias GridMediaManager.Promotion.ShareCard

  @photo_keys ~w(id alt photographer photographer_url pexels_url avg_color landscape_url portrait_url original_url)

  def style_for_plan(nil, saved_style), do: ShareCard.normalize_style(saved_style)

  def style_for_plan(plan, saved_style) do
    plan
    |> visual_details()
    |> Map.get("visual_style", saved_style)
    |> ShareCard.normalize_style()
  end

  def cover_for_plan(nil, fallback_background, fallback_mode) do
    cover(fallback_mode, fallback_background)
  end

  def cover_for_plan(plan, fallback_background, fallback_mode) do
    case get_in(visual_details(plan), ["cover"]) do
      %{"mode" => "photo", "photo" => photo} when is_map(photo) -> cover("pexels", photo)
      %{"mode" => "text"} -> cover("text", nil)
      _cover -> cover(fallback_mode, fallback_background)
    end
  end

  def cover(mode, photo) do
    %{
      "mode" => if(mode in ["photo", "pexels"] and is_map(photo), do: "photo", else: "text"),
      "photo" => if(is_map(photo), do: stringify_photo(photo), else: nil)
    }
  end

  def cover_url(%{"mode" => "photo", "photo" => photo}) when is_map(photo) do
    photo["portrait_url"] || photo["original_url"] || photo["landscape_url"]
  end

  def cover_url(_cover), do: nil

  def configured?, do: Pexels.configured?()
  def search(query, opts \\ []), do: Pexels.search(query, opts)

  def resolve_cover(_selector, _topic, %{cover_mode: "text"}, _search?) do
    %{"mode" => "text", "status" => "selected"}
  end

  def resolve_cover(_selector, _topic, _story, false) do
    %{"mode" => "photo", "status" => "not_searched"}
  end

  def resolve_cover(selector, topic, story, true) do
    case search(story.cover_search_query, orientation: "portrait", per_page: 8) do
      {:ok, [first_photo | _photos] = photos} ->
        {photo, rationale, selection_method} =
          choose_photo(selector, topic, story, photos, first_photo)

        %{
          "mode" => "photo",
          "status" => "selected",
          "selection_method" => selection_method,
          "rationale" => rationale,
          "photo" => stringify_photo(photo)
        }

      {:ok, []} ->
        %{"mode" => "photo", "status" => "no_results"}

      {:error, reason} ->
        %{"mode" => "photo", "status" => "unavailable", "error" => error_message(reason)}
    end
  end

  def apply(%Campaign{} = campaign, %{"mode" => "photo", "photo" => photo})
      when is_map(photo) do
    Campaigns.set_pexels_background(campaign, atomize_photo(photo))
  end

  def apply(%Campaign{} = campaign, _cover), do: Campaigns.set_title_card_mode(campaign, "text")

  def apply_photo(%Campaign{} = campaign, photo) when is_map(photo) do
    Campaigns.set_pexels_background(campaign, atomize_photo(photo))
  end

  def clear(%Campaign{} = campaign), do: Campaigns.clear_pexels_background(campaign)

  def set_mode(%Campaign{} = campaign, mode) when mode in ["text", "pexels"] do
    Campaigns.set_title_card_mode(campaign, mode)
  end

  defp choose_photo(selector, topic, story, photos, fallback) do
    case selector.select_cover(topic, story.hook, story.cover_brief, photos) do
      {:ok, %{"photo_id" => photo_id, "rationale" => rationale}}
      when is_binary(rationale) ->
        case Enum.find(photos, &(to_string(&1.id) == to_string(photo_id))) do
          nil -> {fallback, "Top-ranked Pexels result for the visual brief.", "pexels_ranked"}
          photo -> {photo, String.trim(rationale), "editorial_model"}
        end

      _result ->
        {fallback, "Top-ranked Pexels result for the visual brief.", "pexels_ranked"}
    end
  end

  defp visual_details(%{selection_details: details}) when is_map(details), do: details
  defp visual_details(_plan), do: %{}

  defp stringify_photo(photo) do
    Map.new(@photo_keys, fn key ->
      {key, Map.get(photo, key) || Map.get(photo, known_atom(key))}
    end)
  end

  defp atomize_photo(photo) do
    Map.new(@photo_keys, fn key ->
      {known_atom(key), Map.get(photo, key) || Map.get(photo, known_atom(key))}
    end)
  end

  defp known_atom("id"), do: :id
  defp known_atom("alt"), do: :alt
  defp known_atom("photographer"), do: :photographer
  defp known_atom("photographer_url"), do: :photographer_url
  defp known_atom("pexels_url"), do: :pexels_url
  defp known_atom("avg_color"), do: :avg_color
  defp known_atom("landscape_url"), do: :landscape_url
  defp known_atom("portrait_url"), do: :portrait_url
  defp known_atom("original_url"), do: :original_url

  defp error_message(:not_configured), do: "Pexels is not configured."
  defp error_message(:invalid_query), do: "The generated Pexels query was invalid."
  defp error_message(_reason), do: "Pexels search was unavailable."
end
