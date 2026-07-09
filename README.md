# GridMediaManager

Internal RationalGrid Share Studio for turning RationalGrid media payloads into social-ready assets and deterministic post drafts.

## What it does

- Accepts a RationalGrid URL, direct media endpoint URL, or slug
- Fetches the RationalGrid media JSON with `Req`
- Persists a campaign, media assets, and editable post drafts
- Generates and previews local SVG share cards/highlight cards
- Generates simple template-based drafts for X, Bluesky, LinkedIn, Instagram, and Substack
- Copies draft text and asset URLs for manual publishing

No authentication, LLM support, scheduling, or direct posting is included yet.

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
  "grid": {
    "title": "What can a brave new world teach us?",
    "slug": "what-can-a-brave-new-world-teach-us-1964bc",
    "url": "https://rationalgrid.com/g/what-can-a-brave-new-world-teach-us-1964bc",
    "tags": ["Dystopian Literature", "Social Philosophy"],
    "node_count": 5,
    "inserted_at": "...",
    "updated_at": "..."
  },
  "content": {
    "origin_question": "What can a brave new world teach us?",
    "first_answer": {
      "node_id": "2",
      "title": "What Can a Brave New World Teach Us?",
      "content": "...",
      "excerpt": "..."
    },
    "follow_up_questions": [],
    "user_questions": [],
    "highlights": [],
    "key_nodes": []
  }
}
```

The importer still understands the older `raw`/`assets` response shape during transition.

Generated SVG asset routes:

```text
GET /campaigns/:id/share-card.svg
GET /campaigns/:id/nodes/:node_id/share-card.svg
GET /campaigns/:id/highlights/:highlight_id/share-card.svg
```

When the RationalGrid payload does not provide legacy `assets`, the importer creates local generated assets from the campaign title and content highlights. Key-node cards are generated on demand from the Share Studio key-node panel.

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
