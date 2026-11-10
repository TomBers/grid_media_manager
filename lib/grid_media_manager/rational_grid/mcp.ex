defmodule GridMediaManager.RationalGrid.MCP do
  @moduledoc "Stateless Streamable HTTP MCP transport. Writes require a previously persisted UUID."
  alias GridMediaManager.RationalGrid.{Accounts, HTTP}

  @write_tools ~w(explore_question create_grid add_grid_idea apply_grid_action)
  @read_tools ~w(get_operation read_grid list_my_grids search_public_grids)

  def call(tool, arguments) when tool in @write_tools do
    case Ecto.UUID.cast(arguments["request_id"]) do
      {:ok, _} -> authorized_call(tool, arguments)
      _ -> {:error, :request_id_required}
    end
  end

  def call(tool, arguments) when tool in @read_tools, do: authorized_call(tool, arguments)

  def read_public_grid(grid_id) do
    rpc("tools/call", %{name: "read_grid", arguments: %{grid_id: grid_id, limit: 1}}, nil)
  end

  def read_all(grid_id),
    do: read_page(grid_id, 0, [], [], MapSet.new(), System.monotonic_time(:second) + 60)

  defp read_page(id, offset, nodes, edges, seen, deadline) do
    with true <- System.monotonic_time(:second) < deadline,
         false <- MapSet.member?(seen, offset),
         true <- MapSet.size(seen) < 1000,
         {:ok,
          %{
            "grid" => %{"id" => ^id},
            "nodes" => page_nodes,
            "edges" => page_edges,
            "next_offset" => next
          } = page} <-
           call("read_grid", %{"grid_id" => id, "limit" => 50, "offset" => offset}),
         true <- is_list(page_nodes) and is_list(page_edges) do
      nodes = nodes ++ page_nodes
      edges = edges ++ page_edges

      if is_nil(next) do
        {:ok, %{page | "nodes" => Enum.uniq_by(nodes, & &1["id"]), "edges" => Enum.uniq(edges)}}
      else
        if is_integer(next) and next > offset do
          read_page(id, next, nodes, edges, MapSet.put(seen, offset), deadline)
        else
          {:error, :invalid_pagination}
        end
      end
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_grid_response}
    end
  end

  defp authorized_call(tool, args) do
    with {:ok, token} <- Accounts.access_token() do
      case rpc("tools/call", %{name: tool, arguments: args}, token) do
        {:error, :unauthorized} ->
          with {:ok, next} <- Accounts.access_token(token) do
            rpc("tools/call", %{name: tool, arguments: args}, next)
          end

        result ->
          result
      end
    end
  end

  defp rpc(method, params, token) do
    id = Ecto.UUID.generate()

    headers = [
      {"accept", "application/json, text/event-stream"},
      {"mcp-protocol-version", "2025-03-26"}
    ]

    headers = if token, do: [{"authorization", "Bearer " <> token} | headers], else: headers

    case HTTP.request(:post, "/mcp",
           headers: headers,
           json: %{jsonrpc: "2.0", id: id, method: method, params: params}
         ) do
      {:ok, %{status: 401}} -> {:error, :unauthorized}
      {:ok, %{status: 403}} -> {:error, :access_denied}
      {:ok, %{status: status, body: body}} when status in 200..299 -> decode(body, id)
      {:ok, %{status: status}} -> {:error, {:http_error, status}}
      {:error, _} -> {:error, :transport_unavailable}
    end
  end

  defp decode(body, id) when is_binary(body) do
    decoded =
      case Jason.decode(body) do
        {:ok, data} ->
          data

        _ ->
          body
          |> String.split(~r/\r?\n\r?\n/)
          |> Enum.find_value(fn event ->
            data =
              event
              |> String.split(~r/\r?\n/)
              |> Enum.filter(&String.starts_with?(&1, "data:"))
              |> Enum.map_join("\n", &String.trim_leading(String.replace_prefix(&1, "data:", "")))

            case Jason.decode(data) do
              {:ok, %{"id" => ^id} = data} -> data
              _ -> nil
            end
          end)
      end

    decode(decoded, id)
  end

  defp decode(%{"id" => id, "result" => %{"isError" => true} = result}, id) do
    challenges = get_in(result, ["_meta", "mcp/www_authenticate"]) || []

    cond do
      Enum.any?(challenges, &String.contains?(&1, "insufficient_scope")) ->
        {:error, :access_denied}

      challenges != [] ->
        {:error, :unauthorized}

      Enum.any?(result["content"] || [], fn item ->
        item["type"] == "text" and String.contains?(item["text"] || "", "rate limited")
      end) ->
        {:error, :rate_limited}

      Enum.any?(result["content"] || [], fn item ->
        item["type"] == "text" and
            String.contains?(item["text"] || "", [
              "RationalGrid is unavailable or returned an invalid response",
              "RationalGrid could not complete the request. Please try again later."
            ])
      end) ->
        {:error, :transport_unavailable}

      true ->
        {:error, :tool_failed}
    end
  end

  defp decode(%{"id" => id, "result" => %{"structuredContent" => data}}, id) when is_map(data),
    do: {:ok, data}

  defp decode(%{"id" => id, "result" => %{"content" => content}}, id) when is_list(content) do
    case Enum.find(content, &(&1["type"] == "text")) do
      %{"text" => text} ->
        case Jason.decode(text) do
          {:ok, data} when is_map(data) -> {:ok, data}
          _ -> {:error, :invalid_tool_response}
        end

      _ ->
        {:error, :invalid_tool_response}
    end
  end

  defp decode(%{"error" => _}, _), do: {:error, :rpc_error}
  defp decode(_, _), do: {:error, :invalid_tool_response}
end
