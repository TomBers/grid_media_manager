defmodule GridMediaManager.Weekly.Schedule do
  @moduledoc "Persists bounded UTC test slots while preserving the live queue."
  def slots(platform, count, queued, run, now \\ DateTime.utc_now()) do
    windows = Map.fetch!(run.windows, platform)

    occupied =
      queued
      |> Enum.flat_map(fn post ->
        case DateTime.from_iso8601(post.due_at || "") do
          {:ok, dt, _} -> [dt]
          _ -> []
        end
      end)
      |> Enum.group_by(&DateTime.to_date/1)

    Date.range(run.start_date, run.end_date)
    |> Enum.flat_map(fn date ->
      day =
        windows
        |> Enum.with_index()
        |> Enum.map(fn {time, i} ->
          {:ok, t} = Time.from_iso8601(time <> ":00")

          %{
            scheduled_for: DateTime.new!(date, t),
            window: if(i == 0, do: "first", else: "second")
          }
        end)

      day =
        case Map.get(occupied, date, []) do
          [] ->
            day

          [taken] ->
            nearest = Enum.min_by(day, &abs(DateTime.diff(&1.scheduled_for, taken)))
            Enum.reject(day, &(&1.window == nearest.window))

          _ ->
            []
        end

      Enum.filter(day, &(DateTime.compare(&1.scheduled_for, DateTime.add(now, 3600)) == :gt))
    end)
    |> Enum.take(count)
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
