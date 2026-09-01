defmodule GridMediaManager.EditorStub do
  @behaviour GridMediaManager.Automation.Editor

  @impl true
  def assess(_plan, _campaign, assets, drafts) do
    {:ok,
     %{
       "verdict" => "revise",
       "overall_score" => 74,
       "thematic_consistency_score" => 82,
       "interest_score" => 71,
       "shareability_score" => 68,
       "summary" =>
         "Reviewed #{length(assets)} assets and #{length(drafts)} drafts; the hook could be more specific.",
       "strengths" => ["The formats share one central idea."],
       "concerns" => ["The opening is generic."],
       "recommendations" => ["Lead with the most surprising implication."]
     }}
  end
end
