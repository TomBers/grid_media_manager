defmodule GridMediaManager.WeeklyServicesStub do
  alias GridMediaManager.{Repo, Campaigns}
  alias GridMediaManager.Automation.EditorialPlan
  alias GridMediaManager.Campaigns.PostDraft
  alias GridMediaManager.RationalGrid.Explorations
  alias GridMediaManager.Social.Platforms

  def snapshot do
    Process.put(:weekly_snapshots, Process.get(:weekly_snapshots, 0) + 1)
    {:ok, q} = queue()
    {:ok, %{queue: q, evidence: %{}}}
  end

  def proposals(run),
    do:
      {:ok,
       %{
         "stories" =>
           for(
             i <- 1..run.story_count,
             do: %{
               "question" => "What makes a life meaningful #{i}?",
               "rationale" => "A specific philosophical hypothesis, with limited evidence."
             }
           )
       }}

  def queue(_platforms), do: queue()

  def queue do
    {:ok,
     %{
       platforms:
         Map.new(Platforms.ids(), fn p ->
           posts = Process.get({:weekly_queue, p}, [])
           vacancies = max(Process.get(:weekly_vacancies, 1) - length(posts), 0)
           {p, %{posts: posts, scheduled_count: 10 - vacancies, vacancies: vacancies}}
         end)
     }}
  end

  def plan(run, story) do
    {:ok, c} = Explorations.create_campaign(story.exploration_id)

    Repo.insert(
      EditorialPlan.changeset(%EditorialPlan{}, %{
        editorial_batch_id: run.batch_id,
        campaign_id: c.id,
        position: story.position,
        topic: story.question,
        status: "planned",
        hook: story.question
      })
    )
  end

  def copy(_, story) do
    Process.put(:weekly_copy_feedback, if(story, do: story.error, else: nil))
    Process.put(:weekly_copy_calls, Process.get(:weekly_copy_calls, 0) + 1)

    {:ok,
     %{
       "x" => "A clear philosophical tension.",
       "linkedin" => String.duplicate("A substantive argument with a qualification. ", 20),
       "facebook" => String.duplicate("A thoughtful explanation. ", 25),
       "instagram" => "A specific question and explanation.",
       "tiktok" => "A specific question and explanation.",
       "youtube" => "A specific question and explanation.",
       "hook" => "What makes a life meaningful?",
       "idea_card" => "Meaning may depend on more than satisfaction.",
       "cover_search_query" => "person walking in a forest",
       "video_script" => ["One useful idea.", "A concrete tension.", "An honest qualification."]
     }}
  end

  def apply_copy(_, story) do
    if Process.get(:weekly_copy_issue, false) do
      {:error, {:copy_issues, ["Cover hook exceeds 12 words."]}}
    else
      if Process.get(:weekly_apply_failure, false) do
        {:error, :temporary_failure}
      else
        plan = Repo.get!(EditorialPlan, story.plan_id)

        drafts =
          for p <- Platforms.ids() do
            Repo.insert!(
              PostDraft.changeset(%PostDraft{}, %{
                campaign_id: plan.campaign_id,
                platform: p,
                angle: "weekly",
                body: "A clear idea for #{p} with a meaningful qualification.",
                status: "draft"
              })
            )
          end

        {:ok, %{asset_ids: [], draft_ids: Enum.map(drafts, & &1.id)}}
      end
    end
  end

  def frames_ready?(_), do: Process.get(:weekly_frames, true)
  def finish_media(_), do: :ok
  def public?(_), do: {:ok, Process.get(:weekly_public, true)}
  def drafts(story), do: Enum.map(story.review["draft_ids"], &Campaigns.get_post_draft!/1)

  def media_fingerprint(_), do: Process.get(:weekly_media_fingerprint, "stable")

  def send(delivery) do
    Process.put(:weekly_send_calls, Process.get(:weekly_send_calls, 0) + 1)
    d = Campaigns.get_post_draft!(delivery.post_draft_id)

    post = %{
      id: "buffer-#{d.id}",
      text: d.body,
      due_at: DateTime.to_iso8601(delivery.scheduled_for)
    }

    Process.put({:weekly_queue, d.platform}, [post | Process.get({:weekly_queue, d.platform}, [])])

    if Process.get(:weekly_uncertain, false), do: {:error, :closed}, else: restore(delivery, post)
  end

  def restore(delivery, post),
    do:
      Campaigns.update_post_draft(Campaigns.get_post_draft!(delivery.post_draft_id), %{
        status: "scheduled",
        external_post_id: post.id,
        scheduled_for: delivery.scheduled_for
      })
end
