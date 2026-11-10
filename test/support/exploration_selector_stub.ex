defmodule GridMediaManager.ExplorationSelectorStub do
  def propose_exploration(_theme, feedback, _sources) do
    if is_map(feedback) do
      {:ok,
       %{
         "kind" => "new_question",
         "question" => "When does evidence change minds?",
         "rationale" => "An editorial hypothesis; there is too little performance evidence.",
         "grid_id" => "",
         "parent_node_id" => ""
       }}
    end
  end
end
