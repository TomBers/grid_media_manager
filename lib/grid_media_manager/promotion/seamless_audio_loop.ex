defmodule GridMediaManager.Promotion.SeamlessAudioLoop do
  @moduledoc """
  Builds a crossfaded FFmpeg audio loop from a single decoded source.

  Looping the input container repeats AAC encoder padding and can create a click
  at each join. A direct decoded-sample loop can still click when the final and
  first waveforms do not meet. This module overlaps the tail with the head, then
  loops that continuous cycle before the final AAC encode.
  """

  @maximum_loop_samples 2_147_483_647
  @output_label "looped_audio"

  def input_args(path) when is_binary(path), do: ["-i", path]
  def input_args(_path), do: []

  def output_label, do: @output_label

  def source_duration(path) when is_binary(path) do
    with executable when is_binary(executable) <- ffprobe_path(),
         {output, 0} <-
           System.cmd(executable, [
             "-v",
             "error",
             "-select_streams",
             "a:0",
             "-show_entries",
             "stream=duration",
             "-of",
             "default=noprint_wrappers=1:nokey=1",
             path
           ]),
         {duration, _remainder} <- output |> String.trim() |> Float.parse(),
         true <- duration > 0 do
      {:ok, duration}
    else
      _reason -> {:error, :duration_unavailable}
    end
  end

  def source_duration(_path), do: {:error, :duration_unavailable}

  def filter(source_duration, output_duration, volume, crossfade_seconds)
      when is_number(source_duration) and is_number(output_duration) and is_number(volume) and
             is_number(crossfade_seconds) and source_duration > crossfade_seconds * 2 do
    middle_end = source_duration - crossfade_seconds
    fade_out_start = max(output_duration - crossfade_seconds, 0.0)

    "[1:a:0]asplit=3[loop_head][loop_middle][loop_tail];" <>
      "[loop_head]atrim=start=0:end=#{seconds(crossfade_seconds)}," <>
      "asetpts=PTS-STARTPTS[loop_head_trimmed];" <>
      "[loop_middle]atrim=start=#{seconds(crossfade_seconds)}:end=#{seconds(middle_end)}," <>
      "asetpts=PTS-STARTPTS[loop_middle_trimmed];" <>
      "[loop_tail]atrim=start=#{seconds(middle_end)}:end=#{seconds(source_duration)}," <>
      "asetpts=PTS-STARTPTS[loop_tail_trimmed];" <>
      "[loop_tail_trimmed][loop_head_trimmed]" <>
      "acrossfade=d=#{seconds(crossfade_seconds)}:c1=tri:c2=tri[loop_seam];" <>
      "[loop_seam][loop_middle_trimmed]concat=n=2:v=0:a=1," <>
      loop_filter(output_duration, volume, crossfade_seconds, fade_out_start)
  end

  def filter(_source_duration, output_duration, volume, crossfade_seconds) do
    fallback_filter(output_duration, volume, crossfade_seconds)
  end

  def fallback_filter(output_duration, volume, fade_seconds)
      when is_number(output_duration) and is_number(volume) and is_number(fade_seconds) do
    fade_out_start = max(output_duration - fade_seconds, 0.0)

    "[1:a:0]" <> loop_filter(output_duration, volume, fade_seconds, fade_out_start)
  end

  defp loop_filter(output_duration, volume, fade_seconds, fade_out_start) do
    "aloop=loop=-1:size=#{@maximum_loop_samples},asetpts=N/SR/TB," <>
      "atrim=duration=#{decimal(output_duration)}," <>
      "volume=#{decimal(volume)}," <>
      "afade=t=in:st=0:d=#{decimal(fade_seconds)}," <>
      "afade=t=out:st=#{decimal(fade_out_start)}:d=#{decimal(fade_seconds)}" <>
      "[#{@output_label}]"
  end

  defp ffprobe_path do
    Application.get_env(:grid_media_manager, :ffprobe_path) || System.find_executable("ffprobe")
  end

  defp seconds(value) when is_integer(value), do: seconds(value / 1)
  defp seconds(value) when is_float(value), do: :erlang.float_to_binary(value, decimals: 6)

  defp decimal(value) when is_integer(value), do: decimal(value / 1)
  defp decimal(value) when is_float(value), do: :erlang.float_to_binary(value, decimals: 2)
end
