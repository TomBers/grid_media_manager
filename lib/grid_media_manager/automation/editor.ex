defmodule GridMediaManager.Automation.Editor do
  @moduledoc """
  Reviews a complete generated package for editorial quality before publishing.
  """

  @callback assess(struct(), struct(), [struct()], [struct()]) ::
              {:ok, map()} | {:error, term()}
end
