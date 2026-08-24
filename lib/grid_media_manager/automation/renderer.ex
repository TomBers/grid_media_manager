defmodule GridMediaManager.Automation.Renderer do
  @moduledoc """
  Finalizes generated media assets without owning editorial or visual composition.

  Implementations return completed output details, report that browser artifacts are
  still pending, or fail with a reason that the batch orchestrator can preserve.
  """

  alias GridMediaManager.Campaigns.Campaign
  alias GridMediaManager.Campaigns.MediaAsset

  @type details :: map()
  @type result :: {:ok, details()} | {:pending, details()} | {:error, term()}

  @callback render(%Campaign{}, %MediaAsset{}, keyword()) :: result()
end
