defmodule GridMediaManager.Promotion.CarouselVideo do
  @moduledoc """
  Renders a key-node carousel as a vertical H.264 MP4 for short-form social video.

  Videos are cached in the system temporary directory using a content-derived key.
  FFmpeg must be installed in the runtime environment, or configured with the
  `:ffmpeg_path` application setting.
  """

  require Logger

  alias GridMediaManager.Campaigns.Campaign
  alias GridMediaManager.Promotion.ShareCard

  @width 1080
  @height 1920
  @slide_seconds 3.0
  @static_seconds 6.0
  @fade_seconds 0.25
  @frame_rate 30
  @render_timeout 90_000
  @cache_version 4

  def available?, do: is_binary(ffmpeg_path())

  def asset_attr(%Campaign{} = campaign, node, style) when is_map(node) do
    style = ShareCard.normalize_style(style)
    node_id = node |> value("id") |> to_string()
    node_title = node |> value("title") |> present_string() |> fallback("Key node")
    slide_count = campaign |> ShareCard.carousel_slides(node) |> length()

    %{
      title: "#{node_title} · Short video",
      kind: "key_node_video",
      url: video_path(campaign, node_id, style),
      mime_type: "video/mp4",
      text: node |> value("excerpt") |> present_string() |> fallback(node_title),
      node_id: node_id,
      highlight_id: nil,
      recommended_platforms: ["youtube", "instagram", "linkedin"],
      style: style,
      source_type: "key_node_video",
      source_id: node_id,
      metadata: %{
        "format" => "short_video",
        "width" => @width,
        "height" => @height,
        "slide_count" => slide_count,
        "duration_seconds" => duration_seconds(slide_count)
      }
    }
  end

  def video_path(%Campaign{id: campaign_id}, node_id, style) do
    encoded_node_id = URI.encode(to_string(node_id), &URI.char_unreserved?/1)
    query = URI.encode_query(%{style: ShareCard.normalize_style(style)})
    "/campaigns/#{campaign_id}/nodes/#{encoded_node_id}/carousel.mp4?#{query}"
  end

  def render(%Campaign{} = campaign, node, style) when is_map(node) do
    style = ShareCard.normalize_style(style)

    with ffmpeg when is_binary(ffmpeg) <- ffmpeg_path(),
         {:ok, cache_dir} <- ensure_cache_dir() do
      output_path = Path.join(cache_dir, cache_filename(campaign, node, style))

      if valid_video_file?(output_path) do
        {:ok, output_path}
      else
        render_video(ffmpeg, campaign, node, style, cache_dir, output_path)
      end
    else
      nil -> {:error, :ffmpeg_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def render_static(cache_key, frame_fun) when is_function(frame_fun, 0) do
    with ffmpeg when is_binary(ffmpeg) <- ffmpeg_path(),
         {:ok, cache_dir} <- ensure_cache_dir() do
      output_path = Path.join(cache_dir, static_cache_filename(cache_key))

      if valid_video_file?(output_path) do
        {:ok, output_path}
      else
        render_static_video(ffmpeg, frame_fun, cache_dir, output_path)
      end
    else
      nil -> {:error, :ffmpeg_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def duration_seconds(slide_count) when is_integer(slide_count) and slide_count > 0 do
    Float.round(slide_count * @slide_seconds, 2)
  end

  def duration_seconds(_slide_count), do: 0.0

  defp render_video(ffmpeg, campaign, node, style, cache_dir, output_path) do
    work_dir =
      Path.join(
        cache_dir,
        "work-#{System.unique_integer([:positive, :monotonic])}"
      )

    with :ok <- File.mkdir_p(work_dir) do
      try do
        slide_paths = write_slides!(campaign, node, style, work_dir)
        temporary_output = Path.join(work_dir, "carousel.mp4")
        args = ffmpeg_args(slide_paths, temporary_output)

        case run_ffmpeg(ffmpeg, args) do
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

        case run_ffmpeg(ffmpeg, static_ffmpeg_args(frame_path, temporary_output)) do
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

  defp write_slides!(campaign, node, style, work_dir) do
    campaign
    |> ShareCard.carousel_slides(node)
    |> Enum.with_index(1)
    |> Enum.map(fn {_slide, index} ->
      path = Path.join(work_dir, "slide-#{index}.png")
      png = ShareCard.node_short_video_frame_png(campaign, node, style, index)
      File.write!(path, png)
      path
    end)
  end

  defp ffmpeg_args(slide_paths, output_path) do
    input_args =
      Enum.flat_map(slide_paths, fn path ->
        [
          "-loop",
          "1",
          "-framerate",
          Integer.to_string(@frame_rate),
          "-t",
          decimal(@slide_seconds),
          "-i",
          path
        ]
      end)

    ["-y", "-hide_banner", "-loglevel", "error"] ++
      input_args ++
      [
        "-filter_complex",
        filter_complex(length(slide_paths)),
        "-map",
        "[outv]",
        "-an",
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
        decimal(duration_seconds(length(slide_paths))),
        "-movflags",
        "+faststart",
        "-f",
        "mp4",
        output_path
      ]
  end

  defp static_ffmpeg_args(frame_path, output_path) do
    fade_out_start = @static_seconds - @fade_seconds

    [
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
      frame_path,
      "-vf",
      "scale=#{@width}:#{@height}:force_original_aspect_ratio=decrease," <>
        "pad=#{@width}:#{@height}:(ow-iw)/2:(oh-ih)/2," <>
        "format=yuv420p,fps=#{@frame_rate}," <>
        "fade=t=in:st=0:d=#{decimal(@fade_seconds)}," <>
        "fade=t=out:st=#{decimal(fade_out_start)}:d=#{decimal(@fade_seconds)}",
      "-an",
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
      decimal(@static_seconds),
      "-movflags",
      "+faststart",
      "-f",
      "mp4",
      output_path
    ]
  end

  defp filter_complex(slide_count) do
    slide_filters =
      0..(slide_count - 1)
      |> Enum.map(&slide_filter/1)

    inputs = Enum.map_join(0..(slide_count - 1), "", &"[v#{&1}]")
    concat_filter = "#{inputs}concat=n=#{slide_count}:v=1:a=0[outv]"
    Enum.join(slide_filters ++ [concat_filter], ";")
  end

  defp slide_filter(index) do
    "[#{index}:v]scale=#{@width}:#{@height}:force_original_aspect_ratio=decrease," <>
      "pad=#{@width}:#{@height}:(ow-iw)/2:(oh-ih)/2," <>
      "setsar=1,format=yuv420p,fps=#{@frame_rate},trim=duration=#{decimal(@slide_seconds)}," <>
      "settb=AVTB,setpts=N/(#{@frame_rate}*TB)," <>
      "fade=t=in:st=0:d=#{decimal(@fade_seconds)}," <>
      "fade=t=out:st=#{decimal(@slide_seconds - @fade_seconds)}:" <>
      "d=#{decimal(@fade_seconds)}[v#{index}]"
  end

  defp run_ffmpeg(executable, args) do
    task = Task.async(fn -> System.cmd(executable, args, stderr_to_stdout: true) end)

    case Task.yield(task, @render_timeout) do
      {:ok, {output, 0}} ->
        {:ok, output}

      {:ok, {output, status}} ->
        {:error, {:ffmpeg_exit, status}, output}

      {:exit, reason} ->
        {:error, {:ffmpeg_exit, reason}, inspect(reason)}

      nil ->
        Task.shutdown(task, :brutal_kill)
        {:error, :timeout, "FFmpeg exceeded #{@render_timeout}ms"}
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
      {@cache_version, campaign.id, campaign.title, node, style, @slide_seconds, @fade_seconds}
      |> :erlang.term_to_binary()
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.url_encode64(padding: false)

    "#{digest}.mp4"
  end

  defp static_cache_filename(cache_key) do
    digest =
      {@cache_version, :static, cache_key, @static_seconds, @fade_seconds}
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
