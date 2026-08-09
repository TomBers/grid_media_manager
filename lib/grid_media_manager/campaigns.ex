defmodule GridMediaManager.Campaigns do
  @moduledoc """
  Persistence and workflow functions for RationalGrid sharing campaigns.
  """

  import Ecto.Query

  alias GridMediaManager.Campaigns.Campaign
  alias GridMediaManager.Campaigns.MediaAsset
  alias GridMediaManager.Campaigns.PostDraft
  alias GridMediaManager.Promotion.ArtifactStore
  alias GridMediaManager.Promotion.AssetRenderer
  alias GridMediaManager.Promotion.CarouselVideo
  alias GridMediaManager.Promotion.ShareCard
  alias GridMediaManager.Promotion.SlideSequence
  alias GridMediaManager.RationalGrid.Client
  alias GridMediaManager.RationalGrid.MediaPayload
  alias GridMediaManager.Repo
  alias GridMediaManager.Social.Buffer
  alias GridMediaManager.Social.Platforms
  alias GridMediaManager.Social.Templates
  alias GridMediaManager.Storage.S3
  alias GridMediaManager.TextNormalizer

  def list_campaigns do
    Campaign
    |> order_by([c], desc: c.fetched_at, desc: c.inserted_at)
    |> Repo.all()
  end

  def get_campaign!(id), do: Repo.get!(Campaign, id)

  def get_campaign(id) when is_integer(id), do: Repo.get(Campaign, id)

  def get_campaign(id) when is_binary(id) do
    case Integer.parse(id) do
      {integer, ""} -> Repo.get(Campaign, integer)
      _ -> nil
    end
  end

  def get_campaign(_id), do: nil

  def get_campaign_by_slug(slug) when is_binary(slug), do: Repo.get_by(Campaign, slug: slug)

  def import_grid(source_input) when is_binary(source_input) do
    with {:ok, payload} <- Client.fetch_media(source_input) do
      import_payload(payload, source_input)
    end
  end

  def import_payload(payload, source_input) when is_map(payload) and is_binary(source_input) do
    payload = TextNormalizer.normalize(payload)
    source_input = TextNormalizer.normalize_binary(source_input)
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

  def list_all_post_drafts do
    PostDraft
    |> order_by([d], asc: d.inserted_at, asc: d.id)
    |> preload([:media_asset, :campaign])
    |> Repo.all()
  end

  def ensure_post_drafts_for_platforms(campaign, media_assets, platforms, opts \\ [])

  def ensure_post_drafts_for_platforms(%Campaign{} = campaign, media_assets, platforms, opts)
      when is_list(media_assets) and is_list(platforms) and is_list(opts) do
    campaign = Repo.get!(Campaign, campaign.id)
    platforms = Enum.filter(platforms, &(&1 in Platforms.ids()))
    refresh? = Keyword.get(opts, :refresh, false)

    campaign
    |> Templates.draft_attrs_for_platforms(media_assets, platforms)
    |> Enum.each(fn attrs ->
      attrs = Map.put(attrs, :campaign_id, campaign.id)

      case find_existing_draft(attrs) do
        nil ->
          %PostDraft{}
          |> PostDraft.changeset(attrs)
          |> Repo.insert!()

        %PostDraft{status: "draft"} = draft when refresh? ->
          draft
          |> PostDraft.changeset(%{body: attrs.body})
          |> Repo.update!()

        %PostDraft{} ->
          :ok
      end
    end)

    :ok
  end

  def get_media_asset!(id), do: Repo.get!(MediaAsset, parse_integer(id))

  def get_media_asset(id) do
    case positive_integer(id) do
      {:ok, parsed_id} -> Repo.get(MediaAsset, parsed_id)
      {:error, _reason} -> nil
    end
  end

  def update_media_asset_slide(%MediaAsset{} = asset, slide_index, attrs)
      when is_map(attrs) do
    with {:ok, slide_index} <- positive_integer(slide_index),
         slides when is_list(slides) <- Map.get(asset.metadata || %{}, "slides"),
         true <- slide_index <= length(slides) do
      slide = Enum.at(slides, slide_index - 1)

      updated_slide =
        slide
        |> put_slide_value("title", Map.get(attrs, "title"))
        |> put_slide_value("body", Map.get(attrs, "body"))
        |> Map.drop(["blocks", :blocks])

      metadata =
        (asset.metadata || %{})
        |> Map.put("slides", List.replace_at(slides, slide_index - 1, updated_slide))
        |> invalidate_rendered_media()

      asset
      |> MediaAsset.changeset(%{metadata: metadata})
      |> Repo.update()
    else
      _error -> {:error, :invalid_slide}
    end
  end

  def store_client_artifact(%MediaAsset{} = asset, slide_index, body) when is_binary(body) do
    with {:ok, slide_index} <- positive_integer(slide_index),
         true <- slide_index in media_asset_slide_indexes(asset),
         {:ok, artifact} <- ArtifactStore.put_png(asset, slide_index, body) do
      old_path = get_in(asset.metadata || %{}, ["artifacts", to_string(slide_index), "path"])

      metadata =
        (asset.metadata || %{})
        |> invalidate_published_media()
        |> Map.update("artifacts", %{to_string(slide_index) => artifact}, fn artifacts ->
          Map.put(artifacts || %{}, to_string(slide_index), artifact)
        end)

      result =
        asset
        |> MediaAsset.changeset(%{metadata: metadata})
        |> Repo.update()

      if match?({:ok, _asset}, result) and is_binary(old_path) and old_path != artifact["path"] do
        File.rm(old_path)
      end

      result
    else
      false -> {:error, :invalid_slide}
      {:error, reason} -> {:error, reason}
    end
  end

  def media_asset_slide_indexes(%MediaAsset{metadata: metadata}) when is_map(metadata) do
    slides = Map.get(metadata, "slides", [])
    slide_count = max(length(slides), Map.get(metadata, "slide_count", 0) || 0)

    cond do
      slide_count == 0 ->
        [1]

      is_list(Map.get(metadata, "selected_slide_indexes")) ->
        ShareCard.curated_carousel_selected_slide_indexes(
          slides,
          Map.get(metadata, "selected_slide_indexes")
        )

      true ->
        Enum.to_list(1..slide_count)
    end
  end

  def media_asset_slide_indexes(%MediaAsset{}), do: [1]

  def media_asset_artifact_url(%MediaAsset{id: id}, slide_index \\ 1),
    do: "/media-assets/#{id}/artifacts/#{slide_index}"

  def get_curated_carousel_asset(%Campaign{id: campaign_id}, token) when is_binary(token) do
    Repo.get_by(MediaAsset,
      campaign_id: campaign_id,
      kind: "curated_carousel",
      source_type: "curated_carousel",
      source_id: token
    ) || get_curated_carousel_video_asset(%Campaign{id: campaign_id}, token)
  end

  def get_curated_carousel_video_asset(%Campaign{id: campaign_id}, token)
      when is_binary(token) do
    Repo.get_by(MediaAsset,
      campaign_id: campaign_id,
      kind: "curated_carousel_video",
      source_type: "curated_carousel_video",
      source_id: token
    )
  end

  def get_key_node_video_asset(%Campaign{} = campaign, node_id) do
    get_key_node_video_asset(campaign, node_id, nil)
  end

  def get_key_node_video_asset(%Campaign{id: campaign_id}, node_id, style) do
    MediaAsset
    |> where([asset], asset.campaign_id == ^campaign_id)
    |> where([asset], asset.kind == "key_node_video")
    |> where([asset], asset.source_type == "key_node_video")
    |> where([asset], asset.source_id == ^to_string(node_id))
    |> maybe_filter_asset_style(style)
    |> order_by([asset], desc: asset.id)
    |> limit(1)
    |> Repo.one()
  end

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

  def update_post_draft_body(%PostDraft{} = post_draft, body) when is_binary(body) do
    if PostDraft.editable?(post_draft) do
      update_post_draft(post_draft, %{body: body})
    else
      {:error, :invalid_transition}
    end
  end

  def mark_post_draft_published(id, published_at \\ DateTime.utc_now()) do
    draft = get_post_draft_with_asset!(id)
    published_at = DateTime.truncate(published_at, :second)

    with {:ok, published_draft} <-
           update_post_draft(draft, %{status: "published", published_at: published_at}),
         :ok <- maybe_cleanup_published_media(published_draft.media_asset_id) do
      {:ok, published_draft}
    end
  end

  def cleanup_published_media(%MediaAsset{} = asset) do
    metadata = asset.metadata || %{}

    keys =
      (Map.get(metadata, "s3_keys") || List.wrap(Map.get(metadata, "s3_key")))
      |> Enum.filter(&is_binary/1)
      |> Enum.uniq()

    case Enum.reduce_while(keys, :ok, fn key, :ok ->
           case S3.delete_object(key) do
             :ok -> {:cont, :ok}
             {:error, reason} -> {:halt, {:error, reason}}
           end
         end) do
      :ok ->
        updated_metadata =
          Map.put(metadata, "s3_deleted_at", DateTime.utc_now() |> DateTime.to_iso8601())
          |> Map.put("s3_retained", false)

        asset
        |> MediaAsset.changeset(%{metadata: updated_metadata})
        |> Repo.update()

      {:error, reason} ->
        {:error, reason}
    end
  end

  def assign_generation_batch(assets) when is_list(assets) do
    batch_id = Ecto.UUID.generate()
    generated_at = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

    Repo.transaction(fn ->
      Enum.map(assets, fn asset ->
        metadata =
          Map.merge(asset.metadata || %{}, %{
            "generation_batch_id" => batch_id,
            "generated_at" => generated_at
          })

        asset
        |> MediaAsset.changeset(%{metadata: metadata})
        |> Repo.update!()
      end)
    end)
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

    studio_state =
      (campaign.studio_state || %{})
      |> Map.put("pexels_background", background)
      |> Map.put("title_card_mode", "pexels")

    campaign
    |> Campaign.changeset(%{studio_state: studio_state})
    |> Repo.update()
  end

  def clear_pexels_background(%Campaign{} = campaign) do
    studio_state =
      (campaign.studio_state || %{})
      |> Map.delete("pexels_background")
      |> Map.put("title_card_mode", "text")

    campaign
    |> Campaign.changeset(%{studio_state: studio_state})
    |> Repo.update()
  end

  def pexels_background(%Campaign{} = campaign) do
    Map.get(campaign.studio_state || %{}, "pexels_background") ||
      get_in(campaign.raw_payload || %{}, ["share_studio", "pexels_background"])
  end

  def title_card_mode(%Campaign{} = campaign) do
    Map.get(campaign.studio_state || %{}, "title_card_mode") ||
      get_in(campaign.raw_payload || %{}, ["share_studio", "title_card_mode"]) || "text"
  end

  def guided_studio_state(%Campaign{} = campaign) do
    Map.get(campaign.studio_state || %{}, "state") ||
      get_in(campaign.raw_payload || %{}, ["share_studio", "state"]) || %{}
  end

  def save_guided_studio_state(%Campaign{} = campaign, state) when is_map(state) do
    studio_state = Map.put(campaign.studio_state || %{}, "state", state)

    campaign
    |> Campaign.changeset(%{studio_state: studio_state})
    |> Repo.update()
  end

  def set_title_card_mode(%Campaign{} = campaign, mode) when mode in ["text", "pexels"] do
    studio_state = Map.put(campaign.studio_state || %{}, "title_card_mode", mode)

    campaign
    |> Campaign.changeset(%{studio_state: studio_state})
    |> Repo.update()
  end

  def mark_post_draft_copied(id) do
    id = parse_integer(id)
    post_draft = get_post_draft!(id)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    if PostDraft.editable?(post_draft) do
      update_post_draft(post_draft, %{status: "copied", copied_at: now})
    else
      {:error, :invalid_transition}
    end
  end

  def approve_post_draft(id) do
    post_draft = get_post_draft!(id)

    if PostDraft.approvable?(post_draft) do
      update_post_draft(post_draft, %{status: "approved"})
    else
      {:error, :invalid_transition}
    end
  end

  def approve_post_drafts(ids) when is_list(ids),
    do: approve_post_drafts_query(ids)

  def set_post_draft_suggestion(id, %DateTime{} = suggested_for) do
    id
    |> get_post_draft!()
    |> update_post_draft(%{suggested_for: DateTime.truncate(suggested_for, :second)})
  end

  def delete_post_drafts(ids) when is_list(ids) do
    ids = ids |> Enum.map(&parse_integer/1) |> Enum.reject(&is_nil/1)

    if ids == [] do
      {:ok, 0}
    else
      Repo.transaction(fn ->
        {count, _rows} =
          PostDraft
          |> where([d], d.id in ^ids)
          |> where([d], d.status in ["draft", "copied", "failed"])
          |> Repo.delete_all()

        count
      end)
    end
  end

  defp approve_post_drafts_query(ids) do
    ids = ids |> Enum.map(&parse_integer/1) |> Enum.reject(&is_nil/1)

    if ids == [] do
      {:ok, []}
    else
      Repo.transaction(fn ->
        PostDraft
        |> where([d], d.id in ^ids)
        |> where([d], d.status in ["draft", "copied"])
        |> Repo.all()
        |> Enum.map(fn draft ->
          draft
          |> PostDraft.changeset(%{status: "approved"})
          |> Repo.update!()
        end)
      end)
    end
  end

  def schedule_post_draft(id, scheduled_for) do
    draft = get_post_draft_with_asset!(id)
    campaign = get_campaign!(draft.campaign_id)

    with true <-
           PostDraft.schedulable?(draft) ||
             {:error, "Only draft, approved, or failed posts can be scheduled."},
         %{api_key: api_key, channel_id: channel_id} <-
           Buffer.account_for(draft.platform) ||
             {:error, "Buffer account is not configured for this channel."},
         true <-
           Platforms.within_limit?(draft.body, draft.platform) ||
             {:error, "The draft is over the #{Platforms.label(draft.platform)} character limit."},
         {:ok, media} <- buffer_media(campaign, draft.media_asset),
         {:ok, scheduled_for} <- parse_scheduled_for(scheduled_for),
         :lt <- DateTime.compare(DateTime.utc_now(), scheduled_for) do
      scheduled_draft = %{draft | scheduled_for: scheduled_for}

      case Buffer.schedule(scheduled_draft,
             api_key: api_key,
             channel_id: channel_id,
             media: media,
             title: buffer_post_title(campaign, draft.media_asset)
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

  def generate_curated_carousel(%Campaign{} = campaign, candidates, style)
      when is_list(candidates) and length(candidates) >= 1 do
    generate_curated_carousel(campaign, candidates, style, :with_drafts)
  end

  def generate_curated_carousel(%Campaign{}, _candidates, _style),
    do: {:error, :not_enough_candidates}

  def generate_curated_carousel_for_video(%Campaign{} = campaign, candidates, style)
      when is_list(candidates) and length(candidates) >= 1 do
    generate_curated_carousel(campaign, candidates, style, :without_drafts)
  end

  defp generate_curated_carousel(%Campaign{} = campaign, candidates, style, draft_mode) do
    campaign = get_campaign!(campaign.id)
    style = ShareCard.normalize_style(style)
    slides = SlideSequence.build(campaign, candidates)
    token = curated_carousel_token(candidates, slides, style)

    attrs = %{
      title: "#{campaign.title} · Story carousel",
      kind: "curated_carousel",
      url: ShareCard.curated_carousel_image_path(campaign, token, 1, style),
      mime_type: "image/png",
      text: campaign.title,
      node_id: nil,
      highlight_id: nil,
      recommended_platforms: Platforms.text_ids(),
      style: style,
      source_type: "curated_carousel",
      source_id: token,
      metadata: %{
        "format" => "curated_carousel",
        "width" => 1080,
        "height" => 1350,
        "slide_count" => length(slides),
        "slides" => slides,
        "selected_slide_indexes" => ShareCard.curated_carousel_selected_slide_indexes(slides)
      }
    }

    case draft_mode do
      :with_drafts -> upsert_generated_asset_with_drafts(campaign, attrs)
      :without_drafts -> Repo.transaction(fn -> upsert_media_asset(campaign, attrs) end)
    end
  end

  def update_curated_carousel_selection(%MediaAsset{kind: "curated_carousel"} = asset, selection)
      when is_list(selection) do
    slides = Map.get(asset.metadata || %{}, "slides", [])
    selected_slide_indexes = ShareCard.curated_carousel_selected_slide_indexes(slides, selection)

    metadata =
      (asset.metadata || %{})
      |> Map.put("selected_slide_indexes", selected_slide_indexes)
      |> Map.drop([
        "published_url",
        "published_urls",
        "s3_key",
        "s3_keys",
        "sha256",
        "sha256s",
        "s3_deleted_at",
        "s3_retained"
      ])

    asset
    |> MediaAsset.changeset(%{metadata: metadata})
    |> Repo.update()
  end

  def update_curated_carousel_selection(%MediaAsset{}, _selection),
    do: {:error, :invalid_carousel_selection}

  def generate_curated_carousel_video(
        %Campaign{} = campaign,
        %MediaAsset{kind: "curated_carousel"} = carousel
      ) do
    campaign = get_campaign!(campaign.id)
    slides = Map.get(carousel.metadata || %{}, "slides", [])

    campaign
    |> CarouselVideo.curated_asset_attr(carousel.source_id, slides, carousel.style,
      selected_slide_indexes: Map.get(carousel.metadata || %{}, "selected_slide_indexes")
    )
    |> then(&upsert_generated_asset_with_drafts(campaign, &1))
  end

  defp maybe_filter_asset_style(query, style) when is_binary(style),
    do: where(query, [asset], asset.style == ^ShareCard.normalize_style(style))

  defp maybe_filter_asset_style(query, _style), do: query

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

    with highlight when is_map(highlight) <- ShareCard.find_highlight(campaign, highlight_id) do
      attrs =
        campaign
        |> ShareCard.highlight_short_video_asset_attr(highlight, style)
        |> put_single_slide("highlight")

      attrs
      |> then(&upsert_generated_asset_with_drafts(campaign, &1))
    else
      nil -> {:error, :not_found}
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

  def generate_long_form_post(
        %Campaign{} = campaign,
        node_id,
        style \\ ShareCard.default_style()
      ) do
    campaign = get_campaign!(campaign.id)

    with node when is_map(node) <- ShareCard.find_key_node(campaign, node_id),
         attrs when is_map(attrs) <-
           ShareCard.key_node_long_form_asset_attr(campaign, node, style) do
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

    with node when is_map(node) <- ShareCard.find_key_node(campaign, node_id) do
      campaign
      |> CarouselVideo.asset_attr(node, style)
      |> then(&upsert_generated_asset_with_drafts(campaign, &1))
    else
      nil -> {:error, :not_found}
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

    with question when is_map(question) <- ShareCard.find_question(campaign, question_id) do
      attrs =
        campaign
        |> ShareCard.question_short_video_asset_attr(question, style)
        |> put_single_slide("quote")

      attrs
      |> then(&upsert_generated_asset_with_drafts(campaign, &1))
    else
      nil -> {:error, :not_found}
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

  defp curated_carousel_token(candidates, slides, style) do
    candidates
    |> Enum.map(&Map.take(&1, [:key, :type, :source_id, :title, :excerpt]))
    |> then(&{style, &1, slides})
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.url_encode64(padding: false)
    |> binary_part(0, 20)
  end

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
      ensure_post_drafts(campaign, [asset], refresh: true)
      asset
    end)
  end

  defp maybe_cleanup_published_media(media_asset_id) do
    drafts = Repo.all(from d in PostDraft, where: d.media_asset_id == ^media_asset_id)

    if drafts != [] and Enum.all?(drafts, &(&1.status == "published")) do
      asset = Repo.get!(MediaAsset, media_asset_id)

      case cleanup_published_media(asset) do
        {:ok, _asset} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      :ok
    end
  end

  defp upsert_media_asset(%Campaign{} = campaign, attrs) do
    attrs = Map.put(attrs, :campaign_id, campaign.id)

    case existing_media_asset(campaign, attrs) do
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

  defp existing_media_asset(%Campaign{} = campaign, %{source_type: source_type} = attrs)
       when is_binary(source_type) and source_type != "" do
    Repo.get_by(MediaAsset,
      campaign_id: campaign.id,
      kind: attrs.kind,
      source_type: source_type,
      source_id: attrs.source_id,
      style: attrs.style
    ) || Repo.get_by(MediaAsset, campaign_id: campaign.id, url: attrs.url)
  end

  defp existing_media_asset(%Campaign{} = campaign, attrs),
    do: Repo.get_by(MediaAsset, campaign_id: campaign.id, url: attrs.url)

  defp maybe_where_stale_asset(query, []), do: query

  defp maybe_where_stale_asset(query, incoming_urls) do
    where(query, [a], a.url not in ^incoming_urls)
  end

  defp ensure_post_drafts(%Campaign{} = campaign, assets, opts \\ []) do
    campaign = Repo.get!(Campaign, campaign.id)
    refresh? = Keyword.get(opts, :refresh, false)

    campaign
    |> Templates.draft_attrs(assets)
    |> Enum.each(fn attrs ->
      attrs = Map.put(attrs, :campaign_id, campaign.id)

      case find_existing_draft(attrs) do
        nil ->
          %PostDraft{}
          |> PostDraft.changeset(attrs)
          |> Repo.insert!()

        %PostDraft{status: "draft"} = draft when refresh? ->
          draft
          |> PostDraft.changeset(%{body: attrs.body})
          |> Repo.update!()

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
    value = normalize_datetime_local(value)

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

  defp normalize_datetime_local(value) do
    value = String.trim(value)

    if Regex.match?(~r/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/, value) do
      value <> ":00"
    else
      value
    end
  end

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

  def publish_media_asset(%Campaign{} = campaign, %MediaAsset{} = asset) do
    with {:ok, media} <- publish_media_assets(campaign, asset),
         %{url: url} <- List.first(media) do
      {:ok, url}
    else
      nil -> {:error, "No media was generated for this asset."}
      {:error, reason} -> {:error, reason}
    end
  end

  def publish_media_assets(%Campaign{} = campaign, %MediaAsset{} = asset) do
    case published_media(asset) do
      media when is_list(media) and media != [] ->
        validate_published_media(media)

      _media ->
        with true <- S3.configured?() || {:error, "S3 is not configured."},
             {:ok, bodies} <- AssetRenderer.render_all(campaign, asset),
             {:ok, published} <- upload_media_bodies(campaign, asset, bodies),
             {:ok, _asset} <- persist_published_media(asset, published) do
          {:ok, Enum.map(published, &Map.take(&1, [:url, :mime_type]))}
        else
          {:error, reason} when is_binary(reason) -> {:error, reason}
          {:error, reason} -> {:error, "Could not publish media to S3: #{inspect(reason)}"}
          false -> {:error, "S3 is not configured."}
        end
    end
  end

  defp buffer_media(_campaign, nil), do: {:ok, []}

  defp buffer_media(%Campaign{} = campaign, %MediaAsset{url: url} = asset)
       when is_binary(url) do
    case published_media(asset) do
      media when is_list(media) and media != [] ->
        validate_published_media(media)

      _media ->
        case URI.parse(url) do
          %URI{scheme: scheme} when scheme in ["http", "https"] ->
            with {:ok, public_url} <- validate_public_media_url(url) do
              {:ok, [%{url: public_url, mime_type: asset.mime_type}]}
            end

          _uri ->
            cond do
              S3.configured?() ->
                publish_media_assets(campaign, asset)

              String.starts_with?(url, "/client-assets/") ->
                {:error,
                 "Browser-rendered media requires S3 publishing before it can be scheduled."}

              true ->
                with {:ok, base_url} <- public_base_url(),
                     public_url <- URI.merge(base_url <> "/", url) |> URI.to_string(),
                     {:ok, public_url} <- validate_public_media_url(public_url) do
                  {:ok, [%{url: public_url, mime_type: asset.mime_type}]}
                end
            end
        end
    end
  end

  defp published_media(%MediaAsset{metadata: metadata, mime_type: mime_type})
       when is_map(metadata) do
    case Map.get(metadata, "published_urls") do
      urls when is_list(urls) and urls != [] ->
        Enum.map(urls, &%{url: &1, mime_type: mime_type})

      _urls ->
        case Map.get(metadata, "published_url") do
          url when is_binary(url) -> [%{url: url, mime_type: mime_type}]
          _url -> []
        end
    end
  end

  defp published_media(_asset), do: []

  defp validate_published_media(media) do
    Enum.reduce_while(media, {:ok, []}, fn item, {:ok, valid_media} ->
      case validate_public_media_url(item.url) do
        {:ok, url} -> {:cont, {:ok, valid_media ++ [%{item | url: url}]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp upload_media_bodies(campaign, asset, bodies) do
    bodies
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, []}, fn {body, index}, {:ok, uploaded} ->
      digest = :crypto.hash(:sha256, body) |> Base.encode16(case: :lower)
      key = s3_object_key(campaign, asset, digest, index)
      mime_type = asset.mime_type || "application/octet-stream"

      case S3.put_object(key, body, mime_type) do
        {:ok, url} ->
          item = %{url: url, key: key, digest: digest, mime_type: mime_type}
          {:cont, {:ok, uploaded ++ [item]}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp persist_published_media(asset, published) do
    urls = Enum.map(published, & &1.url)
    keys = Enum.map(published, & &1.key)
    digests = Enum.map(published, & &1.digest)

    metadata =
      Map.merge(asset.metadata || %{}, %{
        "published_url" => List.first(urls),
        "published_urls" => urls,
        "s3_key" => List.first(keys),
        "s3_keys" => keys,
        "sha256" => List.first(digests),
        "sha256s" => digests
      })

    asset
    |> MediaAsset.changeset(%{metadata: metadata})
    |> Repo.update()
  end

  defp s3_object_key(campaign, asset, digest, index) do
    campaign_slug = sanitize_s3_segment(campaign.slug || "campaign-#{campaign.id}")
    extension = if asset.mime_type == "video/mp4", do: "mp4", else: "png"

    "campaigns/#{campaign_slug}/assets/#{asset.id}/#{index}-#{String.slice(digest, 0, 24)}.#{extension}"
  end

  defp sanitize_s3_segment(value) do
    value
    |> to_string()
    |> String.replace(~r/[^A-Za-z0-9._-]+/, "-")
    |> String.trim("-")
  end

  defp public_base_url do
    configured_url =
      System.get_env("PUBLIC_BASE_URL") ||
        Application.get_env(:grid_media_manager, :public_base_url) ||
        GridMediaManagerWeb.Endpoint.url()

    case configured_url do
      value when is_binary(value) and value != "" -> {:ok, String.trim_trailing(value, "/")}
      _value -> {:error, public_media_error()}
    end
  end

  defp validate_public_media_url(url) do
    case URI.parse(url) do
      %URI{scheme: "https", host: host} when is_binary(host) ->
        if private_host?(host), do: {:error, public_media_error()}, else: {:ok, url}

      _uri ->
        {:error, public_media_error()}
    end
  end

  defp private_host?(host) do
    host = String.downcase(host)

    host in ["localhost", "0.0.0.0", "127.0.0.1", "::1"] or
      String.ends_with?(host, ".localhost") or
      String.starts_with?(host, "127.") or
      String.starts_with?(host, "10.") or
      String.starts_with?(host, "192.168.") or
      private_172_host?(host)
  end

  defp private_172_host?(host) do
    case host |> String.split(".") |> Enum.take(2) do
      ["172", second] ->
        case Integer.parse(second) do
          {value, ""} -> value in 16..31
          _other -> false
        end

      _parts ->
        false
    end
  end

  defp public_media_error do
    "Generated media is only available on the local server. Set PUBLIC_BASE_URL to a public HTTPS URL, such as an ngrok or Cloudflare Tunnel URL, before scheduling an image through Buffer."
  end

  defp buffer_post_title(_campaign, %MediaAsset{title: title})
       when is_binary(title) and title != "",
       do: title

  defp buffer_post_title(%Campaign{title: title}, _asset), do: title

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

  defp put_slide_value(slide, _key, nil), do: slide

  defp put_slide_value(slide, key, value) when is_map(slide) and is_binary(value) do
    atom_key = if(key == "title", do: :title, else: :body)

    cond do
      Map.has_key?(slide, key) -> Map.put(slide, key, value)
      Map.has_key?(slide, atom_key) -> Map.put(slide, atom_key, value)
      true -> Map.put(slide, key, value)
    end
  end

  defp invalidate_rendered_media(metadata) do
    metadata
    |> Map.drop(["artifacts", "browser_frame_paths"])
    |> invalidate_published_media()
  end

  defp put_single_slide(attrs, kind) when is_map(attrs) do
    slide = %{
      "kind" => kind,
      "label" => "",
      "title" => Map.get(attrs, :text) || Map.get(attrs, :title) || "",
      "body" => ""
    }

    metadata =
      (Map.get(attrs, :metadata) || %{})
      |> Map.put("slides", [slide])
      |> Map.put("slide_count", 1)

    Map.put(attrs, :metadata, metadata)
  end

  defp invalidate_published_media(metadata) do
    Map.drop(metadata, [
      "published_url",
      "published_urls",
      "s3_key",
      "s3_keys",
      "sha256",
      "sha256s",
      "s3_deleted_at",
      "s3_retained"
    ])
  end

  defp parse_integer(value) when is_integer(value), do: value

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _ -> raise ArgumentError, "expected integer id, got: #{inspect(value)}"
    end
  end

  defp positive_integer(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp positive_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} when integer > 0 -> {:ok, integer}
      _result -> {:error, :invalid_slide}
    end
  end

  defp positive_integer(_value), do: {:error, :invalid_slide}
end
