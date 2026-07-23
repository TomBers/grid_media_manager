defmodule GridMediaManager.AutomationTest do
  use ExUnit.Case, async: true

  alias GridMediaManager.Automation

  @scheduled_for ~U[2026-08-20 15:30:00Z]

  test "preview mode returns a review package without scheduling posts" do
    caller = self()

    builder = fn source ->
      send(caller, {:built, source})

      {:ok,
       %{
         campaign: %{id: 12, title: "A test grid"},
         grid: %{source: source, title: "A test grid"},
         candidates: [],
         assets: [%{id: 34}]
       }}
    end

    assert {:ok, result} =
             Automation.preview_grid("a-test-grid",
               scheduled_for: @scheduled_for,
               builder: builder
             )

    assert_receive {:built, "a-test-grid"}
    assert result.mode == :preview
    assert result.scheduled_for == @scheduled_for
    assert result.scheduled == []
    assert result.failed == []
    assert result.assets == [%{id: 34}]
  end
end
