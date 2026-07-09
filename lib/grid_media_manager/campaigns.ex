defmodule GridMediaManager.Campaigns do
  @moduledoc """
  Persistence and workflow functions for RationalGrid sharing campaigns.
  """

  import Ecto.Query

  alias GridMediaManager.Campaigns.Campaign
  alias GridMediaManager.Campaigns.MediaAsset
  alias GridMediaManager.Campaigns.PostDraft
  alias GridMediaManager.Promotion.ShareCard
  alias GridMediaManager.RationalGrid.Client
  alias GridMediaManager.RationalGrid.MediaPayload
  alias GridMediaManager.Repo
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

  def mark_post_draft_copied(id) do
    id = parse_integer(id)
    post_draft = get_post_draft!(id)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    update_post_draft(post_draft, %{status: "copied", copied_at: now})
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
        style \\ ShareCard.default_style()
      ) do
    campaign = get_campaign!(campaign.id)

    with highlight when is_map(highlight) <- ShareCard.find_highlight(campaign, highlight_id),
         attrs when is_map(attrs) <- ShareCard.highlight_asset_attr(campaign, highlight, style) do
      upsert_generated_asset_with_drafts(campaign, attrs)
    else
      _ -> {:error, :not_found}
    end
  end

  def generate_key_node_asset(%Campaign{} = campaign, node_id, style \\ ShareCard.default_style()) do
    campaign = get_campaign!(campaign.id)

    with node when is_map(node) <- ShareCard.find_key_node(campaign, node_id),
         attrs when is_map(attrs) <- ShareCard.key_node_asset_attr(campaign, node, style) do
      upsert_generated_asset_with_drafts(campaign, attrs)
    else
      _ -> {:error, :not_found}
    end
  end

  def generate_question_asset(
        %Campaign{} = campaign,
        question_id,
        style \\ ShareCard.default_style()
      ) do
    campaign = get_campaign!(campaign.id)

    with question when is_map(question) <- ShareCard.find_question(campaign, question_id),
         attrs when is_map(attrs) <- ShareCard.question_asset_attr(campaign, question, style) do
      upsert_generated_asset_with_drafts(campaign, attrs)
    else
      _ -> {:error, :not_found}
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

  def follow_up_questions(%Campaign{raw_payload: raw_payload}),
    do: MediaPayload.follow_up_questions(raw_payload)

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
