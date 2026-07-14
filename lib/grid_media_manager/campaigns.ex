defmodule GridMediaManager.Campaigns do
  @moduledoc """
  Persistence and workflow functions for RationalGrid sharing campaigns.
  """

  import Ecto.Query

  alias GridMediaManager.Campaigns.Campaign
  alias GridMediaManager.Campaigns.MediaAsset
  alias GridMediaManager.Campaigns.PostDraft
  alias GridMediaManager.Promotion.CarouselVideo
  alias GridMediaManager.Promotion.ShareCard
  alias GridMediaManager.RationalGrid.Client
  alias GridMediaManager.RationalGrid.MediaPayload
  alias GridMediaManager.Repo
  alias GridMediaManager.Social.Buffer
  alias GridMediaManager.Social.Platforms
  alias GridMediaManager.Social.Templates

  def list_campaigns do
    Campaign
    |> order_by([c], desc: c.fetched_at, desc: c.inserted_at)
    |> Repo.all()
  end

  def get_campaign!(id), do: Repo.get!(Campaign, id)

  def get_campaign_by_slug(slug) when is_binary(slug), do: Repo.get_by(Campaign, slug: slug)

  def import_grid(source_input) when is_binary(source_input) do
    with {:ok, payload} <- Client.fetch_media(source_input) do
      import_payload(payload, source_input)
    end
  end

  def import_payload(payload, source_input) when is_map(payload) and is_binary(source_input) do
    attrs = MediaPayload.campaign_attrs(payload, source_input)
    asset_attrs = MediaPayload.asset_attrs(payload)

    Repo.transaction(fn ->
      campaign = upsert_campaign(attrs)
      assets = refresh_assets(campaign, asset_attrs)
      ensure_post_drafts(campaign, assets)
      campaign
    end)
  end

  def list_media_assets(%Campaign{id: campaign_id}) do
    MediaAsset
    |> where([a], a.campaign_id == ^campaign_id)
    |> order_by([a], asc: a.kind, asc: a.highlight_id, asc: a.id)
    |> Repo.all()
  end

  def list_post_drafts(%Campaign{id: campaign_id}, filters \\ []) do
    PostDraft
    |> where([d], d.campaign_id == ^campaign_id)
    |> filter_platform(filters[:platform])
    |> filter_media_asset(filters[:media_asset_id])
    |> order_by([d], asc: d.platform, asc: d.angle, asc: d.id)
    |> preload(:media_asset)
    |> Repo.all()
  end

  def get_media_asset!(id), do: Repo.get!(MediaAsset, parse_integer(id))

  def get_post_draft!(id), do: Repo.get!(PostDraft, parse_integer(id))

  def get_post_draft_with_asset!(id) do
    PostDraft
    |> Repo.get!(parse_integer(id))
    |> Repo.preload(:media_asset)
  end

  def update_post_draft(%PostDraft{} = post_draft, attrs) do
    post_draft
    |> PostDraft.changeset(attrs)
    |> Repo.update()
  end

  def set_pexels_background(%Campaign{} = campaign, photo) when is_map(photo) do
    background =
      photo
      |> Map.take([
        :id,
        :alt,
        :photographer,
        :photographer_url,
        :pexels_url,
        :avg_color,
        :landscape_url,
        :portrait_url,
        :original_url
      ])
      |> Map.new(fn {key, value} -> {Atom.to_string(key), value} end)

    raw_payload = campaign.raw_payload || %{}

    share_studio =
      raw_payload |> Map.get("share_studio", %{}) |> Map.put("pexels_background", background)

    raw_payload = Map.put(raw_payload, "share_studio", share_studio)

    campaign
    |> Campaign.changeset(%{raw_payload: raw_payload})
    |> Repo.update()
  end

  def clear_pexels_background(%Campaign{} = campaign) do
    raw_payload =
      update_in(campaign.raw_payload || %{}, ["share_studio"], fn
        studio when is_map(studio) -> Map.delete(studio, "pexels_background")
        _studio -> %{}
      end)

    campaign
    |> Campaign.changeset(%{raw_payload: raw_payload})
    |> Repo.update()
  end

  def pexels_background(%Campaign{} = campaign) do
    get_in(campaign.raw_payload || %{}, ["share_studio", "pexels_background"])
  end

  def mark_post_draft_copied(id) do
    id = parse_integer(id)
    post_draft = get_post_draft!(id)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    update_post_draft(post_draft, %{status: "copied", copied_at: now})
  end

  def approve_post_draft(id) do
    id
    |> get_post_draft!()
    |> update_post_draft(%{status: "approved"})
  end

  def schedule_post_draft(id, scheduled_for) do
    draft = get_post_draft_with_asset!(id)

    with true <- Buffer.configured?() || {:error, "Buffer is not configured."},
         channel_id when is_binary(channel_id) <- Buffer.channel_id(draft.platform),
         true <-
           Platforms.within_limit?(draft.body, draft.platform) ||
             {:error, "The draft is over the #{Platforms.label(draft.platform)} character limit."},
         {:ok, scheduled_for} <- parse_scheduled_for(scheduled_for),
         :lt <- DateTime.compare(DateTime.utc_now(), scheduled_for) do
      scheduled_draft = %{draft | scheduled_for: scheduled_for}

      case Buffer.schedule(scheduled_draft,
             channel_id: channel_id,
             media_url: buffer_media_url(draft.media_asset),
             mime_type: buffer_media_mime_type(draft.media_asset)
           ) do
        {:ok, post} ->
          update_post_draft(draft, %{
            status: "scheduled",
            scheduled_for: scheduled_for,
            external_post_id: post.id,
            error_message: nil
          })

        {:error, reason} ->
          mark_buffer_failure(draft, scheduled_for, reason)
      end
    else
      nil -> {:error, "No Buffer channel is configured for #{Platforms.label(draft.platform)}."}
      :eq -> {:error, "Choose a future schedule time."}
      :gt -> {:error, "Choose a future schedule time."}
      {:error, reason} -> {:error, reason}
    end
  end

  def generate_grid_asset(%Campaign{} = campaign, style \\ ShareCard.default_style()) do
    campaign = get_campaign!(campaign.id)

    campaign
    |> ShareCard.grid_asset_attr(style)
    |> then(&upsert_generated_asset_with_drafts(campaign, &1))
  end

  def generate_highlight_asset(
        %Campaign{} = campaign,
        highlight_id,
        style \\ ShareCard.default_style(),
        format \\ "landscape"
      ) do
    campaign = get_campaign!(campaign.id)

    with highlight when is_map(highlight) <- ShareCard.find_highlight(campaign, highlight_id),
         attrs when is_map(attrs) <-
           ShareCard.highlight_asset_attr(campaign, highlight, style, format) do
      upsert_generated_asset_with_drafts(campaign, attrs)
    else
      _ -> {:error, :not_found}
    end
  end

  def generate_highlight_short_video(
        %Campaign{} = campaign,
        highlight_id,
        style \\ ShareCard.default_style()
      ) do
    campaign = get_campaign!(campaign.id)
    style = ShareCard.normalize_style(style)

    with highlight when is_map(highlight) <- ShareCard.find_highlight(campaign, highlight_id),
         {:ok, _path} <-
           CarouselVideo.render_static(
             {:highlight, campaign.id, highlight_id, style, highlight},
             fn ->
               ShareCard.highlight_platform_image_png(campaign, highlight, style, "short")
             end
           ) do
      campaign
      |> ShareCard.highlight_short_video_asset_attr(highlight, style)
      |> then(&upsert_generated_asset_with_drafts(campaign, &1))
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def generate_key_node_asset(
        %Campaign{} = campaign,
        node_id,
        style \\ ShareCard.default_style(),
        format \\ "landscape"
      ) do
    campaign = get_campaign!(campaign.id)

    with node when is_map(node) <- ShareCard.find_key_node(campaign, node_id),
         attrs when is_map(attrs) <- ShareCard.key_node_asset_attr(campaign, node, style, format) do
      upsert_generated_asset_with_drafts(campaign, attrs)
    else
      _ -> {:error, :not_found}
    end
  end

  def generate_key_node_carousel(
        %Campaign{} = campaign,
        node_id,
        style \\ ShareCard.default_style()
      ) do
    campaign = get_campaign!(campaign.id)

    with node when is_map(node) <- ShareCard.find_key_node(campaign, node_id),
         attrs when is_list(attrs) <-
           ShareCard.key_node_carousel_asset_attrs(campaign, node, style) do
      Repo.transaction(fn ->
        assets = Enum.map(attrs, &upsert_media_asset(campaign, &1))
        [cover | _] = assets
        ensure_post_drafts(campaign, [cover])
        assets
      end)
    else
      _ -> {:error, :not_found}
    end
  end

  def generate_key_node_video(
        %Campaign{} = campaign,
        node_id,
        style \\ ShareCard.default_style()
      ) do
    campaign = get_campaign!(campaign.id)
    style = ShareCard.normalize_style(style)

    with node when is_map(node) <- ShareCard.find_key_node(campaign, node_id),
         {:ok, _video_path} <- CarouselVideo.render(campaign, node, style) do
      campaign
      |> CarouselVideo.asset_attr(node, style)
      |> then(&upsert_generated_asset_with_drafts(campaign, &1))
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def generate_question_asset(
        %Campaign{} = campaign,
        question_id,
        style \\ ShareCard.default_style(),
        format \\ "landscape"
      ) do
    campaign = get_campaign!(campaign.id)

    with question when is_map(question) <- ShareCard.find_question(campaign, question_id),
         attrs when is_map(attrs) <-
           ShareCard.question_asset_attr(campaign, question, style, format) do
      upsert_generated_asset_with_drafts(campaign, attrs)
    else
      _ -> {:error, :not_found}
    end
  end

  def generate_question_short_video(
        %Campaign{} = campaign,
        question_id,
        style \\ ShareCard.default_style()
      ) do
    campaign = get_campaign!(campaign.id)
    style = ShareCard.normalize_style(style)

    with question when is_map(question) <- ShareCard.find_question(campaign, question_id),
         {:ok, _path} <-
           CarouselVideo.render_static(
             {:question, campaign.id, question_id, style, question},
             fn -> ShareCard.question_platform_image_png(campaign, question, style, "short") end
           ) do
      campaign
      |> ShareCard.question_short_video_asset_attr(question, style)
      |> then(&upsert_generated_asset_with_drafts(campaign, &1))
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def delete_generated_media_asset(id) do
    asset = get_media_asset!(id)

    if generated_media_asset?(asset) do
      Repo.transaction(fn ->
        PostDraft
        |> where([d], d.media_asset_id == ^asset.id)
        |> Repo.delete_all()

        Repo.delete!(asset)
      end)
    else
      {:error, :not_generated}
    end
  end

  def origin_question(%Campaign{raw_payload: raw_payload}),
    do: MediaPayload.origin_question(raw_payload)

  def key_nodes(%Campaign{raw_payload: raw_payload}), do: MediaPayload.key_nodes(raw_payload)

  def first_answer_excerpt(%Campaign{raw_payload: raw_payload}),
    do: MediaPayload.first_answer_excerpt(raw_payload)

  def answer_questions(%Campaign{raw_payload: raw_payload}),
    do: MediaPayload.answer_questions(raw_payload)

  def follow_up_questions(%Campaign{raw_payload: raw_payload}),
    do: MediaPayload.follow_up_questions(raw_payload)

  def recommended_question(%Campaign{raw_payload: raw_payload}),
    do: MediaPayload.recommended_question(raw_payload)

  def user_questions(%Campaign{raw_payload: raw_payload}),
    do: MediaPayload.user_questions(raw_payload)

  def highlights(%Campaign{raw_payload: raw_payload}), do: MediaPayload.highlights(raw_payload)

  defp upsert_campaign(attrs) do
    case Repo.get_by(Campaign, slug: attrs.slug) do
      nil ->
        %Campaign{}
        |> Campaign.changeset(attrs)
        |> Repo.insert!()

      %Campaign{} = campaign ->
        campaign
        |> Campaign.changeset(attrs)
        |> Repo.update!()
    end
  end

  defp refresh_assets(%Campaign{} = campaign, asset_attrs) do
    incoming_urls = Enum.map(asset_attrs, & &1.url)

    MediaAsset
    |> where([a], a.campaign_id == ^campaign.id)
    |> where([a], is_nil(a.source_type))
    |> maybe_where_stale_asset(incoming_urls)
    |> Repo.delete_all()

    Enum.map(asset_attrs, &upsert_media_asset(campaign, &1))
  end

  defp generated_media_asset?(%MediaAsset{source_type: source_type})
       when is_binary(source_type) and source_type != "",
       do: true

  defp generated_media_asset?(%MediaAsset{url: url}) when is_binary(url) do
    String.starts_with?(url, "/campaigns/")
  end

  defp generated_media_asset?(_asset), do: false

  defp upsert_generated_asset_with_drafts(%Campaign{} = campaign, attrs) do
    Repo.transaction(fn ->
      asset = upsert_media_asset(campaign, attrs)
      ensure_post_drafts(campaign, [asset])
      asset
    end)
  end

  defp upsert_media_asset(%Campaign{} = campaign, attrs) do
    attrs = Map.put(attrs, :campaign_id, campaign.id)

    case Repo.get_by(MediaAsset, campaign_id: campaign.id, url: attrs.url) do
      nil ->
        %MediaAsset{}
        |> MediaAsset.changeset(attrs)
        |> Repo.insert!()

      %MediaAsset{} = media_asset ->
        media_asset
        |> MediaAsset.changeset(attrs)
        |> Repo.update!()
    end
  end

  defp maybe_where_stale_asset(query, []), do: query

  defp maybe_where_stale_asset(query, incoming_urls) do
    where(query, [a], a.url not in ^incoming_urls)
  end

  defp ensure_post_drafts(%Campaign{} = campaign, assets) do
    campaign = Repo.get!(Campaign, campaign.id)

    campaign
    |> Templates.draft_attrs(assets)
    |> Enum.each(fn attrs ->
      attrs = Map.put(attrs, :campaign_id, campaign.id)

      case find_existing_draft(attrs) do
        nil ->
          %PostDraft{}
          |> PostDraft.changeset(attrs)
          |> Repo.insert!()

        %PostDraft{} ->
          :ok
      end
    end)
  end

  defp find_existing_draft(attrs) do
    PostDraft
    |> where([d], d.campaign_id == ^attrs.campaign_id)
    |> where([d], d.platform == ^attrs.platform)
    |> where([d], d.angle == ^attrs.angle)
    |> where_media_asset_id(attrs.media_asset_id)
    |> Repo.one()
  end

  defp parse_scheduled_for(%DateTime{} = value),
    do: {:ok, DateTime.truncate(value, :second)}

  defp parse_scheduled_for(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} ->
        {:ok, DateTime.truncate(datetime, :second)}

      {:error, _reason} ->
        with {:ok, naive} <- NaiveDateTime.from_iso8601(value),
             {:ok, datetime} <- DateTime.from_naive(naive, "Etc/UTC") do
          {:ok, DateTime.truncate(datetime, :second)}
        else
          _error -> {:error, "Enter a valid UTC schedule time."}
        end
    end
  end

  defp parse_scheduled_for(_value), do: {:error, "Enter a valid UTC schedule time."}

  defp mark_buffer_failure(draft, scheduled_for, reason) do
    case parse_scheduled_for(scheduled_for) do
      {:ok, datetime} ->
        update_post_draft(draft, %{
          status: "failed",
          scheduled_for: datetime,
          error_message: to_string(reason)
        })

      {:error, _reason} ->
        :ok
    end

    {:error, to_string(reason)}
  end

  defp buffer_media_url(%MediaAsset{url: url}) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme} when scheme in ["http", "https"] -> url
      _uri -> URI.merge(GridMediaManagerWeb.Endpoint.url() <> "/", url) |> URI.to_string()
    end
  end

  defp buffer_media_url(_asset), do: nil

  defp buffer_media_mime_type(%MediaAsset{mime_type: mime_type}), do: mime_type
  defp buffer_media_mime_type(_asset), do: nil

  defp filter_platform(query, nil), do: query
  defp filter_platform(query, "all"), do: query
  defp filter_platform(query, platform), do: where(query, [d], d.platform == ^platform)

  defp filter_media_asset(query, nil), do: query
  defp filter_media_asset(query, "all"), do: query
  defp filter_media_asset(query, :all), do: query
  defp filter_media_asset(query, "campaign"), do: where(query, [d], is_nil(d.media_asset_id))

  defp filter_media_asset(query, media_asset_id) do
    media_asset_id = parse_integer(media_asset_id)
    where(query, [d], d.media_asset_id == ^media_asset_id)
  end

  defp where_media_asset_id(query, nil), do: where(query, [d], is_nil(d.media_asset_id))

  defp where_media_asset_id(query, media_asset_id),
    do: where(query, [d], d.media_asset_id == ^media_asset_id)

  defp parse_integer(value) when is_integer(value), do: value

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _ -> raise ArgumentError, "expected integer id, got: #{inspect(value)}"
    end
  end
end
