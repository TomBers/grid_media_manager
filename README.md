# GridMediaManager

Internal RationalGrid Share Studio for turning RationalGrid media payloads into social-ready assets and deterministic post drafts.

## What it does

- Accepts a RationalGrid URL, direct media endpoint URL, or slug
- Fetches the RationalGrid media JSON with `Req`
- Persists a campaign, media assets, and editable post drafts
- Previews SVG share cards/highlight cards
- Generates simple template-based drafts for X, Bluesky, LinkedIn, Instagram, and Substack
- Copies draft text and asset URLs for manual publishing

No authentication, LLM support, scheduling, or direct posting is included yet.

## RationalGrid endpoint configuration

By default the importer builds media URLs like:

```text
https://rationalgrid.ai/g/:slug/media.json
```

Override this locally when needed. If local RationalGrid is already using port `4000`, start this app on another port:

```sh
PORT=4001 \
RATIONAL_GRID_BASE_URL=http://localhost:4000 \
RATIONAL_GRID_MEDIA_PATH_TEMPLATE=/api/promotion/grids/:slug/materials \
mix phx.server
```

With that configuration, paste a bare slug such as:

```text
what-is-the-collective-subconscious-637e9a
```

You can also paste the full local endpoint directly:

```text
http://localhost:4000/api/promotion/grids/what-is-the-collective-subconscious-637e9a/materials
```

Direct URLs ending in `.json`, using a `/media` path segment, or using a `/materials` path segment are fetched as-is.

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
