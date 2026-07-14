defmodule GridMediaManager.Promotion.AssetRenderer do
  @moduledoc """
  Renders persisted generated media assets into uploadable bytes.

  This keeps S3 publishing independent from the HTTP controller and allows Buffer
  scheduling to publish a local generated route without calling the Phoenix server.
  """

  alias GridMediaManager.Campaigns.Campaign
  alias GridMediaManager.Campaigns.MediaAsset
  alias GridMediaManager.Promotion.CarouselVideo
  alias GridMediaManager.Promotion.ShareCard

  def render(%Campaign{} = campaign, %MediaAsset{kind: "grid_card"} = asset) do
    {:ok, ShareCard.graph_image_png(campaign, asset.style)}
  end

  def render(%Campaign{} = campaign, %MediaAsset{kind: "highlight_card"} = asset) do
    with highlight when is_map(highlight) <-
           ShareCard.find_highlight(campaign, asset.highlight_id) do
      {:ok,
       ShareCard.highlight_platform_image_png(
         campaign,
         highlight,
         asset.style,
         asset_format(asset)
       )}
    else
      _value -> {:error, :source_not_found}
    end
  end

  def render(%Campaign{} = campaign, %MediaAsset{kind: "question_quote_card"} = asset) do
    question_id = asset.source_id || ShareCard.question_id(asset.text, asset.node_id)

    with question when is_map(question) <- ShareCard.find_question(campaign, question_id) do
      {:ok,
       ShareCard.question_platform_image_png(
         campaign,
         question,
         asset.style,
         asset_format(asset)
       )}
    else
      _value -> {:error, :source_not_found}
    end
  end

  def render(%Campaign{} = campaign, %MediaAsset{kind: "key_node_card"} = asset) do
    with node when is_map(node) <- ShareCard.find_key_node(campaign, asset.node_id) do
      {:ok, ShareCard.node_image_png(campaign, node, asset.style, asset_format(asset))}
    else
      _value -> {:error, :source_not_found}
    end
  end

  def render(%Campaign{} = campaign, %MediaAsset{kind: "key_node_carousel_slide"} = asset) do
    with node when is_map(node) <- ShareCard.find_key_node(campaign, asset.node_id) do
      {:ok,
       ShareCard.node_carousel_image_png(
         campaign,
         node,
         asset.style,
         Map.get(asset.metadata || %{}, "slide_index", 1)
       )}
    else
      _value -> {:error, :source_not_found}
    end
  end

  def render(%Campaign{} = campaign, %MediaAsset{kind: "curated_carousel"} = asset) do
    slides = Map.get(asset.metadata || %{}, "slides", [])
    {:ok, ShareCard.curated_carousel_image_png(campaign, slides, asset.style, 1)}
  end

  def render(%Campaign{} = campaign, %MediaAsset{kind: "curated_carousel_video"} = asset) do
    slides = Map.get(asset.metadata || %{}, "slides", [])

    with {:ok, path} <-
           CarouselVideo.render_curated(
             campaign,
             asset.source_id,
             slides,
             asset.style
           ) do
      File.read(path)
    end
  end

  def render(%Campaign{} = campaign, %MediaAsset{kind: "key_node_video"} = asset) do
    with node when is_map(node) <- ShareCard.find_key_node(campaign, asset.node_id),
         {:ok, path} <- CarouselVideo.render(campaign, node, asset.style) do
      File.read(path)
    else
      nil -> {:error, :source_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def render(%Campaign{} = campaign, %MediaAsset{kind: "question_video"} = asset) do
    with question when is_map(question) <- ShareCard.find_question(campaign, asset.source_id),
         {:ok, path} <-
           CarouselVideo.render_static(
             {:question, campaign.id, asset.source_id, asset.style, question},
             fn ->
               ShareCard.question_platform_image_png(campaign, question, asset.style, "short")
             end
           ) do
      File.read(path)
    else
      nil -> {:error, :source_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def render(%Campaign{} = campaign, %MediaAsset{kind: "highlight_video"} = asset) do
    with highlight when is_map(highlight) <-
           ShareCard.find_highlight(campaign, asset.highlight_id),
         {:ok, path} <-
           CarouselVideo.render_static(
             {:highlight, campaign.id, asset.highlight_id, asset.style, highlight},
             fn ->
               ShareCard.highlight_platform_image_png(campaign, highlight, asset.style, "short")
             end
           ) do
      File.read(path)
    else
      nil -> {:error, :source_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def render(%Campaign{}, %MediaAsset{}), do: {:error, :unsupported_asset}

  def render_all(%Campaign{} = campaign, %MediaAsset{kind: "curated_carousel"} = asset) do
    slides = Map.get(asset.metadata || %{}, "slides", [])

    slides
    |> Enum.with_index(1)
    |> Enum.map(fn {_slide, index} ->
      ShareCard.curated_carousel_image_png(campaign, slides, asset.style, index)
    end)
    |> then(&{:ok, &1})
  end

  def render_all(%Campaign{} = campaign, %MediaAsset{} = asset) do
    with {:ok, body} <- render(campaign, asset), do: {:ok, [body]}
  end

  defp asset_format(%MediaAsset{metadata: metadata}) when is_map(metadata),
    do: Map.get(metadata, "format", "landscape")

  defp asset_format(_asset), do: "landscape"
end
