const WIDTH = 1080
const IMAGE_HEIGHT = 1350
const VIDEO_HEIGHT = 1920
const UI_FONT = "Arial, Helvetica, sans-serif"
const QUOTE_FONT = "Georgia, Times New Roman, serif"
const FONT_SIZES = [136, 128, 120, 112, 104, 96, 88, 80, 72, 64, 56, 52, 48, 44, 40, 36, 32, 28, 24, 20, 18]

const PALETTES = {
  minimal_light: {
    canvas: ["#ffffff", "#f1f5f9"],
    card: "rgba(255,255,255,0.94)",
    panel: "rgba(248,250,252,0.94)",
    border: "rgba(100,116,139,0.48)",
    text: "#0f172a",
    secondary: "#334155",
    muted: "#64748b",
    accent: "#334155",
  },
  minimal_dark: {
    canvas: ["#000000", "#111827"],
    card: "rgba(0,0,0,0.9)",
    panel: "rgba(0,0,0,0.9)",
    border: "rgba(255,255,255,0.2)",
    text: "#ffffff",
    secondary: "#e5e5e5",
    muted: "#a3a3a3",
    accent: "#ffffff",
  },
  editorial_dark: {
    canvas: ["#111827", "#1e1b4b", "#0f172a"],
    card: "rgba(2,6,23,0.78)",
    panel: "rgba(255,255,255,0.07)",
    border: "rgba(255,255,255,0.13)",
    text: "#fff7ed",
    secondary: "#cbd5e1",
    muted: "#94a3b8",
    accent: "#fb7185",
  },
  gradient_poster: {
    canvas: ["#2e1065", "#7e22ce", "#0f766e"],
    card: "rgba(17,24,39,0.68)",
    panel: "rgba(255,255,255,0.08)",
    border: "rgba(255,255,255,0.16)",
    text: "#fff7ed",
    secondary: "#e0f2fe",
    muted: "#c4b5fd",
    accent: "#f0abfc",
  },
  minimal_academic: {
    canvas: ["#f8fafc", "#e2e8f0"],
    card: "rgba(255,255,255,0.94)",
    panel: "rgba(248,250,252,0.94)",
    border: "rgba(100,116,139,0.62)",
    text: "#0f172a",
    secondary: "#334155",
    muted: "#64748b",
    accent: "#334155",
  },
  warm_paper: {
    canvas: ["#451a03", "#78350f", "#1c1917"],
    card: "rgba(28,25,23,0.78)",
    panel: "rgba(255,247,237,0.09)",
    border: "rgba(254,215,170,0.18)",
    text: "#fff7ed",
    secondary: "#fed7aa",
    muted: "#fdba74",
    accent: "#f59e0b",
  },
  signal_red: {
    canvas: ["#2b0709", "#7f1d1d", "#111827"],
    card: "rgba(24,10,11,0.82)",
    panel: "rgba(255,241,242,0.08)",
    border: "rgba(254,205,211,0.2)",
    text: "#fff7ed",
    secondary: "#fecaca",
    muted: "#fda4af",
    accent: "#fb7185",
  },
  deep_ocean: {
    canvas: ["#082f49", "#0f172a", "#164e63"],
    card: "rgba(6,17,31,0.84)",
    panel: "rgba(236,254,255,0.07)",
    border: "rgba(165,243,252,0.18)",
    text: "#ecfeff",
    secondary: "#bae6fd",
    muted: "#67e8f9",
    accent: "#67e8f9",
  },
  newsprint: {
    canvas: ["#f5f0e6", "#d6c8b6"],
    card: "rgba(250,247,240,0.94)",
    panel: "rgba(255,253,248,0.84)",
    border: "rgba(120,113,108,0.62)",
    text: "#1c1917",
    secondary: "#44403c",
    muted: "#78716c",
    accent: "#991b1b",
  },
}

function paletteFor(style) {
  return PALETTES[style] || PALETTES.editorial_dark
}

function roundedRect(context, x, y, width, height, radius) {
  if (typeof context.roundRect === "function") {
    context.beginPath()
    context.roundRect(x, y, width, height, radius)
    return
  }

  context.beginPath()
  context.moveTo(x + radius, y)
  context.lineTo(x + width - radius, y)
  context.quadraticCurveTo(x + width, y, x + width, y + radius)
  context.lineTo(x + width, y + height - radius)
  context.quadraticCurveTo(x + width, y + height, x + width - radius, y + height)
  context.lineTo(x + radius, y + height)
  context.quadraticCurveTo(x, y + height, x, y + height - radius)
  context.lineTo(x, y + radius)
  context.quadraticCurveTo(x, y, x + radius, y)
}

function drawBackground(context, palette, frame) {
  const gradient = context.createLinearGradient(0, 0, WIDTH, frame.height)
  const colors = palette.canvas
  colors.forEach((color, index) => gradient.addColorStop(index / Math.max(colors.length - 1, 1), color))
  context.fillStyle = gradient
  context.fillRect(0, 0, WIDTH, frame.height)

  context.fillStyle = "rgba(255,255,255,0.035)"
  context.beginPath()
  context.arc(940, frame.video ? 230 : 170, 230, 0, Math.PI * 2)
  context.fill()
  context.beginPath()
  context.arc(110, frame.video ? 1690 : 1190, 250, 0, Math.PI * 2)
  context.fill()

  context.fillStyle = palette.card
  roundedRect(context, 54, frame.video ? 64 : 54, 972, frame.video ? 1792 : 1242, frame.video ? 48 : 44)
  context.fill()
  context.strokeStyle = palette.border
  context.lineWidth = 1
  context.stroke()

  context.fillStyle = palette.panel
  roundedRect(context, 82, frame.video ? 92 : 82, 916, frame.video ? 1736 : 1186, frame.video ? 34 : 32)
  context.fill()
  context.strokeStyle = palette.border
  context.stroke()
}

function drawHeader(context, palette, frame, textColor = palette.text) {
  context.fillStyle = textColor
  context.globalAlpha = 0.92
  context.font = `800 ${frame.video ? 23 : 20}px ${UI_FONT}`
  context.fillText("RationalGrid.ai", 130, frame.video ? 170 : 142)
  context.globalAlpha = 1
  context.strokeStyle = palette.border
  context.beginPath()
  context.moveTo(130, frame.video ? 210 : 176)
  context.lineTo(950, frame.video ? 210 : 176)
  context.stroke()
}

function cleanInlineMarkdown(value) {
  return String(value || "")
    .replace(/!\[([^\]]*)\]\([^)]*\)/g, "$1")
    .replace(/\[([^\]]+)\]\([^)]*\)/g, "$1")
    .replace(/`([^`]+)`/g, "$1")
    .replace(/[*_~]/g, "")
    .replace(/\s+/g, " ")
    .trim()
}

function sentenceGroups(value, maxCharacters = 220) {
  const sentences = String(value || "").match(/[^.!?]+(?:[.!?]+|$)/g) || []
  const groups = []
  let group = ""

  sentences.forEach(sentence => {
    const clean = cleanInlineMarkdown(sentence)
    if (!clean) return

    const next = group ? `${group} ${clean}` : clean
    if (group && next.length > maxCharacters) {
      groups.push(group)
      group = clean
    } else {
      group = next
    }
  })

  if (group) groups.push(group)
  return groups
}

function normalizedBlocks(slide) {
  if (Array.isArray(slide.blocks) && slide.blocks.length > 0) {
    return slide.blocks
      .map(block => ({
        type: block.type || "paragraph",
        text: cleanInlineMarkdown(block.text),
        marker: block.marker || "•",
      }))
      .filter(block => block.text)
  }

  const blocks = []
  if (slide.title && !["cover", "node_title", "quote", "highlight", "cta"].includes(slide.kind)) {
    blocks.push({type: "heading", text: cleanInlineMarkdown(slide.title)})
  }

  const lines = String(slide.body || "").replace(/\r\n/g, "\n").split("\n")
  let paragraph = []
  const flushParagraph = () => {
    const text = cleanInlineMarkdown(paragraph.join(" "))
    if (text) sentenceGroups(text).forEach(group => blocks.push({type: "paragraph", text: group}))
    paragraph = []
  }

  lines.forEach(line => {
    const trimmed = line.trim()
    if (!trimmed) return flushParagraph()

    const heading = trimmed.match(/^#{1,6}\s+(.+)$/)
    const quote = trimmed.match(/^>\s*(.+)$/)
    const bullet = trimmed.match(/^[-+*]\s+(.+)$/)
    const numbered = trimmed.match(/^(\d+)[.)]\s+(.+)$/)

    if (heading || quote || bullet || numbered) flushParagraph()
    if (heading) blocks.push({type: "heading", text: cleanInlineMarkdown(heading[1])})
    else if (quote) blocks.push({type: "blockquote", text: cleanInlineMarkdown(quote[1])})
    else if (bullet) blocks.push({type: "list_item", marker: "•", text: cleanInlineMarkdown(bullet[1])})
    else if (numbered) blocks.push({type: "list_item", marker: `${numbered[1]}.`, text: cleanInlineMarkdown(numbered[2])})
    else paragraph.push(trimmed)
  })
  flushParagraph()
  return blocks
}

function wrapText(context, text, maxWidth) {
  const words = String(text || "").split(/\s+/).filter(Boolean).flatMap(word => {
    if (context.measureText(word).width <= maxWidth) return [word]
    const parts = []
    let part = ""
    Array.from(word).forEach(character => {
      const next = `${part}${character}`
      if (part && context.measureText(next).width > maxWidth) {
        parts.push(part)
        part = character
      } else {
        part = next
      }
    })
    if (part) parts.push(part)
    return parts
  })
  const lines = []
  let line = ""

  words.forEach(word => {
    const next = line ? `${line} ${word}` : word
    if (!line || context.measureText(next).width <= maxWidth) {
      line = next
    } else {
      lines.push(line)
      line = word
    }
  })

  if (line) lines.push(line)

  if (lines.length > 1 && lines.at(-1).split(" ").length === 1) {
    const previousWords = lines.at(-2).split(" ")
    const orphan = lines.at(-1)
    if (previousWords.length > 2) {
      const moved = previousWords.pop()
      const balancedLast = `${moved} ${orphan}`
      if (context.measureText(balancedLast).width <= maxWidth) {
        lines[lines.length - 2] = previousWords.join(" ")
        lines[lines.length - 1] = balancedLast
      }
    }
  }
  return lines
}

function blockStyle(block, fontSize, palette) {
  if (block.type === "heading") {
    return {size: fontSize + 5, lineHeight: (fontSize + 5) * 1.28, gap: 18, weight: 800, color: palette.text, family: UI_FONT}
  }
  if (block.type === "blockquote") {
    return {size: fontSize, lineHeight: fontSize * 1.42, gap: 18, weight: 600, color: palette.secondary, family: QUOTE_FONT}
  }
  if (block.type === "list_item") {
    return {size: Math.max(fontSize - 1, 16), lineHeight: fontSize * 1.38, gap: 7, weight: 550, color: palette.secondary, family: UI_FONT}
  }
  return {size: fontSize, lineHeight: fontSize * 1.42, gap: 14, weight: 500, color: palette.secondary, family: UI_FONT}
}

function layoutBlocks(context, blocks, fontSize, palette, bodyWidth) {
  let y = 0
  const layout = []

  blocks.forEach(block => {
    const style = blockStyle(block, fontSize, palette)
    context.font = `${style.weight} ${style.size}px ${style.family}`
    const markerGap = Math.max(Math.round(style.size * 0.34), 16)
    const indent = block.type === "list_item"
      ? Math.max(Math.ceil(context.measureText(block.marker).width + markerGap), 52)
      : 0
    const lines = wrapText(context, block.text, bodyWidth - indent)
    layout.push({block, style, indent, lines, y})
    y += lines.length * style.lineHeight + style.gap
  })

  return {layout, height: Math.max(y - (layout.at(-1)?.style.gap || 0), 0)}
}

function nodeLayout(context, slide, palette, frame) {
  const blocks = normalizedBlocks(slide)
  return FONT_SIZES.map(fontSize => layoutBlocks(context, blocks, fontSize, palette, frame.bodyWidth)).find(result => result.height <= frame.bodyMaxY - frame.bodyStartY) || layoutBlocks(context, blocks, FONT_SIZES[FONT_SIZES.length - 1], palette, frame.bodyWidth)
}

function drawNode(context, slide, palette, frame) {
  const {layout, height} = nodeLayout(context, slide, palette, frame)
  const bodyHeight = frame.bodyMaxY - frame.bodyStartY
  const startY = frame.bodyStartY + Math.max(Math.floor((bodyHeight - height) / 2), 0)

  layout.forEach(({block, style, indent, lines, y}) => {
    context.font = `${style.weight} ${style.size}px ${style.family}`
    context.fillStyle = style.color
    context.globalAlpha = block.type === "blockquote" ? 0.96 : 0.94
    lines.forEach((line, index) => {
      const quote = block.type === "blockquote" && index === 0 ? "“" : ""
      const closingQuote = block.type === "blockquote" && index === lines.length - 1 ? "”" : ""
      const baseline = startY + y + index * style.lineHeight

      if (block.type === "list_item" && index === 0) {
        context.fillText(block.marker, frame.bodyX, baseline)
      }

      context.fillText(`${quote}${line}${closingQuote}`, frame.bodyX + indent, baseline)
    })
    context.globalAlpha = 1
    y += lines.length * style.lineHeight + style.gap
  })
}

function titleLayout(context, title, palette, maxWidth = 820) {
  const sizes = [80, 76, 72, 68, 64, 60, 56, 52, 48, 44, 40, 36, 32]
  for (const size of sizes) {
    context.font = `900 ${size}px ${UI_FONT}`
    const lines = wrapText(context, cleanInlineMarkdown(title), maxWidth)
    if (lines.length * size * 1.18 <= 360) return {size, lines, lineHeight: size * 1.18}
  }
  const size = 32
  context.font = `900 ${size}px ${UI_FONT}`
  return {size, lines: wrapText(context, cleanInlineMarkdown(title), maxWidth), lineHeight: size * 1.18}
}

function supportingLayout(context, body, maxWidth, maxHeight, options = {}) {
  const sizes = options.sizes || [30, 28, 26, 24, 22, 20, 18]
  const family = options.family || UI_FONT
  const weight = options.weight || 600
  const text = cleanInlineMarkdown(body)

  for (const size of sizes) {
    const lineHeight = size * 1.42
    context.font = `${weight} ${size}px ${family}`
    const lines = wrapText(context, text, maxWidth)
    if (lines.length * lineHeight <= maxHeight) return {size, lineHeight, lines, family, weight}
  }

  const size = sizes.at(-1)
  const lineHeight = size * 1.42
  context.font = `${weight} ${size}px ${family}`
  return {size, lineHeight, lines: wrapText(context, text, maxWidth), family, weight}
}

function drawCover(context, slide, palette, frame, textColor = palette.text) {
  const title = titleLayout(context, slide.title, palette, frame.bodyWidth)
  const titleHeight = title.lines.length * title.lineHeight
  const titleAreaStart = frame.video ? 610 : 430
  const titleAreaHeight = frame.video ? 390 : 430
  const titleStartY = titleAreaStart + Math.floor((titleAreaHeight - titleHeight) / 2) + title.size
  context.fillStyle = textColor
  context.font = `900 ${title.size}px ${UI_FONT}`
  title.lines.forEach((line, index) => context.fillText(line, frame.bodyX, titleStartY + index * title.lineHeight))

  const lastTitleBaseline = titleStartY + Math.max(title.lines.length - 1, 0) * title.lineHeight
  const accentY = lastTitleBaseline + Math.max(Math.round(title.size * 0.72), 38)
  context.fillStyle = palette.accent
  context.fillRect(frame.bodyX, accentY, 220, 7)

  if (cleanInlineMarkdown(slide.body)) {
    const bodyStartY = accentY + 62
    const body = supportingLayout(
      context,
      slide.body,
      frame.bodyWidth,
      Math.max(frame.bodyMaxY - bodyStartY, 80),
      {sizes: frame.video ? [34, 32, 30, 28, 26, 24, 22] : [28, 26, 24, 22, 20, 18]}
    )
    context.fillStyle = textColor
    context.globalAlpha = 0.82
    context.font = `${body.weight} ${body.size}px ${body.family}`
    body.lines.forEach((line, index) => {
      context.fillText(line, frame.bodyX, bodyStartY + index * body.lineHeight)
    })
    context.globalAlpha = 1
  }
}

function drawQuote(context, slide, palette, frame) {
  const sizes = [72, 68, 64, 60, 56, 52, 48, 44, 40, 36, 32]
  const quoteText = cleanInlineMarkdown(slide.title)
  let quote = null

  for (const size of sizes) {
    context.font = `700 ${size}px ${QUOTE_FONT}`
    const lines = wrapText(context, quoteText, frame.bodyWidth)
    if (lines.length * size * 1.18 <= 560) {
      quote = {size, lines, lineHeight: size * 1.18}
      break
    }
  }

  quote ||= {size: 32, lines: [quoteText], lineHeight: 38}
  const quoteHeight = quote.lines.length * quote.lineHeight
  const quoteAreaStart = frame.video ? 290 : 290
  const quoteAreaHeight = frame.video ? 560 : 560
  const contentHeight = quoteHeight + (frame.video ? 172 : 80)
  const contentStart = frame.video
    ? quoteAreaStart + Math.max(Math.floor((frame.bodyMaxY - quoteAreaStart - contentHeight) / 2), 0)
    : quoteAreaStart
  const quoteStartY = contentStart + (frame.video ? quote.size : Math.floor((quoteAreaHeight - quoteHeight) / 2) + quote.size)
  context.fillStyle = palette.text
  context.font = `700 ${quote.size}px ${QUOTE_FONT}`
  quote.lines.forEach((line, index) => {
    const opening = index === 0 ? "“" : ""
    const closing = index === quote.lines.length - 1 ? "”" : ""
    context.fillText(`${opening}${line}${closing}`, frame.bodyX, quoteStartY + index * quote.lineHeight)
  })
  context.fillStyle = palette.accent
  const bodyStart = frame.video ? contentStart + quoteHeight + 92 : 930
  context.fillRect(frame.bodyX, bodyStart - 72, 240, 8)

  if (cleanInlineMarkdown(slide.body)) {
    const body = supportingLayout(
      context,
      slide.body,
      frame.bodyWidth,
      Math.max(frame.bodyMaxY - bodyStart, 80),
      {sizes: frame.video ? [32, 30, 28, 26, 24, 22, 20] : [28, 26, 24, 22, 20, 18]}
    )
    context.fillStyle = palette.secondary
    context.font = `${body.weight} ${body.size}px ${body.family}`
    body.lines.forEach((line, index) => {
      context.fillText(line, frame.bodyX, bodyStart + index * body.lineHeight)
    })
  }
}

function drawCta(context, slide, palette, logo, frame) {
  if (logo) context.drawImage(logo, 420, frame.video ? 520 : 360, 240, 240)
  context.fillStyle = palette.text
  context.textAlign = "center"
  const title = cleanInlineMarkdown(slide.title || "Continue on RationalGrid.ai")
  context.font = `900 54px ${UI_FONT}`
  const lines = wrapText(context, title, 780)
  const startY = frame.video ? 930 : 760
  lines.forEach((line, index) => context.fillText(line, 540, startY + index * 66))
  if (cleanInlineMarkdown(slide.body)) {
    const bodyStartY = startY + lines.length * 66 + 38
    const body = supportingLayout(context, slide.body, 780, frame.bodyMaxY - bodyStartY)
    context.font = `${body.weight} ${body.size}px ${body.family}`
    context.fillStyle = palette.secondary
    body.lines.forEach((line, index) => {
      context.fillText(line, 540, bodyStartY + index * body.lineHeight)
    })
  }
  context.textAlign = "left"
}

function drawFooter(context, slideIndex, slideCount, palette, frame, mutedColor = palette.muted) {
  context.strokeStyle = palette.border
  context.beginPath()
  context.moveTo(130, frame.video ? 1738 : 1210)
  context.lineTo(950, frame.video ? 1738 : 1210)
  context.stroke()
  context.fillStyle = mutedColor
  context.font = `700 ${frame.video ? 22 : 18}px ${UI_FONT}`
  context.fillText(`${slideIndex} / ${slideCount} · Learn more at rationalgrid.ai`, 130, frame.video ? 1790 : 1248)
}

function drawImageCover(context, image, width, height) {
  const scale = Math.max(width / image.naturalWidth, height / image.naturalHeight)
  const drawWidth = image.naturalWidth * scale
  const drawHeight = image.naturalHeight * scale
  context.drawImage(image, (width - drawWidth) / 2, (height - drawHeight) / 2, drawWidth, drawHeight)
}

function drawSlide(canvas, slide, slideIndex, slideCount, style, logo, videoCoverImage, video) {
  const context = canvas.getContext("2d")
  const palette = paletteFor(style)
  const coverSlide = slideIndex === 1 && (slide.kind === "cover" || slide.kind === "node_title")
  const frame = {
    video,
    height: video ? VIDEO_HEIGHT : IMAGE_HEIGHT,
    bodyX: 130,
    bodyWidth: 820,
    bodyStartY: video ? 350 : 240,
    bodyMaxY: video ? 1620 : 1160,
  }
  canvas.width = WIDTH
  canvas.height = frame.height
  context.clearRect(0, 0, WIDTH, frame.height)
  drawBackground(context, palette, frame)

  if (slide.kind === "cta" || slide.label === "Learn more") {
    drawCta(context, slide, palette, logo, frame)
    return
  }

  if (coverSlide && video && videoCoverImage) {
    context.save()
    roundedRect(context, 54, 64, 972, 1792, 48)
    context.clip()
    drawImageCover(context, videoCoverImage, WIDTH, frame.height)
    context.fillStyle = "rgba(2, 6, 23, 0.58)"
    context.fillRect(0, 0, WIDTH, frame.height)
    context.restore()
  }

  const coverPhoto = coverSlide && video && videoCoverImage
  const coverTextColor = coverPhoto ? "#fff7ed" : palette.text
  const coverMutedColor = coverPhoto ? "rgba(255,247,237,0.82)" : palette.muted
  drawHeader(context, palette, frame, coverPhoto ? "#fff7ed" : palette.text)
  if (slide.kind === "cover" || slide.kind === "node_title") drawCover(context, slide, palette, frame, coverTextColor)
  else if (slide.kind === "quote" || slide.kind === "highlight") drawQuote(context, slide, palette, frame)
  else drawNode(context, slide, palette, frame)
  drawFooter(context, slideIndex, slideCount, palette, frame, coverMutedColor)
}

function canvasBlob(canvas) {
  return new Promise(resolve => canvas.toBlob(resolve, "image/png"))
}

function copyCanvas(source, target) {
  if (!(source instanceof HTMLCanvasElement) || !(target instanceof HTMLCanvasElement)) return
  target.width = source.width
  target.height = source.height
  const context = target.getContext("2d")
  context.clearRect(0, 0, target.width, target.height)
  context.drawImage(source, 0, 0)
}

function loadImage(source) {
  return new Promise(resolve => {
    const image = new Image()
    if (/^https?:\/\//.test(source)) image.crossOrigin = "anonymous"
    image.onload = () => resolve(image)
    image.onerror = () => resolve(null)
    image.src = source
  })
}

function cacheBustedUrl(source) {
  const separator = source.includes("?") ? "&" : "?"
  return `${source}${separator}browser_frames=${Date.now()}`
}

export const CanvasSlideRenderer = {
  mounted() {
    this.root = document.getElementById(this.el.dataset.rootId)
    if (!this.root) return

    this.rendering = false
    this.renderAgain = false
    this.uploadingFrames = false
    this.uploadedFrameFingerprint = null
    this.previewClickHandler = event => {
      const uploadButton = event.target.closest("[data-browser-render-upload]")
      if (uploadButton && this.root.contains(uploadButton)) {
        event.preventDefault()
        this.uploadFrames()
        return
      }

      const control = event.target.closest("[data-carousel-preview]")
      if (!control || !this.root.contains(control)) return

      const preview = document.getElementById(control.dataset.previewTarget)
      const canvas = document.getElementById(control.dataset.previewCanvas)
      if (preview && canvas) copyCanvas(canvas, preview)

      this.root.querySelectorAll("[data-carousel-preview]").forEach(item => {
        item.classList.remove("ring-2", "ring-sky-400/80")
      })
      control.classList.add("ring-2", "ring-sky-400/80")
    }
    this.root.addEventListener("click", this.previewClickHandler)
    this.rootObserver = new MutationObserver(() => this.renderAll())
    this.rootObserver.observe(this.root, {
      attributes: true,
      attributeFilter: ["data-slides", "data-selected-indexes", "data-preview-slide"],
      childList: true,
      subtree: true,
    })
    this.renderAll()
  },

  destroyed() {
    this.rootObserver?.disconnect()
    this.root?.removeEventListener("click", this.previewClickHandler)
  },

  updated() {
    this.renderAll()
  },

  async renderAll() {
    if (this.rendering) {
      this.renderAgain = true
      return
    }

    this.rendering = true
    try {
      if (!this.root) return
      const slides = JSON.parse(this.root.dataset.slides || "[]")
      const style = this.root.dataset.style || "editorial_dark"
      const video = this.root.dataset.videoFrame === "true"
      const logo = await loadImage(this.root.dataset.logoSrc || "/images/rg_logo.webp")
      const videoCoverImage = video && this.root.dataset.videoCoverImageUrl
        ? await loadImage(this.root.dataset.videoCoverImageUrl)
        : null
      const targets = this.root.querySelectorAll("[data-canvas-slide]")

      targets.forEach(target => {
        const index = Number(target.dataset.slideIndex)
        const slide = slides[index - 1]
        const canvas = target
        if (!slide || !canvas) return
        drawSlide(canvas, slide, index, slides.length, style, logo, videoCoverImage, video)
      })

      const previewIndex = Number(this.root.dataset.previewSlide || 1)
      const previewCanvas = Array.from(targets).find(
        target => Number(target.dataset.slideIndex) === previewIndex
      )
      const mainPreview = document.getElementById(this.root.dataset.mainPreviewId)
      if (previewCanvas && mainPreview) copyCanvas(previewCanvas, mainPreview)

      const status = this.root.querySelector("[data-browser-render-status]")
      const fingerprint = `${this.root.dataset.slides}|${style}|${this.root.dataset.videoFrame || ""}|${this.root.dataset.videoCoverImageUrl || ""}|${this.root.dataset.selectedIndexes || ""}`
      if (this.root.dataset.artifactsReady === "true" && !this.uploadedFrameFingerprint) {
        this.uploadedFrameFingerprint = fingerprint
      }
      if (this.uploadedFrameFingerprint !== fingerprint) {
        const uploadButton = this.root.querySelector("[data-browser-render-upload]")
        if (uploadButton) {
          uploadButton.disabled = false
          uploadButton.textContent = "Save finished assets"
        }
        if (status) status.textContent = "Unsaved browser preview"
      } else {
        const uploadButton = this.root.querySelector("[data-browser-render-upload]")
        if (uploadButton) {
          uploadButton.disabled = true
          uploadButton.textContent = "Assets saved"
        }
        if (status) status.textContent = "Finished assets saved"
      }

      if (this.root.dataset.videoPreviewId) {
        if (this.uploadedFrameFingerprint !== fingerprint && !this.uploadingFrames) {
          await this.uploadFrames({automatic: true, fingerprint})
        }
      }
    } catch (_error) {
      const status = this.root?.querySelector("[data-browser-render-status]")
      if (status) status.textContent = "Preview fallback"
      this.loadVideoFallback()
    } finally {
      this.rendering = false
      if (this.renderAgain) {
        this.renderAgain = false
        this.renderAll()
      }
    }
  },

  async uploadFrames(options = {}) {
    if (!this.root) return
    if (this.uploadingFrames) return
    const uploadButton = this.root.querySelector("[data-browser-render-upload]")
    if (!uploadButton) return
    const automatic = options.automatic === true
    const fingerprint = options.fingerprint || `${this.root.dataset.slides}|${this.root.dataset.style}|${this.root.dataset.videoFrame || ""}|${this.root.dataset.videoCoverImageUrl || ""}|${this.root.dataset.selectedIndexes || ""}`
    const targets = this.root.querySelectorAll("[data-canvas-slide]")
    const selectedIndexes = JSON.parse(this.root.dataset.selectedIndexes || "[]").map(Number)
    const frameIndexes = Array.from(targets)
      .map(target => Number(target.dataset.slideIndex))
      .filter(index => selectedIndexes.length === 0 || selectedIndexes.includes(index))
    const status = this.root.querySelector("[data-browser-render-status]")
    const uploadUrl = this.root.dataset.uploadUrl.startsWith("/api/")
      ? this.root.dataset.uploadUrl
      : `/api${this.root.dataset.uploadUrl}`
    this.uploadingFrames = true
    if (automatic) this.uploadedFrameFingerprint = fingerprint
    uploadButton.disabled = true
    if (!automatic) uploadButton.textContent = "Saving browser frames…"

    try {
      for (const index of frameIndexes) {
        const target = Array.from(targets).find(item => Number(item.dataset.slideIndex) === index)
        const canvas = target
        if (!canvas) continue
        const blob = await canvasBlob(canvas)
        const form = new FormData()
        form.append("artifact", blob, `slide-${index}.png`)
        const csrfToken = document.querySelector("meta[name='csrf-token']")?.getAttribute("content")
        const response = await fetch(`${uploadUrl}/${index}`, {
          method: "POST",
          headers: {accept: "application/json", "x-csrf-token": csrfToken || ""},
          body: form,
        })
        if (!response.ok) throw new Error(`Frame ${index} failed`)
      }

      if (status) {
        status.textContent = this.root.dataset.videoPreviewId
          ? "Finished frames saved; video is ready"
          : "Finished PNG assets saved"
      }
      uploadButton.textContent = "Assets saved"
      this.uploadedFrameFingerprint = fingerprint
      this.pushEvent("artifacts_saved", {asset_id: this.root.dataset.assetId})
      this.reloadVideoFromBrowserFrames()
    } catch (_error) {
      this.uploadedFrameFingerprint = null
      if (status) status.textContent = "Could not save browser frames"
      uploadButton.textContent = "Retry saving assets"
      uploadButton.disabled = false
      this.loadVideoFallback()
    } finally {
      this.uploadingFrames = false
    }
  },

  reloadVideoFromBrowserFrames() {
    const videoId = this.root?.dataset.videoPreviewId
    if (!videoId) return

    const video = document.getElementById(videoId)
    const source = video?.dataset.browserFrameVideoUrl
    if (!video || !source) return

    video.src = cacheBustedUrl(source)
    video.load()
  },

  loadVideoFallback() {
    const videoId = this.root?.dataset.videoPreviewId
    if (!videoId) return

    const video = document.getElementById(videoId)
    const source = video?.dataset.browserFrameVideoUrl
    if (!video || !source || video.src) return

    video.src = source
    video.load()
  },
}
