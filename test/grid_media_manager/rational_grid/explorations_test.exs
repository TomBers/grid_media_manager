defmodule GridMediaManager.RationalGrid.ExplorationsTest do
  use GridMediaManager.DataCase
  import GridMediaManager.RationalGridMCPHelpers
  alias GridMediaManager.RationalGrid.{Explorations, MCP}

  setup do
    setup_http()
    connected()
    :ok
  end

  test "recommendations persist the supplied evidence with the editorial hypothesis" do
    previous = Application.get_env(:grid_media_manager, :exploration_selector)

    Application.put_env(
      :grid_media_manager,
      :exploration_selector,
      GridMediaManager.ExplorationSelectorStub
    )

    on_exit(fn ->
      if previous,
        do: Application.put_env(:grid_media_manager, :exploration_selector, previous),
        else: Application.delete_env(:grid_media_manager, :exploration_selector)
    end)

    assert {:ok, e} = Explorations.recommend("Evidence")
    assert e.status == "proposed"
    assert e.evidence["theme"] == "Evidence"
    assert e.evidence["feedback"]["x"]["sample_size"] == 0
    assert e.tool == "explore_question"
  end

  test "progress polls the operation without repeating the write" do
    {:ok, e} =
      Explorations.propose(
        %{question: "Why this result?", rationale: "Follow a consequential question."},
        %{}
      )

    Explorations.start(e.id)

    stub(fn conn ->
      rpc(conn, fn
        "explore_question", _ ->
          send(self(), :created)
          %{"request_id" => e.request_id, "status" => "generating", "grid" => grid()}

        "get_operation", _ ->
          %{"request_id" => e.request_id, "status" => "completed", "grid" => grid()}

        "read_grid", args ->
          page(args["offset"])
      end)
    end)

    assert {:ok, %{status: "generating"}} = Explorations.process_next()
    assert_receive :created
    e = Explorations.get!(e.id)

    Repo.update!(
      Ecto.Changeset.change(e,
        next_run_at: DateTime.add(DateTime.utc_now(), -1) |> DateTime.truncate(:second)
      )
    )

    assert {:ok, %{status: "review"}} = Explorations.process_next()
    refute_receive :created
  end

  test "a proposed private-grid question checks the target before editing" do
    {:ok, e} =
      Explorations.propose(
        %{question: "What would falsify this?", rationale: "Test the explanation."},
        %{},
        %{"grid_id" => "private-grid", "parent_node_id" => "node-1", "kind" => "question"}
      )

    Explorations.start(e.id)

    stub(fn conn ->
      rpc(conn, fn
        "read_grid", args ->
          page(args["offset"])

        "add_grid_idea", args ->
          assert args["parent_node_id"] == "node-1"
          assert args["content"] == e.question
          assert args["request_id"] == e.request_id
          %{"request_id" => e.request_id, "status" => "completed", "grid" => grid()}
      end)
    end)

    assert {:ok, %{status: "review"}} = Explorations.process_next()
  end

  test "private exploration follows pages and campaign creation is idempotent with provenance" do
    evidence = %{"source_grid_id" => "source-1", "sample_size" => 3}

    {:ok, e} =
      Explorations.propose(
        %{question: "Can evidence change minds?", rationale: "Test a promising theme."},
        evidence
      )

    stub(fn conn ->
      rpc(conn, fn
        "explore_question", args ->
          assert args["request_id"] == e.request_id
          %{"request_id" => e.request_id, "status" => "completed", "grid" => grid()}

        "read_grid", args ->
          assert args["grid_id"] == "private-grid"
          page(args["offset"])
      end)
    end)

    assert {:ok, _} = Explorations.start(e.id)
    assert {:ok, _} = Explorations.start(e.id)
    assert {:ok, %{status: "review"}} = Explorations.process_next()
    e = Explorations.get!(e.id)
    assert length(e.payload["graph"]["nodes"]) == 2
    assert length(e.payload["graph"]["edges"]) == 1
    assert e.payload["metadata"]["visibility"] == "private"
    assert {:ok, campaign} = Explorations.create_campaign(e.id)
    assert {:ok, same} = Explorations.create_campaign(e.id)
    assert same.id == campaign.id
    assert Explorations.get!(e.id).campaign_id == campaign.id
    assert Explorations.get!(e.id).evidence == evidence
  end

  test "uncertain writes replay exactly the persisted arguments and UUID" do
    {:ok, e} =
      Explorations.propose(
        %{question: "Why this result?", rationale: "Compare weak results."},
        %{}
      )

    {:ok, e} = Explorations.start(e.id)

    stub(fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      args = Jason.decode!(body)["params"]["arguments"]
      assert args == e.arguments
      send(self(), {:write, args})
      Plug.Conn.send_resp(conn, 503, "unavailable")
    end)

    assert {:ok, %{attempts: 1}} = Explorations.process_next()
    assert_receive {:write, args}
    e = Explorations.get!(e.id)

    Repo.update!(
      Ecto.Changeset.change(e,
        next_run_at: DateTime.add(DateTime.utc_now(), -1) |> DateTime.truncate(:second)
      )
    )

    assert {:ok, _} = Explorations.process_next()
    assert_receive {:write, ^args}
  end

  test "failed generation is terminal and never silently starts another grid" do
    {:ok, e} =
      Explorations.propose(
        %{question: "Why this result?", rationale: "Investigate failure."},
        %{}
      )

    Explorations.start(e.id)

    stub(fn conn ->
      rpc(conn, fn "explore_question", _ ->
        %{"request_id" => e.request_id, "status" => "failed", "grid" => grid()}
      end)
    end)

    assert {:ok, %{status: "failed"}} = Explorations.process_next()
    assert {:ok, %{status: "failed"}} = Explorations.retry(e.id)
    assert {:ok, :idle} = Explorations.process_next()
    assert {:error, :not_ready} = Explorations.create_campaign(e.id)
  end

  test "private grid access denial cannot import a campaign" do
    stub(fn conn -> Plug.Conn.send_resp(conn, 403, "denied") end)
    assert {:error, :access_denied} = MCP.read_all("private-grid")
  end

  test "rejects looping pagination" do
    stub(fn conn -> rpc(conn, fn "read_grid", _ -> %{page() | "next_offset" => 0} end) end)
    assert {:error, :invalid_pagination} = MCP.read_all("private-grid")
  end

  test "401 renewal retries the identical MCP arguments" do
    stub(fn conn ->
      case conn.request_path do
        "/oauth/token" ->
          Req.Test.json(conn, %{
            access_token: "access-2",
            refresh_token: "refresh-2",
            expires_in: 3600
          })

        "/mcp" ->
          if Plug.Conn.get_req_header(conn, "authorization") == ["Bearer access-1"] do
            Plug.Conn.send_resp(conn, 401, "expired")
          else
            rpc(conn, fn "get_operation", args ->
              assert args == %{"request_id" => "request-1"}
              %{"status" => "completed"}
            end)
          end
      end
    end)

    assert {:ok, %{"status" => "completed"}} =
             MCP.call("get_operation", %{"request_id" => "request-1"})
  end
end
