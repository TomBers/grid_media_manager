# RationalGrid Publishing Studio

A Phoenix LiveView workflow for turning RationalGrid source text into editable social media packages.

## Product flow

1. Find or import a RationalGrid grid.
2. Choose the questions, highlights, or longer answers worth sharing.
3. Choose an output format and destinations.
4. Edit every slide's headline and supporting text.
5. The browser lays out the text on canvas and saves the finished PNG frames.
6. Review and approve the accompanying post copy, then schedule it through Buffer.

The browser canvas is the only visual renderer. Phoenix plans and persists editable text, style choices, and slide order; it does not contain an SVG or server-side card renderer. For short-form video, FFmpeg packages the exact saved PNG frames into an MP4 without recreating their layout.

## Development

```sh
cp .env.example .env
bin/dev
```

The app normally runs at `http://localhost:4001`. Run the complete verification suite with:

```sh
mix precommit
```

Important configuration:

- `RATIONAL_GRID_BASE_URL` — trusted RationalGrid origin; direct import URLs must use this origin.
- `RATIONALGRID_PROMOTION_API_TOKEN` — bearer token for RationalGrid's promotion API.
- `PEXELS_API_KEY` — optional attributed photo search.
- `BUFFER_API_KEY`, `BUFFER_VIDEO_API_KEY`, `BUFFER_TEXT_API_KEY` and the corresponding `BUFFER_*_CHANNEL_*` values — publishing destinations.
- `S3_BUCKET`, AWS credentials, and optionally `S3_PUBLIC_BASE_URL` — durable public media for Buffer.
- `STUDIO_BASIC_AUTH_USER` and `STUDIO_BASIC_AUTH_PASSWORD` — required in production while this remains a standalone application.

Local development can read these values from the ignored `.env` file. Production must provide them through the deployment environment.

## Client artifact boundary

Finished PNGs are posted to:

```text
POST /api/media-assets/:id/artifacts/:index
```

They are read from:

```text
GET /media-assets/:id/artifacts/:index
GET /media-assets/:id/artifact.mp4
```

`GridMediaManager.Promotion.ArtifactStore` is the storage boundary. It currently uses a configurable local directory (`:artifact_store_path`, default `storage/artifacts`). RationalGrid integration should replace this implementation with its object-storage service while keeping the canvas and campaign APIs unchanged.

## RationalGrid integration

The intended end state is for this workflow to live inside RationalGrid's authenticated Phoenix application:

- mount the studio routes inside RationalGrid's authenticated `live_session` and pass its `current_scope`;
- associate campaigns, media assets, and post drafts with the RationalGrid account or user;
- replace `RequireStudioAccess` with RationalGrid authorization;
- call the source context directly instead of making an HTTP round trip where practical;
- back `ArtifactStore` with RationalGrid's object storage;
- keep publishing credentials and Buffer reconciliation in server-side services.

The reusable seams are the content planner (`ShareCard` and `SlideSequence`), workflow orchestration (`Studio.Workflow`), client canvas hook, artifact store, and publishing contexts. The server stores content and state; the client owns presentation.

## Media and publishing notes

FFmpeg must be on `PATH` to create MP4s. A custom executable can be configured with `config :grid_media_manager, :ffmpeg_path, "/path/to/ffmpeg"`.

Buffer needs durable public HTTPS media, so production scheduling normally also needs S3-compatible storage. Editing a slide invalidates saved artifacts and published URLs; the user must save the new browser render before it can be scheduled.

## Engagement and results

`/results` stores the latest Buffer metrics matched by platform and external post ID to studio drafts. Refresh is read-only at Buffer. An explicit `sent` response reconciles a scheduled draft to published without deleting its media. Refreshes replace cumulative counters; they never add them together. Missing metrics remain unavailable. The table compares posts aged 72 hours to 90 days within a channel; totals are cumulative, not controlled experiments or equal-age comparisons. Buffer's metrics API is experimental.

New captions tag RationalGrid links with `utm_source`, `utm_medium=social`, `utm_campaign=grid-ID` and `utm_content=asset-ID-angle`, preserving deep-link parameters and fragments. Measuring website visits or conversions still requires analytics on RationalGrid. Shorts descriptions explicitly identify their reference URL as non-clickable.

Autopilot refreshes metrics when the last successful matched-post sync is over six hours old, then includes channel-specific examples with clicks, saves, shares or comments in topic selection. These are weak editorial signals; small samples do not establish a winning topic or time.

New planned videos carry three concise `video_script` beats. Publishing checks the selected sequence for 4–6 frames, at most 25 visible words per non-CTA frame, and at most 45 seconds. Text reading time is preserved; a concise opening has a three-second minimum. Dense manually selected source excerpts remain editable and receive a pacing warning rather than being silently truncated. The original source is unchanged.

`Automation.queue_fill_plan/2` previews available slots; `Automation.fill_queues/2` submits them. It respects the ten-post limit per channel, existing queue dates, explicit draft approval or current Editor approval, media readiness, copy limits and pacing. Re-running skips drafts already scheduled or published. Slots use alternating UTC test windows in `Social.PostingSchedule`, informed by [Buffer's 2026 timing research](https://buffer.com/resources/best-time-to-post-social-media/), with a UK audience as the initial assumption. These UTC windows do not automatically adjust for daylight saving. X, Facebook, LinkedIn and Instagram use weekdays; TikTok and Shorts also use weekends. Review actual results and audience geography before changing the windows.
