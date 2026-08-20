# One-Week Content Runbook for Future Agents

This is the efficient path for creating and scheduling a week of RationalGrid content. Use it as a checklist and preserve completed work if a session is interrupted.

## 1. Establish the exact workload

Start with read-only checks:

1. Confirm today's date, timezone, requested start date, and number of days.
2. Query Buffer for every configured channel and count only currently queued posts.
3. Treat 10 queued posts per channel as the maximum. Calculate vacancies before generating anything.
4. Leave published posts untouched. Record the external IDs and `dueAt` values of queued posts that may need editing.
5. Fetch recent Buffer performance data once. Summarise the strongest topics, hooks, formats, weekdays, and posting times; do not repeatedly call the API for the same analysis.

For a standard full week, aim for one coordinated topic per day:

- One short-form video adapted for Instagram, TikTok, and YouTube Shorts.
- One text/image treatment adapted for Facebook, LinkedIn, and X.

If a channel has fewer vacancies, generate only what can be scheduled.

## 2. Select the week's topics in one batch

Load candidate grid content and metadata before asking the LLM to decide. Distinguish human questions, highlights, and AI answers using node metadata.

Make one structured LLM selection call for the whole week rather than one call per topic. Ask for:

- Ranked topic and source-node IDs.
- Opening question or hook.
- Why the topic should interest the audience.
- Best supported format.
- Strongest supporting excerpt or key quote.
- Suggested Pexels search query and visual mood.
- Risk notes: weak evidence, repetition, sensitive claims, or distracting grounding references.

Require diversity across the week. Reject near-duplicate subjects and generic hooks. The useful code starts in:

- `lib/grid_media_manager/automation/llm_selector.ex`
- `lib/grid_media_manager/automation/editorial_guidance.ex`
- `lib/grid_media_manager/automation/editorial_batch.ex`

Save the resulting plan before media generation so the run can resume without another LLM call.

## 3. Clean and quality-check all copy together

Generate platform copy as a batch, then run a second batch editorial pass over all titles and posts.

The pass should check:

- Spelling, grammar, punctuation, and natural title capitalisation.
- Whether the opening line creates curiosity without overstating the evidence.
- Removal of inline search-grounding markers and distracting citation tokens.
- A clear reason to continue to RationalGrid.ai.
- Native length and tone for X, LinkedIn, and Facebook.
- No duplicated wording across consecutive days.

Do not make three identical captions with different platform labels. Use `lib/grid_media_manager/social/templates.ex` as the common copy layer.

## 4. Select imagery efficiently

Run one Pexels search per selected topic using the LLM's visual query. Prefer images with:

- A clear subject or visual metaphor.
- Space for a large question.
- Strong contrast after a dark overlay.
- Editorial relevance rather than literal keyword matching.

Choose the best candidate from each result set, store the Pexels attribution metadata, and avoid downloading alternatives that will not be used.

## 5. Generate complete media packages

Build packages through the shared Studio contexts, not through LiveView-specific functions:

- `lib/grid_media_manager/studio/package_builder.ex`
- `lib/grid_media_manager/studio/workflow.ex`
- `lib/grid_media_manager/studio/visual_direction.ex`

For every text post, generate and save exactly two ordered PNGs:

1. Branded opening-question cover using a darkened Pexels background and RationalGrid.ai logo. Do not add an “OPEN QUESTION” pill.
2. RationalGrid.ai follow-up card with a direct visit CTA.

For every video, include the opening hook, selected evidence, and the canonical final “Continue on RationalGrid.ai” frame.

The canonical sequence is in `lib/grid_media_manager/promotion/slide_sequence.ex`; browser composition is in `assets/js/canvas_slide_renderer.js`. Save finished Canvas artifacts through `GridMediaManager.Promotion.ArtifactStore`. Never silently substitute the raw Pexels image when a composed artifact is missing.

Generate packages topic-by-topic with bounded concurrency. Keep source selection sequential only where later decisions depend on earlier results; parallelise independent Pexels downloads, rendering, and uploads.

## 6. Perform one review pass

Before touching Buffer, review the whole week together. Check representative previews and inspect every long title for overflow.

The approval view should make it easy to verify:

- Day and posting time.
- Topic and source rationale.
- Opening cover and final CTA.
- Video preview.
- Copy for each destination.
- Any editorial warnings.

Fix issues in the saved plan or shared package, then regenerate affected outputs only. Do not restart the whole week for one bad cover.

## 7. Publish assets before scheduling

Upload finished artifacts to stable S3 URLs. Preserve carousel ordering in `published_urls`: cover first and CTA last.

Verify a representative URL is public, returns the expected MIME type, and is not a local `/client-assets/` path. Reuse the already-uploaded asset for all platforms sharing the same creative.

## 8. Schedule through Buffer

Use `GridMediaManager.Social.Buffer.account_for/1` because text and video platforms may use different credentials.

Schedule successive days using the intended local timezone, converted deliberately to UTC. Apply the performance-informed posting time unless it would create a collision.

Operational rules:

- Use modest concurrency and transient retries to respect Buffer limits.
- Facebook posts require `%{facebook: %{type: "post"}}` metadata.
- If replacing a queued post, use Buffer's edit mutation to preserve its external ID and `dueAt`.
- Never create a duplicate merely because a response timed out. Query Buffer first and reconcile by external ID or schedule slot.
- Record each success immediately so a partial batch can resume safely.

## 9. Audit the live result

Do not declare completion from local database state alone. Query Buffer and verify:

- Expected count per channel and no channel above 10.
- Exact external IDs and scheduled times.
- Two PNG assets on every text post.
- Video asset on every video post.
- RationalGrid CTA present in every generated package.
- No duplicate topic/date combinations.

Report successful counts per platform and list any exceptions explicitly.

## 10. Leave a resumable checkpoint

At the end of the session, record:

- Plan or campaign IDs.
- Local draft IDs and Buffer external IDs.
- S3 asset URLs.
- Scheduled dates and channels.
- Failed or unfilled slots and the reason.

This checkpoint prevents the next agent from repeating LLM selection, Pexels searches, uploads, or Buffer mutations.

After source-code changes, run focused tests and finish with `mix precommit`. For UI behaviour, analyse source first and use Tidewave `browser_eval` snapshots. Do not restart Phoenix for ordinary code changes.
