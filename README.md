# GridMediaManager

Internal RationalGrid Share Studio for turning RationalGrid media payloads into social-ready assets and deterministic post drafts.

## What it does

- Accepts a RationalGrid URL, direct media endpoint URL, or slug
- Fetches the RationalGrid media JSON with `Req`
- Persists a campaign, media assets, and editable post drafts
- Generates and previews upload-ready PNG share cards and highlight cards
- Renders carousel slides as PNGs and stitches them into vertical MP4s for Reels and Shorts
- Generates simple template-based drafts for X, Bluesky, LinkedIn, Instagram, YouTube Shorts, and Substack
- Copies draft text and asset URLs for manual publishing
- Searches Pexels for optional attributed photo backdrops
- Schedules approved or edited drafts through Buffer

No authentication or LLM support is included yet.

## RationalGrid endpoint configuration

By default the importer uses the RationalGrid promotion endpoints:

```text
GET https://rationalgrid.ai/api/promotion/grids
GET https://rationalgrid.ai/api/promotion/grids/:graph_name
```

For local testing against RationalGrid on port `4000`, start this app on another port and point the base URL at the local app:

```sh
PORT=4001 \
RATIONAL_GRID_BASE_URL=http://localhost:4000 \
RATIONALGRID_PROMOTION_API_TOKEN=your-dev-token \
mix phx.server
```

The app sends the token as:

```text
Authorization: Bearer $RATIONALGRID_PROMOTION_API_TOKEN
```

Do not commit real tokens; keep them in your shell environment, `.envrc`, or another local secret manager.

If your dev server does not inherit shell environment variables, create an ignored local file at `config/dev.secret.exs`:

```elixir
import Config

config :grid_media_manager, :rational_grid,
  promotion_api_token: "your-dev-token"
```

With that configuration you can click **Load grids** on the import screen, choose a grid from the index endpoint, or paste a bare graph name such as:

```text
what-is-the-collective-subconscious-637e9a
```

You can also paste the full local show endpoint directly:

```text
http://localhost:4000/api/promotion/grids/what-is-the-collective-subconscious-637e9a
```

Direct URLs ending in `.json`, using a `/media` path segment, using a `/materials` path segment, or matching `/api/promotion/grids/:graph_name` are fetched as-is.

## Promotion payload shape

The RationalGrid promotion API should return source content, not pre-rendered media. Grid Media Manager owns generating cards, images, and platform-specific export assets from this content.

Expected show response:

```json
{
  "metadata": {
    "title": "What can a brave new world teach us?",
    "slug": "what-can-a-brave-new-world-teach-us-1964bc",
    "url": "https://rationalgrid.com/g/what-can-a-brave-new-world-teach-us-1964bc",
    "api_url": "https://rationalgrid.com/api/promotion/grids/what-can-a-brave-new-world-teach-us-1964bc",
    "tags": ["Dystopian Literature", "Social Philosophy"],
    "node_count": 5,
    "inserted_at": "...",
    "updated_at": "..."
  },
  "graph": {
    "nodes": [],
    "edges": []
  },
  "highlights": []
}
```

The importer derives the Share Studio context from this raw graph data:

- `metadata` becomes the campaign summary.
- `graph.nodes` becomes key-node source material.
- the first node with class `answer` becomes the first answer excerpt source.
- nodes with class `question` or `user` become user questions.
- question sentences found in graph node content are extracted as follow-up questions.
- answer Markdown is parsed into media-safe semantic blocks so headings, paragraphs, lists, numbering, blockquotes, citation labels, and spacing survive in generated cards and videos.
- top-level `highlights` become generated highlight-card source material.

The importer still understands the older `grid`/`content` and `raw`/`assets` response shapes during transition.

Generated PNG asset routes:

```text
GET /campaigns/:id/share-card.png
GET /campaigns/:id/nodes/:node_id/share-card.png
GET /campaigns/:id/questions/:question_id/share-card.png
GET /campaigns/:id/highlights/:highlight_id/share-card.png
```

SVG is used only as an internal layout intermediate before rasterization; Studio assets and public image routes are PNG.

The importer does not generate images on load. Title/grid cards, highlight cards, key-node cards, and identified-question quote cards are generated on demand from the Share Studio context panel.

Share Studio includes a card style picker. The same key node or question can be generated in multiple styles.

Foundation styles:

- `minimal_light` — black text on a flat white background with decoration disabled
- `minimal_dark` — white text on a flat black background with decoration disabled

Social/editorial styles:

- `editorial_dark` — premium dark treatment for quotes and explainers
- `gradient_poster` — high-energy color for hooks and launches
- `minimal_academic` — cool light editorial treatment for thoughtful explainers
- `warm_paper` — warm cinematic treatment for reflective excerpts
- `signal_red` — high-urgency treatment for debate prompts
- `deep_ocean` — analytical dark treatment for complex topics
- `newsprint` — tactile print treatment for quotes and cultural topics

Question, highlight, and key-node production includes channel-specific layouts:

- `landscape` — 1200×630 feed hook for X, Bluesky, and link previews
- `linkedin` — 1200×1200 square explainer with denser body copy
- `portrait` — 1080×1350 Instagram reading card
- `carousel` — key nodes become 1080×1350 Instagram slides plus a multi-frame Short; questions and highlights become a portrait plus a six-second 1080×1920 MP4
- `combined_carousel` — two to six selected questions, highlights, key nodes, or overview cards become one curated carousel package with a cover and closing invitation, plus a companion 1080×1920 Short with theme audio

Generated style and layout variants are persisted as separate media assets. Generated assets can be deleted from the asset gallery, which also removes their associated generated drafts so variants can be regenerated during testing. Titles and quote text are preserved in full and fitted to the available card area. Generated suggestions always stay within their platform limit; when complete source text cannot fit, the template falls back to a compact link invitation instead of truncating the title or quote. X counters exclude hashtags.

## Local environment file

For local development, the runtime loads the ignored `.env` file before the application starts. Copy the template and start the app through the included wrapper:

```sh
cp .env.example .env
# edit .env with your keys and Buffer channel IDs
bin/dev
```

`bin/dev` also exports the values in `.env` before running `mix phx.server`, which is useful when starting the app from a shell. The file is ignored by git, and you must restart the server after changing it. Production deployments should continue to provide environment variables through the host or release manager.

The two Buffer accounts are configured with `BUFFER_API_KEY` (or `BUFFER_VIDEO_API_KEY`) plus the video channel IDs, and `BUFFER_TEXT_API_KEY` plus `BUFFER_TEXT_CHANNEL_X` and `BUFFER_TEXT_CHANNEL_LINKEDIN` for text scheduling.

## Pexels backgrounds

Set `PEXELS_API_KEY` to enable photo search in the guided studio:

```sh
PEXELS_API_KEY=your-key mix phx.server
```

Alternatively, export the variable before starting the server:

```sh
export PEXELS_API_KEY=your-key
mix phx.server
```

The server must be restarted after changing its environment. For local development, you can instead add the following to the ignored `config/dev.secret.exs` file:

```elixir
import Config
config :grid_media_manager, :pexels, api_key: "your-key"
```

The selected photo is stored with its photographer and Pexels attribution and is embedded behind the active card theme. Only HTTPS images returned from `images.pexels.com` are fetched by the renderer. If the image is unavailable, cards fall back to the selected built-in theme.

## S3 media publishing

Generated local media can be rendered and uploaded to S3 automatically before Buffer scheduling:

```sh
S3_BUCKET=your-media-bucket \
AWS_REGION=eu-west-2 \
AWS_ACCESS_KEY_ID=your-access-key \
AWS_SECRET_ACCESS_KEY=your-secret-key \
S3_PUBLIC_BASE_URL=https://media.example.com \
mix phx.server
```

The IAM identity needs `s3:PutObject` for the `campaigns/*` prefix. `S3_PUBLIC_BASE_URL` should point to a public HTTPS bucket endpoint or CloudFront distribution where Buffer can retrieve objects without authentication. If it is omitted, the standard virtual-hosted S3 URL is used, which still requires an appropriate public-read bucket policy. `S3_ENDPOINT` can override the upload endpoint when needed.

Assets use content-hashed object keys. The durable `published_url`, S3 key, and SHA-256 digest are stored in media asset metadata while the original local generation route remains unchanged. The first Buffer schedule uploads the asset; subsequent schedules reuse the persisted S3 URL.

## Buffer scheduling

Buffer scheduling uses Buffer's GraphQL API and requires a personal API key plus a channel ID for each platform you want to schedule:

```sh
PUBLIC_BASE_URL=https://your-public-studio.example.com \
S3_BUCKET=your-media-bucket \
AWS_REGION=eu-west-2 \
AWS_ACCESS_KEY_ID=your-access-key \
AWS_SECRET_ACCESS_KEY=your-secret-key \
S3_PUBLIC_BASE_URL=https://media.example.com \
BUFFER_API_KEY=your-key \
BUFFER_CHANNEL_X=channel-id \
BUFFER_CHANNEL_BLUESKY=channel-id \
BUFFER_CHANNEL_LINKEDIN=channel-id \
BUFFER_CHANNEL_INSTAGRAM=channel-id \
BUFFER_CHANNEL_YOUTUBE=channel-id \
BUFFER_YOUTUBE_CATEGORY_ID=27 \
mix phx.server
```

Schedules are entered in UTC. Buffer requires media to be available from a public HTTPS URL through the scheduled publication time. `PUBLIC_BASE_URL` is used to turn generated card paths into URLs Buffer can fetch. In local development, expose the Phoenix server with a service such as ngrok or Cloudflare Tunnel and set `PUBLIC_BASE_URL` to that HTTPS tunnel URL. The scheduler rejects local/private URLs before calling Buffer and stores Buffer's post ID or API failure on the draft for review.

## Short-form video rendering

Carousel video exports require FFmpeg at runtime. By default the app finds `ffmpeg` on `PATH`; a custom executable can be configured with:

```elixir
config :grid_media_manager, :ffmpeg_path, "/path/to/ffmpeg"
```

The generated MP4 is 1080×1920 H.264/yuv420p with approximately three seconds per slide and gentle transitions. Both carousel videos and six-second static Shorts include `priv/static/sounds/rationalgrid_theme.mp4` as a softly mixed AAC background track, looped or trimmed to the exact video duration with short audio fades. A different source can be configured with `config :grid_media_manager, :video_background_audio_path, "/path/to/audio.mp4"`. Video frames use a dedicated full-screen layout with larger hook typography rather than padding the Instagram carousel images. Videos are cached in the system temporary directory using a content-derived key that includes the audio file metadata. If FFmpeg is unavailable, carousel PNGs still generate and the guided studio shows a video-encoding warning.

Generated carousel routes:

```text
GET /campaigns/:id/nodes/:node_id/carousel.png?slide=1
GET /campaigns/:id/nodes/:node_id/carousel.mp4
GET /campaigns/:id/questions/:question_id/short.mp4
GET /campaigns/:id/highlights/:highlight_id/short.mp4
```

## Start the Phoenix server

- Run `mix setup` to install and setup dependencies
- Run migrations with `mix ecto.migrate`
- Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Visit [`localhost:4000`](http://localhost:4000) from your browser.

## Validation

Run the project precommit before finishing changes:

```sh
mix precommit
```

## Learn more

- Phoenix website: https://www.phoenixframework.org/
- Phoenix guides: https://hexdocs.pm/phoenix/overview.html
- Phoenix docs: https://hexdocs.pm/phoenix
