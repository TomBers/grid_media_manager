defmodule GridMediaManager.Weekly.Worker do
  @moduledoc false
  use GenServer
  require Logger
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  @impl true
  def init(opts) do
    if Keyword.get(opts, :enabled, true), do: Process.send_after(self(), :work, 5_000)
    {:ok, nil}
  end

  @impl true
  def handle_info(:work, nil) do
    task =
      Task.Supervisor.async_nolink(GridMediaManager.Weekly.Tasks, fn ->
        GridMediaManager.Weekly.process_next()
      end)

    timer = Process.send_after(self(), {:timeout, task.ref}, 120_000)
    {:noreply, {task, timer}}
  end

  def handle_info({ref, _result}, {%Task{ref: ref}, timer}) do
    Process.demonitor(ref, [:flush])
    Process.cancel_timer(timer)
    Process.send_after(self(), :work, 2_000)
    {:noreply, nil}
  end

  def handle_info({:DOWN, ref, :process, _, _}, {%Task{ref: ref}, timer}) do
    Process.cancel_timer(timer)
    Logger.warning("Weekly step stopped; its saved lease will expire and the run can resume.")
    Process.send_after(self(), :work, 5_000)
    {:noreply, nil}
  end

  def handle_info({:timeout, ref}, {%Task{ref: ref} = task, _timer}) do
    Task.shutdown(task, :brutal_kill)

    Logger.warning(
      "Weekly step exceeded its two-minute limit. Saved progress and send intents are retained."
    )

    Process.send_after(self(), :work, 5_000)
    {:noreply, nil}
  end

  def handle_info(_, state), do: {:noreply, state}
end
