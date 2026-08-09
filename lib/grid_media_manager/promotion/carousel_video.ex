defmodule GridMediaManager.Promotion.CarouselVideo do
  @moduledoc """
  Packages finished browser-rendered PNG frames into an H.264 MP4.

  This module does not lay out text or draw visuals. Its only media operation is
  transcoding the exact frames saved by the client canvas.
  """

  require Logger

  alias GridMediaManager.Campaigns.Campaign
  alias GridMediaManager.Campaigns.MediaAsset
  alias GridMediaManager.Promotion.ArtifactStore
  alias GridMediaManager.Promotion.ShareCard
  alias GridMediaManager.Social.Platforms

  @width 1080
  @height 1920
  @seconds_per_frame 3.0
  @audio_fade_seconds 0.5
  @audio_volume 0.18
  @audio_bitrate "160k"
  @frame_rate 30
  @render_timeout 300_000
  @render_timeout_per_second 5_000
  @cache_version 24
  @default_background_audio_path "priv/static/sounds/rationalgrid_theme.mp4"

  def available?, do: is_binary(ffmpeg_path())

  def asset_attr(%Campaign{} = campaign, node, style) when is_map(node) do
    style = ShareCard.normalize_style(style)
    node_id = node |> value("id") |> to_string()
    node_title = node |> value("title") |> present_string() |> fallback("Key idea")
    slides = ShareCard.node_short_video_slides(campaign, node)

    %{
      title: "#{node_title} · Short video",
      kind: "key_node_video",
      url: identity_url(campaign, "node", node_id, style),
      mime_type: "video/mp4",
      text: node |> value("excerpt") |> present_string() |> fallback(node_title),
      node_id: node_id,
      highlight_id: nil,
      recommended_platforms: Platforms.video_ids(),
      style: style,
      source_type: "key_node_video",
      source_id: node_id,
      metadata: video_metadata(slides)
    }
  end

  def curated_asset_attr(%Campaign{} = campaign, token, slides, style, opts \\ [])
      when is_list(slides) and is_list(opts) do
    style = ShareCard.normalize_style(style)
    selection = Keyword.get(opts, :selected_slide_indexes)
    indexes = ShareCard.curated_carousel_selected_slide_indexes(slides, selection)

    metadata =
      slides
      |> video_metadata()
      |> Map.put("selected_slide_indexes", indexes)

    %{
      title: "#{campaign.title} · Story Short",
      kind: "curated_carousel_video",
      url: identity_url(campaign, "story", token, style),
      mime_type: "video/mp4",
      text: campaign.title,
      node_id: nil,
      highlight_id: nil,
      recommended_platforms: Platforms.video_ids(),
      style: style,
      source_type: "curated_carousel_video",
      source_id: token,
      metadata: metadata
    }
  end

  def duration_seconds(durations) when is_list(durations) and durations != [] do
    durations |> Enum.sum() |> Float.round(2)
  end

  def duration_seconds(slide_count) when is_integer(slide_count) and slide_count > 0,
    do: Float.round(slide_count * @seconds_per_frame, 2)

  def duration_seconds(_value), do: 0.0

  def background_audio_available?, do: is_binary(background_audio_path())

  @doc """
  Encodes finished client artifacts without changing their visual content.
  """
  def render_artifacts(%MediaAsset{} = asset, indexes) when is_list(indexes) and indexes != [] do
    artifacts = Enum.map(indexes, &ArtifactStore.artifact(asset, &1))

    with true <- Enum.all?(artifacts, &valid_artifact?/1),
         ffmpeg when is_binary(ffmpeg) <- ffmpeg_path(),
         {:ok, cache_dir} <- ensure_cache_dir() do
      output_path = Path.join(cache_dir, cache_filename(asset, indexes, artifacts))

      if valid_video_file?(output_path) do
        {:ok, output_path}
      else
        durations = Enum.map(indexes, fn _index -> @seconds_per_frame end)

        encode_frames(ffmpeg, durations, cache_dir, output_path, fn position ->
          artifacts
          |> Enum.at(position - 1)
          |> Map.fetch!("path")
          |> File.read!()
        end)
      end
    else
      false -> {:error, :artifact_not_ready}
      nil -> {:error, :ffmpeg_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def render_artifacts(%MediaAsset{}, _indexes), do: {:error, :artifact_not_ready}

  defp video_metadata(slides) do
    %{
      "format" => "short_video",
      "width" => @width,
      "height" => @height,
      "slide_count" => length(slides),
      "duration_seconds" => duration_seconds(length(slides)),
      "background_audio" => background_audio_available?(),
      "slides" => slides
    }
  end

  defp identity_url(%Campaign{id: campaign_id}, kind, source_id, style) do
    source_id = URI.encode(to_string(source_id), &URI.char_unreserved?/1)
    query = URI.encode_query(%{style: ShareCard.normalize_style(style)})
    "/client-assets/campaigns/#{campaign_id}/videos/#{kind}/#{source_id}?#{query}"
  end

  defp encode_frames(ffmpeg, durations, cache_dir, output_path, frame_fun) do
    work_dir = Path.join(cache_dir, "work-#{System.unique_integer([:positive, :monotonic])}")

    with :ok <- File.mkdir_p(work_dir) do
      try do
        slide_paths = write_frames!(length(durations), frame_fun, work_dir)
        manifest_path = write_concat_manifest!(slide_paths, durations, work_dir)
        temporary_output = Path.join(work_dir, "artifact.mp4")
        args = ffmpeg_args(manifest_path, background_audio_path(), temporary_output, durations)

        case run_ffmpeg(ffmpeg, args, duration_seconds(durations)) do
          {:ok, _output} ->
            with true <- valid_video_file?(temporary_output),
                 :ok <- move_video(temporary_output, output_path) do
              {:ok, output_path}
            else
              false -> {:error, :empty_video}
              {:error, reason} -> {:error, reason}
            end

          {:error, reason, output} ->
            Logger.warning(
              "Client artifact video encoding failed: #{String.slice(output, 0, 1_000)}"
            )

            {:error, reason}
        end
      rescue
        error ->
          Logger.warning("Client artifact video encoding failed: #{Exception.message(error)}")
          {:error, :encoding_failed}
      after
        File.rm_rf(work_dir)
      end
    end
  end

  defp write_frames!(frame_count, frame_fun, work_dir) do
    Enum.map(1..frame_count, fn index ->
      path = Path.join(work_dir, "slide-#{index}.png")
      File.write!(path, frame_fun.(index))
      path
    end)
  end

  defp write_concat_manifest!(slide_paths, durations, work_dir) do
    manifest_path = Path.join(work_dir, "slides.concat.txt")

    entries =
      Enum.zip(slide_paths, durations)
      |> Enum.map_join("\n", fn {path, duration} ->
        "file '#{escape_concat_path(path)}'\nduration #{decimal(duration)}"
      end)

    contents = entries <> "\nfile '#{escape_concat_path(List.last(slide_paths))}'\n"
    File.write!(manifest_path, contents)
    manifest_path
  end

  defp escape_concat_path(path), do: String.replace(path, "'", "'\\''")

  defp ffmpeg_args(manifest_path, audio_path, output_path, durations) do
    audio? = is_binary(audio_path)
    duration = duration_seconds(durations)

    [
      "-y",
      "-hide_banner",
      "-loglevel",
      "error",
      "-f",
      "concat",
      "-safe",
      "0",
      "-i",
      manifest_path
    ] ++
      audio_input_args(audio_path) ++
      ["-vf", video_filter(), "-map", "0:v:0"] ++
      if(audio?, do: ["-map", "1:a:0", "-af", audio_filter(duration)], else: ["-an"]) ++
      [
        "-c:v",
        "libx264",
        "-preset",
        "veryfast",
        "-crf",
        "20",
        "-pix_fmt",
        "yuv420p",
        "-r",
        Integer.to_string(@frame_rate),
        "-t",
        decimal(duration)
      ] ++
      if(audio?, do: ["-c:a", "aac", "-b:a", @audio_bitrate], else: []) ++
      ["-movflags", "+faststart", "-f", "mp4", output_path]
  end

  defp video_filter do
    "scale=#{@width}:#{@height}:force_original_aspect_ratio=decrease," <>
      "pad=#{@width}:#{@height}:(ow-iw)/2:(oh-ih)/2," <>
      "setsar=1,format=yuv420p,fps=#{@frame_rate}"
  end

  defp audio_input_args(path) when is_binary(path), do: ["-stream_loop", "-1", "-i", path]
  defp audio_input_args(_path), do: []

  defp audio_filter(duration) do
    fade_out_start = max(duration - @audio_fade_seconds, 0.0)

    "apad=pad_dur=#{decimal(duration)},atrim=duration=#{decimal(duration)},asetpts=PTS-STARTPTS," <>
      "volume=#{decimal(@audio_volume)}," <>
      "afade=t=in:st=0:d=#{decimal(@audio_fade_seconds)}," <>
      "afade=t=out:st=#{decimal(fade_out_start)}:d=#{decimal(@audio_fade_seconds)}"
  end

  defp run_ffmpeg(executable, args, expected_duration) do
    task = Task.async(fn -> System.cmd(executable, args, stderr_to_stdout: true) end)
    timeout = ffmpeg_timeout(expected_duration)

    case Task.yield(task, timeout) do
      {:ok, {output, 0}} ->
        {:ok, output}

      {:ok, {output, status}} ->
        {:error, {:ffmpeg_exit, status}, output}

      {:exit, reason} ->
        {:error, {:ffmpeg_exit, reason}, inspect(reason)}

      nil ->
        Task.shutdown(task, :brutal_kill)
        {:error, :timeout, "FFmpeg exceeded #{timeout}ms"}
    end
  end

  defp move_video(source, destination) do
    case File.rename(source, destination) do
      :ok ->
        :ok

      {:error, :eexist} ->
        if(valid_video_file?(destination), do: :ok, else: {:error, :cache_write_failed})

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp cache_filename(asset, indexes, artifacts) do
    signature = Enum.map(artifacts, &Map.take(&1, ["sha256", "byte_size"]))

    digest =
      {@cache_version, asset.id, indexes, signature, video_filter(), background_audio_signature()}
      |> :erlang.term_to_binary()
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.url_encode64(padding: false)

    "client-#{digest}.mp4"
  end

  defp valid_artifact?(%{"path" => path}) when is_binary(path), do: File.regular?(path)
  defp valid_artifact?(_artifact), do: false

  defp ensure_cache_dir do
    cache_dir = Path.join(System.tmp_dir!(), "grid_media_manager/client_videos")

    case File.mkdir_p(cache_dir),
      do: (
        :ok -> {:ok, cache_dir}
        {:error, reason} -> {:error, reason}
      )
  end

  defp valid_video_file?(path) do
    case File.stat(path) do
      {:ok, %{type: :regular, size: size}} when size > 0 -> true
      _result -> false
    end
  end

  defp background_audio_signature do
    case background_audio_path() do
      nil ->
        :no_audio

      path ->
        case File.stat(path) do
          {:ok, stat} -> {path, stat.size, stat.mtime, @audio_volume}
          {:error, _reason} -> :no_audio
        end
    end
  end

  defp background_audio_path do
    path =
      Application.get_env(:grid_media_manager, :video_background_audio_path) ||
        Application.app_dir(:grid_media_manager, @default_background_audio_path)

    if is_binary(path) and File.regular?(path), do: path
  end

  defp ffmpeg_timeout(expected_duration) do
    case Application.get_env(:grid_media_manager, :ffmpeg_render_timeout) do
      :infinity ->
        :infinity

      timeout when is_integer(timeout) and timeout > 0 ->
        timeout

      _value ->
        max(@render_timeout, trunc(max(expected_duration, 1.0) * @render_timeout_per_second))
    end
  end

  defp ffmpeg_path do
    Application.get_env(:grid_media_manager, :ffmpeg_path) || System.find_executable("ffmpeg")
  end

  defp decimal(value) when is_float(value), do: :erlang.float_to_binary(value, decimals: 2)

  defp value(map, key), do: Map.get(map, key) || Map.get(map, String.to_existing_atom(key))

  defp present_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      present -> present
    end
  end

  defp present_string(_value), do: nil

  defp fallback(nil, fallback), do: fallback
  defp fallback("", fallback), do: fallback
  defp fallback(value, _fallback), do: value
end
