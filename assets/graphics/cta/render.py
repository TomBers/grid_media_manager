#!/usr/bin/env python3
"""Export the shared CTA artwork; this is a design tool, not an app renderer."""

import base64
from pathlib import Path
import subprocess
import tempfile


HERE = Path(__file__).resolve().parent
OUTPUT = HERE.parents[2] / "priv" / "static" / "images"


def data_uri(path, mime):
    return f"data:{mime};base64,{base64.b64encode(path.read_bytes()).decode()}"


def artwork(story=False):
    height = 1920 if story else 1350
    brand_y = 230 if story else 108
    heading_y = 455 if story else 310
    support_y = 650 if story else 490
    map_y = 820 if story else 580
    action_y = 1290 if story else 972
    address_y = 1480 if story else 1156
    rule_y = 1660 if story else 1280
    tree = data_uri(HERE / "branching-tree.webp", "image/webp")
    mark = data_uri(HERE / "brandmark.svg", "image/svg+xml")

    return f'''<svg xmlns="http://www.w3.org/2000/svg"
        xmlns:xlink="http://www.w3.org/1999/xlink"
        width="1080" height="{height}" viewBox="0 0 1080 {height}">
      <title>RationalGrid — See what you think.</title>
      <desc>Explore this idea at rationalgrid.ai. Follow the evidence and compare perspectives. Free to explore.</desc>
      <defs>
        <linearGradient id="shade" x2="1" y2="0">
          <stop stop-color="#020617" stop-opacity=".98"/>
          <stop offset=".58" stop-color="#020617" stop-opacity=".5"/>
          <stop offset="1" stop-color="#020617" stop-opacity=".15"/>
        </linearGradient>
        <radialGradient id="teal-glow">
          <stop stop-color="#14b8a6" stop-opacity=".13"/>
          <stop offset="1" stop-color="#14b8a6" stop-opacity="0"/>
        </radialGradient>
        <radialGradient id="violet-glow">
          <stop stop-color="#818cf8" stop-opacity=".15"/>
          <stop offset="1" stop-color="#818cf8" stop-opacity="0"/>
        </radialGradient>
        <linearGradient id="spectrum">
          <stop stop-color="#2dd4bf"/>
          <stop offset=".52" stop-color="#818cf8"/>
          <stop offset="1" stop-color="#fbbf24"/>
        </linearGradient>
      </defs>
      <rect width="1080" height="{height}" fill="#020617"/>
      <image x="120" y="-40" width="1500" height="1000" preserveAspectRatio="xMidYMid slice"
        opacity=".24" xlink:href="{tree}"/>
      <rect width="1080" height="{height}" fill="url(#shade)"/>
      <ellipse cx="980" cy="{heading_y + 100}" rx="680" ry="640" fill="url(#violet-glow)"/>
      <ellipse cx="100" cy="{action_y + 120}" rx="900" ry="640" fill="url(#teal-glow)"/>

      <g font-family="Arial, Helvetica, sans-serif">
        <image x="84" y="{brand_y}" width="56" height="56" xlink:href="{mark}"/>
        <text x="158" y="{brand_y + 42}" font-size="40" font-weight="700" letter-spacing="-1" fill="#f8fafc">RationalGrid</text>

        <g font-size="108" font-weight="700" letter-spacing="-5">
          <text x="84" y="{heading_y}" fill="#f8fafc">See what</text>
          <text x="84" y="{heading_y + 110}" fill="#5eead4">you think.</text>
        </g>
        <text x="88" y="{support_y}" font-size="34" fill="#cbd5e1">Go beyond the answer.</text>

        <g transform="translate(0 {map_y})">
          <path d="M510 82 V126 M279 174 V126 H741 V174" fill="none" stroke="#64748b" stroke-width="2"/>
          <circle cx="510" cy="126" r="5" fill="#94a3b8"/>
          <rect x="268" width="484" height="82" rx="8" fill="#0f172a" stroke="#334155"/>
          <rect x="268" width="4" height="82" rx="2" fill="#38bdf8"/>
          <circle cx="313" cy="41" r="7" fill="#7dd3fc"/>
          <text x="340" y="53" font-size="34" fill="#f8fafc">Question</text>

          <rect x="84" y="174" width="390" height="114" rx="8" fill="#0f172a" stroke="#334155"/>
          <rect x="84" y="174" width="4" height="114" rx="2" fill="#34d399"/>
          <text x="112" y="219" font-size="20" letter-spacing="2.5" fill="#6ee7b7">EVIDENCE</text>
          <text x="112" y="258" font-size="29" fill="#f8fafc">Follow the evidence</text>

          <rect x="546" y="174" width="390" height="114" rx="8" fill="#0f172a" stroke="#334155"/>
          <rect x="546" y="174" width="4" height="114" rx="2" fill="#fbbf24"/>
          <text x="574" y="219" font-size="20" letter-spacing="2.5" fill="#fcd34d">PERSPECTIVES</text>
          <text x="574" y="258" font-size="29" fill="#f8fafc">Compare perspectives</text>
        </g>

        <rect x="84" y="{action_y}" width="852" height="102" rx="10" fill="#5eead4"/>
        <text x="120" y="{action_y + 66}" font-size="42" font-weight="700" fill="#020617">Explore this idea</text>
        <path d="M843 {action_y + 51} H891 M876 {action_y + 36} L891 {action_y + 51} L876 {action_y + 66}"
          fill="none" stroke="#020617" stroke-width="4" stroke-linecap="round" stroke-linejoin="round"/>
        <text x="84" y="{address_y}" font-size="52" font-weight="700" letter-spacing="-1" fill="#f8fafc">rationalgrid.ai</text>
        <text x="87" y="{address_y + 54}" font-size="27" fill="#94a3b8">Free to explore.</text>
      </g>
      <rect x="84" y="{rule_y}" width="852" height="3" fill="url(#spectrum)"/>
    </svg>'''


if __name__ == "__main__":
    OUTPUT.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="rationalgrid-cta-") as directory:
        for name, story in [("carousel", False), ("story", True)]:
            source = Path(directory) / f"{name}.svg"
            source.write_text(artwork(story))
            output = OUTPUT / f"rationalgrid-cta-{name}.png"
            subprocess.run(["rsvg-convert", str(source), "-o", str(output)], check=True)
            print(output)
