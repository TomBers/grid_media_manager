defmodule GridMediaManager.Studio.VisualDirectionTest do
  use ExUnit.Case, async: true

  alias GridMediaManager.Automation.EditorialPlan
  alias GridMediaManager.Studio.VisualDirection

  test "an explicit style override survives a revised model recommendation" do
    plan = %EditorialPlan{
      selection_details: %{
        "visual_style" => "minimal_light",
        "visual_style_override" => "editorial_dark"
      }
    }

    assert VisualDirection.style_for_plan(plan, "newsprint") == "editorial_dark"
  end

  test "plans without an override keep the recommended style and saved fallback" do
    plan = %EditorialPlan{selection_details: %{"visual_style" => "minimal_light"}}
    assert VisualDirection.style_for_plan(plan, "editorial_dark") == "minimal_light"
    assert VisualDirection.style_for_plan(%EditorialPlan{}, "minimal_dark") == "minimal_dark"
  end
end
