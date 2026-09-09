defmodule GridMediaManager.Automation.EditorPayloadTest do
  use ExUnit.Case, async: true
  alias GridMediaManager.Automation.LLMEditor
  alias GridMediaManager.Campaigns.{Campaign, MediaAsset}

  test "review sees selected frames rather than unused text or deselected slides" do
    asset = %MediaAsset{
      kind: "curated_carousel",
      text: "Unused source excerpt",
      metadata: %{
        "slides" => [%{"title" => "Opening"}, %{"title" => "Deselected"}, %{"title" => "Closing"}],
        "selected_slide_indexes" => [1, 3]
      }
    }

    payload =
      LLMEditor.package_payload(
        %{topic: "Topic", hook: "Hook", rationale: "Reason"},
        %Campaign{title: "Source"},
        [asset],
        []
      )

    assert [%{text: nil, slides: [%{"title" => "Opening"}, %{"title" => "Closing"}]}] =
             payload.assets
  end
end
