defmodule GridMediaManager.Weekly.ValidationTest do
  use ExUnit.Case, async: true
  alias GridMediaManager.Weekly.{Validation, Schedule, Evidence}

  test "production checks catch scaffolding, corrupted text, exclusions and excessive pacing" do
    copy = %{
      "x" => "Hook: An interesting question.",
      "linkedin" => "Too short.",
      "facebook" => "Too short.",
      "instagram" => "AI systems matter.",
      "tiktok" => "A strange character 価.",
      "youtube" => "A complete argument.",
      "hook" => "A clear question?",
      "idea_card" => "A useful claim.",
      "cover_search_query" => "a person reading",
      "video_script" => [String.duplicate("word ", 23), "One thought.", "Another thought."]
    }

    issues = Validation.copy_issues(copy, "Philosophy unrelated to AI")
    assert "Remove drafting labels." in issues
    assert "Unexpected or corrupted text in English copy." in issues
    assert "Copy violates the exclusion of AI topics." in issues
    assert "Video needs three complete beats of at most 22 words." in issues
  end

  test "time windows require a meaningful sample and engagement, never just an outlier" do
    data = %{
      "x" => %{
        time_bins: [
          %{sample_size: 1, actions: 20, utc_start_hour: 9},
          %{sample_size: 6, actions: 8, utc_start_hour: 21}
        ]
      }
    }

    assert Evidence.windows(data)["x"] == ["22:00", "23:00"]
    assert Evidence.windows(%{})["tiktok"] == Evidence.defaults()["tiktok"]
  end

  test "date range, daily maximum and existing queues constrain UTC slots" do
    run = %{
      windows: %{"x" => ["19:00", "23:00"]},
      start_date: ~D[2026-11-11],
      end_date: ~D[2026-11-12]
    }

    slots =
      Schedule.slots("x", 10, [%{due_at: "2026-11-11T18:50:00Z"}], run, ~U[2026-11-10 12:00:00Z])

    assert Enum.map(slots, & &1.scheduled_for) == [
             ~U[2026-11-11 23:00:00Z],
             ~U[2026-11-12 19:00:00Z],
             ~U[2026-11-12 23:00:00Z]
           ]
  end

  test "malformed model output produces blocking issues rather than crashing" do
    assert Validation.copy_issues(%{"video_script" => "invalid", "hook" => %{}}, "No AI") != []

    assert Validation.normalise(%{"x" => "Hook: A complete question?"})["x"] ==
             "A complete question?"

    assert Validation.normalise(%{
             "x" => "Can comfort constrain choice? Quick hook: comfort has two sides."
           })["x"] ==
             "Can comfort constrain choice? Comfort has two sides."
  end
end
