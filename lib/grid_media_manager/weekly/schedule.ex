defmodule GridMediaManager.Weekly.Schedule do
  @moduledoc "Picks one UTC slot per free day while preserving the live queue."
  def slots(platform, count, queued, run, now \\ DateTime.utc_now()) do
    [time | _] = Map.fetch!(run.windows, platform)
    {:ok, time} = Time.from_iso8601(time <> ":00")

    occupied =
      queued
      |> Enum.flat_map(fn post ->
        case DateTime.from_iso8601(post.due_at || "") do
          {:ok, dt, _} -> [DateTime.to_date(dt)]
          _ -> []
        end
      end)
      |> MapSet.new()

    Date.range(run.start_date, run.end_date)
    |> Enum.reject(&MapSet.member?(occupied, &1))
    |> Enum.map(&DateTime.new!(&1, time))
    |> Enum.filter(&(DateTime.compare(&1, DateTime.add(now, 3600)) == :gt))
    |> Enum.take(count)
    |> Enum.map(&%{scheduled_for: &1, window: "first"})
  end

  def match(post, delivery, draft) do
    with true <- String.trim(post.text || "") == String.trim(draft.body),
         {:ok, due, _} <- DateTime.from_iso8601(post.due_at || "") do
      DateTime.compare(due, delivery.scheduled_for) == :eq
    else
      _ -> false
    end
  end
end
