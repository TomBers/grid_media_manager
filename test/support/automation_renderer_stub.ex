defmodule GridMediaManager.AutomationRendererStub do
  @behaviour GridMediaManager.Automation.Renderer

  @impl true
  def render(_campaign, asset, opts) do
    case Keyword.get(opts, :status, :complete) do
      :complete -> {:ok, %{output_type: :test, asset_id: asset.id}}
      :pending -> {:pending, %{required_indexes: [1], missing_indexes: [1]}}
      :failed -> {:error, :test_renderer_failed}
    end
  end
end
