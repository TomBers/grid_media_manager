defmodule GridMediaManager.Promotion.CarouselVideo do
  @moduledoc """
  Renders key-node and curated story carousels as vertical H.264 MP4s for short-form video.

  Videos are cached in the system temporary directory using a content-derived key.
  FFmpeg must be installed in the runtime environment, or configured with the
  `:ffmpeg_path` application setting. Generated videos include the configured
  RationalGrid theme as a softly mixed background audio track.
  """

  require Logger

  alias GridMediaManager.Campaigns.Campaign
  alias GridMediaManager.Promotion.ShareCard
  alias GridMediaManager.Social.Platforms

  @width 1080
  @height 1920
  @static_seconds 6.0
  @fade_seconds 0.25
  @audio_fade_seconds 0.5
  @audio_volume 0.18
  @audio_bitrate "160k"
  @frame_rate 30
  @render_timeout 300_000
  @render_timeout_per_second 5_000
  @cache_version 18
  @default_background_audio_path "priv/static/sounds/rationalgrid_theme.mp4"

  def available?, do: is_binary(ffmpeg_path())

  def asset_attr(%Campaign{} = campaign, node, style) when is_map(node) do
    style = ShareCard.normalize_style(style)
    node_id = node |> value("id") |> to_string()
    node_title = node |> value("title") |> present_string() |> fallback("Key node")
    durations = ShareCard.node_short_video_durations(campaign, node)
    slide_count = length(durations)

    %{
      title: "#{node_title} · Short video",
      kind: "key_node_video",
      url: video_path(campaign, node_id, style),
      mime_type: "video/mp4",
      text: node |> value("excerpt") |> present_string() |> fallback(node_title),
      node_id: node_id,
      highlight_id: nil,
      recommended_platforms: Platforms.video_ids(),
      style: style,
      source_type: "key_node_video",
      source_id: node_id,
      metadata: %{
        "format" => "short_video",
        "width" => @width,
        "height" => @height,
        "slide_count" => slide_count,
        "duration_seconds" => duration_seconds(durations),
        "background_audio" => background_audio_available?()
      }
    }
  end

  def curated_asset_attr(%Campaign{} = campaign, token, slides, style) when is_list(slides) do
    curated_asset_attr(campaign, token, slides, style, selected_slide_indexes: nil)
  end

  def curated_asset_attr(%Campaign{} = campaign, token, slides, style, opts)
      when is_list(slides) and is_list(opts) do
    style = ShareCard.normalize_style(style)
    selected_slide_indexes = Keyword.get(opts, :selected_slide_indexes)
    video_indexes = video_slide_indexes(slides, selected_slide_indexes)
    video_slides = selected_slides(slides, video_indexes)
    durations = ShareCard.curated_carousel_short_video_durations(video_slides)

    metadata = %{
      "format" => "short_video",
      "width" => @width,
      "height" => @height,
      "slide_count" => length(video_slides),
      "duration_seconds" => duration_seconds(durations),
      "background_audio" => background_audio_available?(),
      "slides" => slides
    }

    metadata =
      if is_list(selected_slide_indexes) do
        Map.put(metadata, "selected_slide_indexes", video_indexes)
      else
        metadata
      end

    %{
      title: "#{campaign.title} · Story Short",
      kind: "curated_carousel_video",
      url: curated_video_path(campaign, token, style),
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

  def curated_video_path(%Campaign{id: campaign_id}, token, style) do
    encoded_token = URI.encode(to_string(token), &URI.char_unreserved?/1)
    query = URI.encode_query(%{style: ShareCard.normalize_style(style), v: @cache_version})
    "/campaigns/#{campaign_id}/curated-carousels/#{encoded_token}/short.mp4?#{query}"
  end

  def video_path(%Campaign{id: campaign_id}, node_id, style) do
    encoded_node_id = URI.encode(to_string(node_id), &URI.char_unreserved?/1)
    query = URI.encode_query(%{style: ShareCard.normalize_style(style), v: @cache_version})
    "/campaigns/#{campaign_id}/nodes/#{encoded_node_id}/carousel.mp4?#{query}"
  end

  def render(%Campaign{} = campaign, node, style) when is_map(node) do
    render(campaign, node, style, force: false)
  end

  def render(%Campaign{} = campaign, node, style, opts) when is_map(node) and is_list(opts) do
    style = ShareCard.normalize_style(style)
    force? = Keyword.get(opts, :force, false)

    with ffmpeg when is_binary(ffmpeg) <- ffmpeg_path(),
         {:ok, cache_dir} <- ensure_cache_dir() do
      output_path = Path.join(cache_dir, cache_filename(campaign, node, style))
      if force?, do: File.rm(output_path)

      if not force? and valid_video_file?(output_path) do
        {:ok, output_path}
      else
        render_video(ffmpeg, campaign, node, style, cache_dir, output_path)
      end
    else
      nil -> {:error, :ffmpeg_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def render_curated(%Campaign{} = campaign, token, slides, style) when is_list(slides) do
    render_curated(campaign, token, slides, style, force: false)
  end

  def render_curated(%Campaign{} = campaign, token, slides, style, opts)
      when is_list(slides) and is_list(opts) do
    style = ShareCard.normalize_style(style)
    force? = Keyword.get(opts, :force, false)
    frame_paths = Keyword.get(opts, :frame_paths, %{})

    selected_slide_indexes =
      video_slide_indexes(slides, Keyword.get(opts, :selected_slide_indexes))

    with ffmpeg when is_binary(ffmpeg) <- ffmpeg_path(),
         {:ok, cache_dir} <- ensure_cache_dir() do
      output_path =
        Path.join(
          cache_dir,
          curated_cache_filename(
            campaign,
            token,
            slides,
            style,
            frame_paths,
            selected_slide_indexes
          )
        )

      if force?, do: File.rm(output_path)

      if not force? and valid_video_file?(output_path) do
        {:ok, output_path}
      else
        video_slides = selected_slides(slides, selected_slide_indexes)
        durations = ShareCard.curated_carousel_short_video_durations(video_slides)

        render_frame_video(
          ffmpeg,
          durations,
          cache_dir,
          output_path,
          fn index ->
            slide_index = Enum.at(selected_slide_indexes, index - 1)
            browser_frame_or_render(campaign, slides, style, slide_index, frame_paths)
          end
        )
      end
    else
      nil -> {:error, :ffmpeg_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def render_static(cache_key, frame_fun) when is_function(frame_fun, 0) do
    render_static(cache_key, frame_fun, force: false)
  end

  def render_static(cache_key, frame_fun, opts)
      when is_function(frame_fun, 0) and is_list(opts) do
    force? = Keyword.get(opts, :force, false)

    with ffmpeg when is_binary(ffmpeg) <- ffmpeg_path(),
         {:ok, cache_dir} <- ensure_cache_dir() do
      output_path = Path.join(cache_dir, static_cache_filename(cache_key))
      if force?, do: File.rm(output_path)

      if not force? and valid_video_file?(output_path) do
        {:ok, output_path}
      else
        render_static_video(ffmpeg, frame_fun, cache_dir, output_path)
      end
    else
      nil -> {:error, :ffmpeg_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def duration_seconds(durations) when is_list(durations) and durations != [] do
    durations |> Enum.sum() |> Float.round(2)
  end

  def duration_seconds(slide_count) when is_integer(slide_count) and slide_count > 0 do
    Float.round(slide_count * 3.0, 2)
  end

  def duration_seconds(_slide_count), do: 0.0

  def background_audio_available?, do: is_binary(background_audio_path())

  defp render_video(ffmpeg, campaign, node, style, cache_dir, output_path) do
    durations = ShareCard.node_short_video_durations(campaign, node)

    render_frame_video(ffmpeg, durations, cache_dir, output_path, fn index ->
      ShareCard.node_short_video_frame_png(campaign, node, style, index)
    end)
  end

  defp browser_frame_or_render(campaign, slides, style, index, frame_paths) do
    path = Map.get(frame_paths, to_string(index))

    case path && File.read(path) do
      {:ok, body} -> body
      _error -> ShareCard.curated_carousel_short_video_frame_png(campaign, slides, style, index)
    end
  end

  defp render_frame_video(ffmpeg, durations, cache_dir, output_path, frame_fun) do
    work_dir =
      Path.join(cache_dir, "work-#{System.unique_integer([:positive, :monotonic])}")

    with :ok <- File.mkdir_p(work_dir) do
      try do
        slide_paths = write_frames!(length(durations), frame_fun, work_dir)
        manifest_path = write_concat_manifest!(slide_paths, durations, work_dir)
        temporary_output = Path.join(work_dir, "carousel.mp4")
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
            Logger.warning("Carousel video encoding failed: #{String.slice(output, 0, 1_000)}")
            {:error, reason}
        end
      rescue
        error ->
          Logger.warning("Carousel video rendering failed: #{Exception.message(error)}")
          {:error, :render_failed}
      after
        File.rm_rf(work_dir)
      end
    end
  end

  defp render_static_video(ffmpeg, frame_fun, cache_dir, output_path) do
    work_dir =
      Path.join(cache_dir, "static-work-#{System.unique_integer([:positive, :monotonic])}")

    with :ok <- File.mkdir_p(work_dir) do
      try do
        frame_path = Path.join(work_dir, "frame.png")
        temporary_output = Path.join(work_dir, "short.mp4")
        File.write!(frame_path, frame_fun.())

        case run_ffmpeg(
               ffmpeg,
               static_ffmpeg_args(frame_path, background_audio_path(), temporary_output),
               @static_seconds
             ) do
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
              "Static short video encoding failed: #{String.slice(output, 0, 1_000)}"
            )

            {:error, reason}
        end
      rescue
        error ->
          Logger.warning("Static short video rendering failed: #{Exception.message(error)}")
          {:error, :render_failed}
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

    last_path = List.last(slide_paths)
    contents = entries <> "\nfile '#{escape_concat_path(last_path)}'\n"
    File.write!(manifest_path, contents)
    manifest_path
  end

  defp escape_concat_path(path), do: String.replace(path, "'", "'\\''")

  defp ffmpeg_args(manifest_path, audio_path, output_path, durations) do
    audio? = is_binary(audio_path)
    duration = duration_seconds(durations)

    base_args =
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
      ] ++ audio_input_args(audio_path)

    output_args =
      [
        "-vf",
        video_filter(),
        "-map",
        "0:v:0"
      ] ++
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
        if(audio?, do: audio_codec_args(), else: []) ++
        ["-movflags", "+faststart", "-f", "mp4", output_path]

    base_args ++ output_args
  end

  defp video_filter do
    "scale=#{@width}:#{@height}:force_original_aspect_ratio=decrease," <>
      "pad=#{@width}:#{@height}:(ow-iw)/2:(oh-ih)/2," <>
      "setsar=1,format=yuv420p,fps=#{@frame_rate}"
  end

  defp static_ffmpeg_args(frame_path, audio_path, output_path) do
    fade_out_start = @static_seconds - @fade_seconds

    base_args = [
      "-y",
      "-hide_banner",
      "-loglevel",
      "error",
      "-loop",
      "1",
      "-framerate",
      Integer.to_string(@frame_rate),
      "-t",
      decimal(@static_seconds),
      "-i",
      frame_path
    ]

    video_args = [
      "-vf",
      "scale=#{@width}:#{@height}:force_original_aspect_ratio=decrease," <>
        "pad=#{@width}:#{@height}:(ow-iw)/2:(oh-ih)/2," <>
        "format=yuv420p,fps=#{@frame_rate}," <>
        "fade=t=out:st=#{decimal(fade_out_start)}:d=#{decimal(@fade_seconds)}",
      "-c:v",
      "libx264",
      "-preset",
      "medium",
      "-crf",
      "20",
      "-pix_fmt",
      "yuv420p",
      "-r",
      Integer.to_string(@frame_rate),
      "-t",
      decimal(@static_seconds)
    ]

    output_args = ["-movflags", "+faststart", "-f", "mp4", output_path]

    if is_binary(audio_path) do
      base_args ++
        audio_input_args(audio_path) ++
        ["-map", "0:v:0", "-map", "1:a:0", "-af", audio_filter(@static_seconds)] ++
        video_args ++ audio_codec_args() ++ output_args
    else
      base_args ++ ["-an"] ++ video_args ++ output_args
    end
  end

  defp audio_input_args(path) when is_binary(path),
    do: ["-stream_loop", "-1", "-i", path]

  defp audio_input_args(_path), do: []

  defp audio_codec_args, do: ["-c:a", "aac", "-b:a", @audio_bitrate]

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
        {:error, :timeout, "FFmpeg exceeded #{timeout}ms for #{decimal(expected_duration)}s"}
    end
  end

  defp move_video(source, destination) do
    case File.rename(source, destination) do
      :ok ->
        :ok

      {:error, :eexist} ->
        if valid_video_file?(destination), do: :ok, else: {:error, :cache_write_failed}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp cache_filename(campaign, node, style) do
    digest =
      {@cache_version, campaign.id, campaign.title, node, style, @fade_seconds,
       background_audio_signature()}
      |> :erlang.term_to_binary()
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.url_encode64(padding: false)

    "#{digest}.mp4"
  end

  defp curated_cache_filename(campaign, token, slides, style, frame_paths, selected_slide_indexes) do
    digest =
      {@cache_version, :curated, campaign.id, campaign.title, token, slides, style, @fade_seconds,
       frame_paths, selected_slide_indexes, background_audio_signature()}
      |> :erlang.term_to_binary()
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.url_encode64(padding: false)

    "curated-#{digest}.mp4"
  end

  defp static_cache_filename(cache_key) do
    digest =
      {@cache_version, :static, cache_key, @static_seconds, @fade_seconds,
       background_audio_signature()}
      |> :erlang.term_to_binary()
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.url_encode64(padding: false)

    "static-#{digest}.mp4"
  end

  defp ensure_cache_dir do
    cache_dir = Path.join(System.tmp_dir!(), "grid_media_manager/carousel_videos")

    case File.mkdir_p(cache_dir) do
      :ok -> {:ok, cache_dir}
      {:error, reason} -> {:error, reason}
    end
  end

  defp valid_video_file?(path) do
    case File.stat(path) do
      {:ok, %{type: :regular, size: size}} when size > 0 -> true
      _ -> false
    end
  end

  defp background_audio_signature do
    case background_audio_path() do
      nil ->
        :no_audio

      path ->
        case File.stat(path) do
          {:ok, stat} -> {path, stat.size, stat.mtime, @audio_volume, @audio_fade_seconds}
          {:error, _reason} -> :no_audio
        end
    end
  end

  defp background_audio_path do
    configured_path =
      Application.get_env(:grid_media_manager, :video_background_audio_path) ||
        Application.app_dir(:grid_media_manager, @default_background_audio_path)

    if is_binary(configured_path) and File.regular?(configured_path), do: configured_path
  end

  defp video_slide_indexes(slides, nil) do
    case length(slides) do
      0 -> []
      count -> Enum.to_list(1..count)
    end
  end

  defp video_slide_indexes(slides, selection) when is_list(selection) do
    ShareCard.curated_carousel_selected_slide_indexes(slides, selection)
  end

  defp selected_slides(slides, indexes) do
    indexes
    |> Enum.map(&Enum.at(slides, &1 - 1))
    |> Enum.reject(&is_nil/1)
  end

  defp ffmpeg_timeout(expected_duration) do
    case Application.get_env(:grid_media_manager, :ffmpeg_render_timeout) do
      :infinity -> :infinity
      timeout when is_integer(timeout) and timeout > 0 -> timeout
      _ -> max(@render_timeout, trunc(max(expected_duration, 1.0) * @render_timeout_per_second))
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
      value -> value
    end
  end

  defp present_string(_value), do: nil

  defp fallback(nil, fallback), do: fallback
  defp fallback("", fallback), do: fallback
  defp fallback(value, _fallback), do: value
end
