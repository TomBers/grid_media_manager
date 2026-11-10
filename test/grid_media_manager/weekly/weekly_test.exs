defmodule GridMediaManager.WeeklyTest do
  use GridMediaManager.DataCase
  alias GridMediaManager.{Weekly, Repo}
  alias GridMediaManager.Weekly.{Run, Delivery}
  alias GridMediaManager.RationalGrid.Explorations
  alias GridMediaManager.WeeklyServicesStub, as: Services
  import GridMediaManager.RationalGridMCPHelpers, only: [connected: 0]

  setup do
    connected()
    :ok
  end

  defp tick(id) do
    r = Repo.get!(Run, id)

    Weekly.save(r, %{
      next_run_at: DateTime.add(DateTime.utc_now(), -1) |> DateTime.truncate(:second)
    })

    Weekly.process_next(Services)
    Weekly.get!(id)
  end

  defp run do
    {:ok, r} = Weekly.create(Weekly.default_attrs())
    r
  end

  defp complete_grid(r) do
    for s <- r.stories, s.exploration_id do
      e = Explorations.get!(s.exploration_id)

      if e.status == "queued" do
        payload = %{
          "metadata" => %{
            "id" => "weekly-#{s.id}",
            "title" => s.question,
            "url" => "https://rationalgrid.ai/g/weekly-#{s.id}"
          },
          "graph" => %{"nodes" => [], "edges" => []}
        }

        Weekly.save(e, %{
          status: "review",
          payload: payload,
          result: %{"grid" => %{"id" => "weekly-#{s.id}"}}
        })
      end
    end
  end

  defp ready do
    r = run()

    Enum.reduce(1..20, r, fn _, r ->
      if r.status == "ready" do
        r
      else
        r = tick(r.id)
        complete_grid(r)
        Weekly.get!(r.id)
      end
    end)
  end

  test "one active run makes repeated preparation idempotent" do
    first = run()
    assert {:ok, second} = Weekly.create(Weekly.default_attrs())
    assert first.id == second.id
    assert Repo.aggregate(Run, :count) == 1
  end

  test "invalid dates cannot create a run" do
    attrs = %{Weekly.default_attrs() | end_date: Date.add(Date.utc_today(), 20)}
    assert {:error, %Ecto.Changeset{}} = Weekly.create(attrs)
    assert Repo.aggregate(Run, :count) == 0
  end

  test "full queues complete without proposals or paid generation" do
    Process.put(:weekly_vacancies, 0)
    r = run() |> then(&tick(&1.id))
    assert r.status == "completed"
    assert r.story_count == 0
    assert r.stories == []
    assert Process.get(:weekly_copy_calls, 0) == 0
  end

  test "saved run reaches reviewed packages and verifies every scheduled ID and time" do
    r = ready()
    assert r.status == "ready"
    assert length(r.stories) == 1
    assert Process.get(:weekly_copy_calls) == 1
    assert {:ok, _} = Weekly.schedule(r.id, Services)
    assert {:ok, _} = Weekly.schedule(r.id, Services)
    assert Repo.aggregate(Delivery, :count) == 6
    r = Enum.reduce(1..9, r, fn _, r -> tick(r.id) end)
    assert r.status == "completed"
    assert Enum.all?(r.deliveries, &(&1.status == "verified"))
    assert Process.get(:weekly_send_calls) == 6
  end

  test "model output survives an interrupted application step" do
    r = run()

    r =
      Enum.reduce(1..6, r, fn _, r ->
        r = tick(r.id)
        complete_grid(r)
        Weekly.get!(r.id)
      end)

    assert r.status == "copying"
    Process.put(:weekly_apply_failure, true)
    r = tick(r.id)
    assert map_size(hd(r.stories).copy) > 0
    assert Process.get(:weekly_copy_calls) == 1
    Process.put(:weekly_apply_failure, false)
    r = tick(r.id)
    assert hd(r.stories).status == "copied"
    assert Process.get(:weekly_copy_calls) == 1
  end

  test "publication gates scheduling and is checked again immediately before approval" do
    r = ready()
    Process.put(:weekly_public, false)
    assert {:error, :publication_or_queue_check_failed} = Weekly.schedule(r.id, Services)
    assert Repo.aggregate(Delivery, :count) == 0
    assert Process.get(:weekly_send_calls, 0) == 0
  end

  test "uncertain writes reconcile the remotely created post rather than send twice" do
    r = ready()
    Process.put(:weekly_uncertain, true)
    {:ok, _} = Weekly.schedule(r.id, Services)
    r = Enum.reduce(1..16, r, fn _, r -> tick(r.id) end)
    assert r.status == "completed"
    assert Process.get(:weekly_send_calls) == 6
    assert Enum.all?(r.deliveries, &(&1.status == "verified"))
  end

  test "a crash after send intent cannot trigger a blind resubmission" do
    r = ready()
    {:ok, _} = Weekly.schedule(r.id, Services)
    r = Weekly.get!(r.id)
    d = hd(r.deliveries)

    Weekly.save(d, %{
      status: "sending",
      attempted_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })

    r = Enum.reduce(1..4, r, fn _, r -> tick(r.id) end)
    assert r.status == "attention"
    assert Process.get(:weekly_send_calls, 0) == 0
    Weekly.resume(r.id)
    tick(r.id)
    assert Process.get(:weekly_send_calls, 0) == 0
  end

  test "live queue vacancies bound the actual deliveries" do
    r = ready()
    Process.put(:weekly_vacancies, 0)
    assert {:ok, _} = Weekly.schedule(r.id, Services)
    assert Repo.aggregate(Delivery, :count) == 0
  end

  test "unexpired worker leases exclude another claim" do
    r = run()

    Weekly.save(r, %{
      lease_until: DateTime.add(DateTime.utc_now(), 300) |> DateTime.truncate(:second)
    })

    assert Weekly.process_next(Services) == :idle
    assert Process.get(:weekly_snapshots, 0) == 0

    Weekly.save(Repo.get!(Run, r.id), %{
      lease_until: DateTime.add(DateTime.utc_now(), -1) |> DateTime.truncate(:second)
    })

    assert tick(r.id).status == "discovering"
  end

  test "rendering waits for saved browser frames and then for public grids" do
    Process.put(:weekly_frames, false)
    Process.put(:weekly_public, false)
    r = run()

    r =
      Enum.reduce(1..15, r, fn _, r ->
        r = tick(r.id)
        complete_grid(r)
        Weekly.get!(r.id)
      end)

    assert r.status == "rendering"
    Process.put(:weekly_frames, true)
    r = Enum.reduce(1..4, r, fn _, r -> tick(r.id) end)
    assert r.status == "publication"
    assert hd(r.stories).public == false
    Process.put(:weekly_public, true)
    assert tick(r.id).status == "ready"
  end

  test "production corrections are bounded to the affected story" do
    r = run()

    r =
      Enum.reduce(1..6, r, fn _, r ->
        r = tick(r.id)
        complete_grid(r)
        Weekly.get!(r.id)
      end)

    Process.put(:weekly_copy_issue, true)
    r = tick(r.id)
    assert Process.get(:weekly_copy_calls) == 1
    assert r.status == "copying"
    r = tick(r.id)
    assert r.status == "attention"
    assert Process.get(:weekly_copy_calls) == 2
    assert hd(r.stories).error =~ "Cover hook"
    Process.put(:weekly_copy_issue, false)
    Weekly.regenerate_copy(r.id, hd(r.stories).id)
    r = tick(r.id)
    assert hd(r.stories).status == "copied"
    assert Process.get(:weekly_copy_calls) == 3
    assert Process.get(:weekly_copy_feedback) =~ "Cover hook"
  end

  test "media changes after approval prevent submission" do
    r = ready()
    {:ok, _} = Weekly.schedule(r.id, Services)
    Process.put(:weekly_media_fingerprint, "edited after approval")
    assert tick(r.id).status == "attention"
    assert Process.get(:weekly_send_calls, 0) == 0
  end

  test "cancellation releases the active run but cannot interrupt a leased step" do
    r = run()
    assert {:ok, %{status: "cancelled"}} = Weekly.cancel(r.id)
    next = run()
    assert next.id != r.id

    Weekly.save(next, %{
      lease_until: DateTime.add(DateTime.utc_now(), 300) |> DateTime.truncate(:second)
    })

    assert {:error, :submission_in_progress} = Weekly.cancel(next.id)
  end

  test "copy changed after approval stops before touching Buffer" do
    r = ready()
    {:ok, _} = Weekly.schedule(r.id, Services)
    r = Weekly.get!(r.id)
    d = hd(r.deliveries)

    Weekly.save(GridMediaManager.Campaigns.get_post_draft!(d.post_draft_id), %{
      body: "Changed after approval."
    })

    assert tick(r.id).status == "attention"
    assert Process.get(:weekly_send_calls, 0) == 0
  end

  test "explicit partial-source review preserves failed status and does not regenerate" do
    GridMediaManager.RationalGridMCPHelpers.setup_http()
    r = run() |> then(&tick(&1.id)) |> then(&tick(&1.id)) |> then(&tick(&1.id))
    s = hd(r.stories)
    e = Explorations.get!(s.exploration_id)

    Weekly.save(e, %{
      status: "failed",
      result: %{"status" => "failed", "grid" => %{"id" => "partial-source"}}
    })

    r = tick(r.id)
    assert r.status == "attention"

    GridMediaManager.RationalGridMCPHelpers.stub(fn conn ->
      GridMediaManager.RationalGridMCPHelpers.rpc(conn, fn "read_grid", _ ->
        %{
          "grid" => %{
            "id" => "partial-source",
            "title" => s.question,
            "url" => "https://rationalgrid.ai/g/partial-source",
            "visibility" => "private"
          },
          "nodes" => [
            %{
              "id" => "2",
              "class" => "answer",
              "content" => String.duplicate("A substantive available answer. ", 12)
            }
          ],
          "edges" => [],
          "next_offset" => nil
        }
      end)
    end)

    assert {:ok, _} = Weekly.use_partial(r.id, s.id)
    e = Explorations.get!(e.id)
    assert e.status == "partial_review"
    assert e.result["status"] == "failed"
    assert e.payload["metadata"]["partial_generation"] == true
    assert tick(r.id).status == "planning"
  end
end
