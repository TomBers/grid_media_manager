defmodule GridMediaManager.Promotion.SeamlessAudioLoop do
  @moduledoc """
  Builds a gapless FFmpeg audio loop from a single decoded source.

  Looping the input container repeats AAC encoder padding and can create a click
  at each join. Buffering and looping decoded samples keeps one continuous audio
  timeline before the final AAC encode.
  """

  @maximum_loop_samples 2_147_483_647

  def input_args(path) when is_binary(path), do: ["-i", path]
  def input_args(_path), do: []

  def filter(duration, volume, fade_seconds)
      when is_number(duration) and is_number(volume) and is_number(fade_seconds) do
    fade_out_start = max(duration - fade_seconds, 0.0)

    "aloop=loop=-1:size=#{@maximum_loop_samples},asetpts=N/SR/TB," <>
      "atrim=duration=#{decimal(duration)}," <>
      "volume=#{decimal(volume)}," <>
      "afade=t=in:st=0:d=#{decimal(fade_seconds)}," <>
      "afade=t=out:st=#{decimal(fade_out_start)}:d=#{decimal(fade_seconds)}"
  end

  defp decimal(value) when is_integer(value), do: decimal(value / 1)
  defp decimal(value) when is_float(value), do: :erlang.float_to_binary(value, decimals: 2)
end
