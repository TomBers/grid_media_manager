defmodule GridMediaManager.RationalGrid.ExplorationWorker do
  @moduledoc "Database-backed job runner. Locked jobs survive process or server restarts."
  use GenServer

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  @impl true
  def init(opts) do
    if Keyword.get(opts, :enabled, true), do: Process.send_after(self(), :work, 5_000)
    {:ok, nil}
  end

  @impl true
  def handle_info(:work, state) do
    try do
      GridMediaManager.RationalGrid.Explorations.process_next()
    rescue
      _ -> :ok
    end

    Process.send_after(self(), :work, 5_000)
    {:noreply, state}
  end
end
