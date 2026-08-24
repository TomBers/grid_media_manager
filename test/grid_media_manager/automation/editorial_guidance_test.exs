defmodule GridMediaManager.Automation.EditorialGuidanceTest do
  use ExUnit.Case, async: true

  alias GridMediaManager.Automation.EditorialGuidance

  test "short-video guidance constrains source selection and duration" do
    guidance = compact(EditorialGuidance.format_selection())

    assert guidance =~ "select only two or three distinct moments"
    assert guidance =~ "never a generic grid overview"
    assert guidance =~ "roughly 25–40 seconds"
    assert guidance =~ "never more than 45 seconds"
    assert guidance =~ "structured answer can expand into several frames"
  end

  test "story guidance rejects visible source scaffolding and repetition" do
    guidance = compact(EditorialGuidance.story_selection())

    assert guidance =~ "formatting labels"
    assert guidance =~ "Select the fewest moments needed"
    assert guidance =~ "never select both a grid overview"
  end

  test "platform guidance asks LinkedIn and Facebook posts to develop the argument" do
    guidance = compact(EditorialGuidance.story_selection())

    assert guidance =~ "substantive posts, not merely longer captions"
    assert guidance =~ "central thesis, the reasoning or evidence behind it"
    assert guidance =~ "LinkedIn copy may use most of its 3,000-character allowance"
    assert guidance =~ "Facebook may retain the fuller explanation"
    assert guidance =~ "Do not apply short-video frame density"
  end

  defp compact(guidance), do: String.replace(guidance, ~r/\s+/u, " ")
end
