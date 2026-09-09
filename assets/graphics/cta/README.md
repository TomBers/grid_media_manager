The shared CTA artwork follows https://rationalgrid.ai/ as reviewed on 9 September 2026:
the navy and teal hero, “See what you think.”, connected question cards, and the
teal/indigo/amber rule. The brandmark and branching-tree background are copied
from the site's own assets, preserving the established identity.

Edit `render.py` and export with Python 3 and the `rsvg-convert` design utility:

```sh
python3 assets/graphics/cta/render.py
```

This produces committed PNGs in `priv/static/images`: 1080 × 1350 for carousels
and 1080 × 1920 for stories. The story composition keeps its main content between
230 and 1663 pixels vertically, with generous side margins for social controls.
The source uses Arial, with Helvetica and sans-serif fallbacks; install Arial
when reproducing the committed artwork.

The app's existing browser canvas draws these static graphics. The exporter is
an offline design tool and is not part of the application rendering pipeline.
After changing the graphics, bump `ArtifactStore`'s renderer version so saved
frames are refreshed. Keep the canonical copy in `StoryPackage` aligned with
the artwork, since it also informs video reading time.

Reference assets:
- https://rationalgrid.ai/images/brandmark-cdb69531c2e86f1ce948c51f0b5fc6db.svg
- https://rationalgrid.ai/images/fractal-branching-tree-1536-301446b121789d28db1b68830c76b312.webp
