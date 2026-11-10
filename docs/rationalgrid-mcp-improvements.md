# RationalGrid MCP: fewer client interventions

These are proposed server changes, not features the media manager assumes already exist.
They are based on the local `dialectic/mcp/src/server.ts` and
`dialectic/lib/dialectic/integrations/explorations.ex`, and the 10 November publishing run.
No RationalGrid server files were changed by this implementation.

## 1. Publish on completion, atomically

The biggest intervention was publishing each completed private grid. Publishing early
also caused the coordinator to return `editing_stopped`, even when some or all answers
had already finished. Delayed retries created further private grids after the bulk change.

Add an opt-in `publish_on_complete` argument to `explore_question`, backed by a separate
`grids:publish` OAuth scope and a saved account/client publication policy. The default
should remain private. An approved weekly workflow could request publication once for
its bounded run, rather than needing a manual toggle for every grid.

The coordinator should finish generation, persist the final graph revision, mark the
operation completed, and then publish under one coordinated transition. If publication
fails, retain the completed private grid with `publication_status=failed`; do not label
successful generation failed or regenerate its answers. Return the public URL and the
revision that was published. Do not silently publish partial content.

For existing grids, a separate idempotent `publish_grid(grid_id, expected_revision,
request_id)` tool would permit review before publication. Enforce ownership, the
publication scope, and revision matching. Expose the actual public-access status.

## 2. Machine-readable errors and capacity

The client currently has to recognise human error text such as “rate limited”. Return
structured error data with stable fields, for example:

```json
{
  "code": "too_many_active_operations",
  "retryable": true,
  "retry_after_seconds": 20,
  "request_accepted": false,
  "request_id": "persisted-client-uuid"
}
```

Distinguish rate limits, active-generation limits, transient provider failures, invalid
arguments, lost access, deleted results and UUID/content conflicts. Preserve the original
request UUID and operation receipt on uncertain transport retries. Never retry a write
under a different UUID merely because an HTTP response was lost.

Advertise maximum active explorations, burst limits, suggested poll intervals, supported
protocol versions, publication support and content limits in server capabilities. A
server-side bounded batch queue would be better still: accept a list of UUID/question
pairs once, then schedule them fairly without making clients probe the rate limit.

## 3. Make “completed” a durable content guarantee

A completed operation should identify a persisted revision whose opening answer, test,
deepening and synthesis can all be read. During the first live import, operation output
contained synthesis text that the grid-read projection omitted. The client now supplements
missing text from the matching completed operation, but should not need this workaround.

Use the same canonical node serializer for operation results and grid reads. Return
`content_status` and per-stage status, including the distinction between an empty
placeholder and a completed empty result. Keep operation receipts after job pruning.

For pagination, return a snapshot revision and bind subsequent cursors to it. That avoids
missing or duplicating nodes while the graph changes between pages.

## 4. Export a stable campaign snapshot

Add `export_grid(grid_id, revision)` for accessible public or private grids. Return stable
metadata, origin question, canonical nodes and edges, synthesis, source citations,
authorship/provenance, visibility, public URL and a content hash. Include every page or
provide a revision-bound cursor. This would remove the promotion-API/MCP format mismatch
and provide a reliable cache key for copy and media.

Private exports should keep the existing access checks; public posting should separately
check that its destination URL is anonymously accessible.

## 5. Notifications and bounded batch status

Expose operation updates through MCP notifications or a signed webhook, with ordinary
polling as a fallback. Include suggested next-poll time, last progress time and the
reason for any stall. A `get_operations(request_ids)` tool would let a weekly run obtain
all statuses in one read, including per-operation errors and publication progress.

## 6. Recover a stage rather than restart a grid

Add explicit cancellation and retry/resume of a failed stage. Keep completed nodes,
preserve user-authored text, and report exactly which stage can resume. Use a separate
idempotency key for the requested retry action while linking it to the original
operation. Require explicit intent to regenerate content; reading status must remain
read-only. Public grids should not be silently made private or appended to as a side
effect of recovery.

## Suggested order

1. Typed errors, capacity metadata, and a consistent completed-content serializer.
2. `publish_on_complete` with a publication scope and a durable publication receipt.
3. Revision-bound export and operation notifications/batch reads.
4. Explicit stage recovery and cancellation.

The media manager now tolerates absent publication support, resumes saved work, checks
anonymous access, and reconciles uncertain Buffer submissions. These server changes would
remove most remaining manual publication and recovery steps.
