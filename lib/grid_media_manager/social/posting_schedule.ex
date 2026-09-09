defmodule GridMediaManager.Social.PostingSchedule do
  @moduledoc "Builds a reviewable schedule of future, unoccupied days from a live Buffer queue."

  # UTC test windows informed by Buffer's March 2026 research, assuming a UK audience.
  # These are starting hypotheses, not statistically established account optima.
  @windows %{
    "facebook" => [~T[08:00:00], ~T[10:00:00]],
    "x" => [~T[08:00:00], ~T[09:30:00]],
    "linkedin" => [~T[15:00:00], ~T[16:30:00]],
    "instagram" => [~T[08:00:00], ~T[17:00:00]],
    "tiktok" => [~T[18:00:00], ~T[20:00:00]],
    "youtube" => [~T[15:00:00], ~T[17:00:00]]
  }

  def windows, do: @windows

  def slots(platform, count, queued_posts, opts \\ []) when count >= 0 do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    times = Keyword.get(opts, :times, Map.fetch!(@windows, platform))

    occupied =
      queued_posts
      |> Enum.flat_map(fn post ->
        case DateTime.from_iso8601(post.due_at || "") do
          {:ok, due_at, _} -> [DateTime.to_date(due_at)]
          _ -> []
        end
      end)
      |> MapSet.new()

    earliest = Keyword.get(opts, :start_date, DateTime.to_date(now))
    start_date = Enum.max([earliest, DateTime.to_date(now) | MapSet.to_list(occupied)], Date)

    Stream.iterate(start_date, &Date.add(&1, 1))
    |> Stream.reject(&MapSet.member?(occupied, &1))
    |> Stream.filter(
      &(platform not in ["x", "facebook", "linkedin", "instagram"] or Date.day_of_week(&1) <= 5)
    )
    |> Stream.with_index()
    |> Stream.map(fn {date, index} ->
      DateTime.new!(date, Enum.at(times, rem(index, length(times))), "Etc/UTC")
    end)
    |> Stream.filter(&(DateTime.compare(&1, DateTime.add(now, 3600)) == :gt))
    |> Enum.take(count)
  end
end
