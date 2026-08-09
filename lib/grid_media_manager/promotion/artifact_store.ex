defmodule GridMediaManager.Promotion.ArtifactStore do
  @moduledoc """
  Stores finished media produced by the browser canvas.

  The browser owns visual composition. This module only persists and reads the
  resulting bytes, making it a small boundary that can be replaced by
  RationalGrid's object storage when the studio is integrated there.
  """

  alias GridMediaManager.Campaigns.MediaAsset

  @png_signature <<137, 80, 78, 71, 13, 10, 26, 10>>
  @renderer_version 2

  def renderer_version, do: @renderer_version

  def current_renderer_version?(version), do: to_string(version) == to_string(@renderer_version)

  def put_png(asset, index, body, renderer_version \\ @renderer_version)

  def put_png(%MediaAsset{} = asset, index, body, renderer_version)
      when is_integer(index) and index > 0 and is_binary(body) do
    with :ok <- validate_png(body),
         true <- current_renderer_version?(renderer_version),
         directory <- asset_directory(asset),
         :ok <- File.mkdir_p(directory),
         digest <- sha256(body),
         path <- Path.join(directory, "#{index}-#{String.slice(digest, 0, 24)}.png"),
         :ok <- File.write(path, body) do
      {:ok,
       %{
         "path" => path,
         "mime_type" => "image/png",
         "byte_size" => byte_size(body),
         "sha256" => digest,
         "renderer_version" => @renderer_version
       }}
    else
      false -> {:error, :stale_renderer}
      {:error, reason} -> {:error, reason}
    end
  end

  def put_png(%MediaAsset{}, _index, _body, _renderer_version),
    do: {:error, :invalid_artifact}

  def read(%MediaAsset{} = asset, index) when is_integer(index) and index > 0 do
    with %{"path" => path} <- artifact(asset, index),
         true <- within_root?(path),
         {:ok, body} <- File.read(path) do
      {:ok, body}
    else
      _error -> {:error, :artifact_not_ready}
    end
  end

  def read(%MediaAsset{}, _index), do: {:error, :artifact_not_ready}

  def read_all(%MediaAsset{} = asset, indexes) when is_list(indexes) do
    Enum.reduce_while(indexes, {:ok, []}, fn index, {:ok, bodies} ->
      case read(asset, index) do
        {:ok, body} -> {:cont, {:ok, [body | bodies]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, bodies} -> {:ok, Enum.reverse(bodies)}
      error -> error
    end
  end

  def artifact(%MediaAsset{metadata: metadata}, index) when is_map(metadata) do
    artifact = metadata |> Map.get("artifacts", %{}) |> Map.get(to_string(index))

    case artifact do
      %{"renderer_version" => @renderer_version} -> artifact
      _stale_or_missing -> nil
    end
  end

  def artifact(%MediaAsset{}, _index), do: nil

  def ready?(%MediaAsset{} = asset, indexes) when is_list(indexes) do
    indexes != [] and Enum.all?(indexes, &artifact_ready?(asset, &1))
  end

  def root do
    Application.get_env(:grid_media_manager, :artifact_store_path) ||
      Path.join(File.cwd!(), "storage/artifacts")
  end

  defp asset_directory(%MediaAsset{campaign_id: campaign_id, id: asset_id}) do
    Path.join([root(), Integer.to_string(campaign_id), Integer.to_string(asset_id)])
  end

  defp validate_png(body) when byte_size(body) <= 12_000_000 do
    if String.starts_with?(body, @png_signature), do: :ok, else: {:error, :invalid_png}
  end

  defp validate_png(_body), do: {:error, :artifact_too_large}

  defp sha256(body), do: :crypto.hash(:sha256, body) |> Base.encode16(case: :lower)

  defp within_root?(path) when is_binary(path) do
    expanded_root = Path.expand(root())
    expanded_path = Path.expand(path)
    expanded_path == expanded_root or String.starts_with?(expanded_path, expanded_root <> "/")
  end

  defp within_root?(_path), do: false

  defp artifact_ready?(asset, index) do
    with %{"path" => path} <- artifact(asset, index),
         true <- within_root?(path),
         {:ok, %File.Stat{type: :regular}} <- File.stat(path) do
      true
    else
      _error -> false
    end
  end
end
