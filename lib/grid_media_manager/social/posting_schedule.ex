defmodule GridMediaManager.Social.PostingSchedule do
  @moduledoc "Builds daily UK and US Eastern test slots around the live Buffer queue."

  # Local wall times, not proven account optima. All windows are after the DST
  # transition hour and remain on the same UTC date in both seasons.
  @windows %{
    "facebook" => %{uk: ~T[09:00:00], us: ~T[09:00:00]},
    "x" => %{uk: ~T[09:00:00], us: ~T[09:00:00]},
    "linkedin" => %{uk: ~T[10:00:00], us: ~T[10:00:00]},
    "instagram" => %{uk: ~T[12:00:00], us: ~T[18:00:00]},
    "tiktok" => %{uk: ~T[18:00:00], us: ~T[18:00:00]},
    "youtube" => %{uk: ~T[16:00:00], us: ~T[16:00:00]}
  }

  def windows, do: @windows

  def slots(platform, count, queued_posts, opts \\ []) when count >= 0 do
    market_slots(platform, count, queued_posts, opts) |> Enum.map(& &1.scheduled_for)
  end

  def market_slots(platform, count, queued_posts, opts \\ []) when count >= 0 do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    start_date =
      Enum.max(
        [Keyword.get(opts, :start_date, DateTime.to_date(now)), DateTime.to_date(now)],
        Date
      )

    occupied =
      queued_posts
      |> Enum.flat_map(fn post ->
        case DateTime.from_iso8601(post.due_at || "") do
          {:ok, due_at, _} -> [due_at]
          _ -> []
        end
      end)
      |> Enum.group_by(&DateTime.to_date/1)

    Stream.iterate(start_date, &Date.add(&1, 1))
    |> Stream.flat_map(fn date ->
      day = day_slots(platform, date)

      case Map.get(occupied, date, []) do
        [] ->
          day

        [post] ->
          nearest = Enum.min_by(day, &abs(DateTime.diff(&1.scheduled_for, post)))
          Enum.reject(day, &(&1.market == nearest.market))

        _ ->
          []
      end
    end)
    |> Stream.filter(&(DateTime.compare(&1.scheduled_for, DateTime.add(now, 3600)) == :gt))
    |> Enum.take(count)
  end

  @doc "Matches market-specific content to its window; unlabelled jobs can use either."
  def assign_jobs(platform, jobs, queued_posts, opts \\ []) do
    # Allow for one-market batches and existing posts occupying that market.
    market_slots(platform, (length(jobs) + length(queued_posts)) * 2, queued_posts, opts)
    |> Enum.reduce({[], jobs}, fn slot, {assigned, remaining} ->
      case Enum.find_index(remaining, &(Map.get(&1, :market) in [nil, slot.market])) do
        nil ->
          {assigned, remaining}

        index ->
          {job, rest} = List.pop_at(remaining, index)
          {[Map.merge(job, slot) | assigned], rest}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp day_slots(platform, date) do
    for market <- [:uk, :us] do
      time = Map.fetch!(@windows, platform) |> Map.fetch!(market)

      utc =
        DateTime.new!(date, time, "Etc/UTC") |> DateTime.add(-offset_hours(date, market) * 3600)

      %{market: market, scheduled_for: utc}
    end
  end

  # Current statutory rules for daytime publishing, valid from 2007 onwards.
  # https://www.gov.uk/when-do-the-clocks-change
  # https://www.nist.gov/pml/time-and-frequency-division/popular-links/daylight-saving-time-dst
  # Keep these explicit until the application adopts an IANA time-zone database.
  defp offset_hours(%Date{year: year} = date, market) when year >= 2007 do
    {starts, ends, standard} =
      case market do
        :uk -> {last_sunday(year, 3), last_sunday(year, 10), 0}
        :us -> {Date.add(first_sunday(year, 3), 7), first_sunday(year, 11), -5}
      end

    if Date.compare(date, starts) != :lt and Date.compare(date, ends) == :lt,
      do: standard + 1,
      else: standard
  end

  defp first_sunday(year, month) do
    first = Date.new!(year, month, 1)
    Date.add(first, rem(7 - Date.day_of_week(first), 7))
  end

  defp last_sunday(year, month) do
    last = Date.end_of_month(Date.new!(year, month, 1))
    Date.add(last, -rem(Date.day_of_week(last), 7))
  end
end
