defmodule GridMediaManager.Weekly.Evidence do
  @moduledoc "Channel-specific observations, with explicit age and sample-size limitations."
  alias GridMediaManager.Social.{Performance, Platforms}

  @defaults %{
    "x" => ["19:00"],
    "linkedin" => ["15:30"],
    "facebook" => ["09:00"],
    "instagram" => ["15:30"],
    "tiktok" => ["18:00"],
    "youtube" => ["16:00"]
  }
  def defaults, do: @defaults

  def snapshot do
    feedback = Performance.editorial_feedback()

    Map.new(Platforms.ids(), fn platform ->
      rows = Performance.results(platform)

      bins =
        rows
        |> Enum.group_by(&div(&1.sent_at.hour, 3))
        |> Enum.map(fn {bin, rs} ->
          measured = Enum.reject(rs, &is_nil(&1.exposure))

          %{
            utc_start_hour: bin * 3,
            sample_size: length(rs),
            median_exposure: median(Enum.map(measured, & &1.exposure)),
            actions: Enum.sum(Enum.map(rs, &Performance.actions/1)),
            median_post_age_hours: median(Enum.map(rs, & &1.post_age_hours)),
            median_metric_age_hours: median(Enum.map(rs, & &1.metric_age_hours))
          }
        end)
        |> Enum.sort_by(& &1.utc_start_hour)

      {platform, Map.put(feedback[platform], :time_bins, bins)}
    end)
  end

  # Prefer an observed window only when it has at least five posts and actual engagement.
  def windows(evidence) do
    Map.new(@defaults, fn {platform, [default]} ->
      data = evidence[platform] || %{}
      bins = data["time_bins"] || data[:time_bins] || []

      eligible =
        Enum.filter(bins, fn b -> field(b, :sample_size) >= 5 and field(b, :actions) > 0 end)

      time =
        case Enum.max_by(eligible, fn b -> field(b, :actions) / field(b, :sample_size) end, fn ->
               nil
             end) do
          nil ->
            default

          best ->
            hour = field(best, :utc_start_hour) + 1
            String.pad_leading(to_string(hour), 2, "0") <> ":00"
        end

      {platform, [time]}
    end)
  end

  defp field(b, key), do: Map.get(b, key, Map.get(b, Atom.to_string(key), 0))
  defp median([]), do: nil

  defp median(values) do
    sorted = Enum.sort(values)
    n = length(sorted)

    if rem(n, 2) == 1,
      do: Enum.at(sorted, div(n, 2)),
      else: (Enum.at(sorted, div(n, 2) - 1) + Enum.at(sorted, div(n, 2))) / 2
  end
end
