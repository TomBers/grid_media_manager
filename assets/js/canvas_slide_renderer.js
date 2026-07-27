const WIDTH = 1080
const HEIGHT = 1350
const BODY_X = 130
const BODY_WIDTH = 820
const BODY_START_Y = 240
const BODY_MAX_Y = 1160
const BODY_HEIGHT = BODY_MAX_Y - BODY_START_Y
const UI_FONT = "Arial, Helvetica, sans-serif"
const QUOTE_FONT = "Georgia, Times New Roman, serif"
const FONT_SIZES = [136, 128, 120, 112, 104, 96, 88, 80, 72, 64, 56, 52, 48, 44, 40, 36, 32]

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

function drawBackground(context, palette) {
  const gradient = context.createLinearGradient(0, 0, WIDTH, HEIGHT)
  const colors = palette.canvas
  colors.forEach((color, index) => gradient.addColorStop(index / Math.max(colors.length - 1, 1), color))
  context.fillStyle = gradient
  context.fillRect(0, 0, WIDTH, HEIGHT)

  context.fillStyle = "rgba(255,255,255,0.035)"
  context.beginPath()
  context.arc(940, 170, 230, 0, Math.PI * 2)
  context.fill()
  context.beginPath()
  context.arc(110, 1190, 250, 0, Math.PI * 2)
  context.fill()

  context.fillStyle = palette.card
  roundedRect(context, 54, 54, 972, 1242, 44)
  context.fill()
  context.strokeStyle = palette.border
  context.lineWidth = 1
  context.stroke()

  context.fillStyle = palette.panel
  roundedRect(context, 82, 82, 916, 1186, 32)
  context.fill()
  context.strokeStyle = palette.border
  context.stroke()
}

function drawHeader(context, palette) {
  context.fillStyle = palette.text
  context.globalAlpha = 0.92
  context.font = `800 20px ${UI_FONT}`
  context.fillText("RationalGrid.ai", 130, 142)
  context.globalAlpha = 1
  context.strokeStyle = palette.border
  context.beginPath()
  context.moveTo(130, 176)
  context.lineTo(950, 176)
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

  return String(slide.body || "")
    .split(/\n{2,}/)
    .flatMap(text => sentenceGroups(text))
    .map(text => ({type: "paragraph", text}))
}

function wrapText(context, text, maxWidth) {
  const words = String(text || "").split(/\s+/).filter(Boolean)
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

function layoutBlocks(context, blocks, fontSize, palette) {
  let y = 0
  const layout = []

  blocks.forEach(block => {
    const style = blockStyle(block, fontSize, palette)
    context.font = `${style.weight} ${style.size}px ${style.family}`
    const indent = block.type === "list_item" || block.type === "blockquote" ? 30 : 0
    const lines = wrapText(context, block.text, BODY_WIDTH - indent)
    layout.push({block, style, indent, lines, y})
    y += lines.length * style.lineHeight + style.gap
  })

  return {layout, height: Math.max(y - (layout.at(-1)?.style.gap || 0), 0)}
}

function nodeLayout(context, slide, palette) {
  const blocks = normalizedBlocks(slide)
  return FONT_SIZES.map(fontSize => layoutBlocks(context, blocks, fontSize, palette)).find(result => result.height <= BODY_MAX_Y - BODY_START_Y) || layoutBlocks(context, blocks, FONT_SIZES[FONT_SIZES.length - 1], palette)
}

function drawNode(context, slide, palette) {
  const {layout, height} = nodeLayout(context, slide, palette)
  const startY = BODY_START_Y + Math.max(Math.floor((BODY_HEIGHT - height) / 2), 0)

  layout.forEach(({block, style, indent, lines, y}) => {
    context.font = `${style.weight} ${style.size}px ${style.family}`
    context.fillStyle = style.color
    context.globalAlpha = block.type === "blockquote" ? 0.96 : 0.94
    lines.forEach((line, index) => {
      const prefix = block.type === "list_item" && index === 0 ? `${block.marker}  ` : ""
      const quote = block.type === "blockquote" && index === 0 ? "“" : ""
      const closingQuote = block.type === "blockquote" && index === lines.length - 1 ? "”" : ""
      context.fillText(`${prefix}${quote}${line}${closingQuote}`, BODY_X + indent, startY + y + index * style.lineHeight)
    })
    context.globalAlpha = 1
    if (block.type === "blockquote") {
      context.fillStyle = palette.accent
      context.fillRect(BODY_X, startY + y - style.size, 5, lines.length * style.lineHeight)
    }
    y += lines.length * style.lineHeight + style.gap
  })
}

function titleLayout(context, title, palette) {
  const sizes = [80, 76, 72, 68, 64, 60, 56, 52, 48, 44, 40, 36, 32]
  for (const size of sizes) {
    context.font = `900 ${size}px ${UI_FONT}`
    const lines = wrapText(context, cleanInlineMarkdown(title), 820)
    if (lines.length * size * 1.18 <= 360) return {size, lines, lineHeight: size * 1.18}
  }
  const size = 32
  context.font = `900 ${size}px ${UI_FONT}`
  return {size, lines: wrapText(context, cleanInlineMarkdown(title), 820), lineHeight: size * 1.18}
}

function drawCover(context, slide, palette) {
  const title = titleLayout(context, slide.title, palette)
  const titleHeight = title.lines.length * title.lineHeight
  const titleStartY = 430 + Math.floor((430 - titleHeight) / 2) + title.size
  context.fillStyle = palette.text
  context.font = `900 ${title.size}px ${UI_FONT}`
  title.lines.forEach((line, index) => context.fillText(line, BODY_X, titleStartY + index * title.lineHeight))
  context.fillStyle = palette.accent
  context.fillRect(BODY_X, titleStartY + titleHeight + 46, 220, 7)
}

function drawQuote(context, slide, palette) {
  const sizes = [72, 68, 64, 60, 56, 52, 48, 44, 40, 36, 32]
  const quoteText = cleanInlineMarkdown(slide.title)
  let quote = null

  for (const size of sizes) {
    context.font = `700 ${size}px ${QUOTE_FONT}`
    const lines = wrapText(context, quoteText, 820)
    if (lines.length * size * 1.18 <= 560) {
      quote = {size, lines, lineHeight: size * 1.18}
      break
    }
  }

  quote ||= {size: 32, lines: [quoteText], lineHeight: 38}
  const quoteHeight = quote.lines.length * quote.lineHeight
  const quoteStartY = 290 + Math.floor((560 - quoteHeight) / 2) + quote.size
  context.fillStyle = palette.text
  context.font = `700 ${quote.size}px ${QUOTE_FONT}`
  quote.lines.forEach((line, index) => {
    const opening = index === 0 ? "“" : ""
    const closing = index === quote.lines.length - 1 ? "”" : ""
    context.fillText(`${opening}${line}${closing}`, BODY_X, quoteStartY + index * quote.lineHeight)
  })
  context.fillStyle = palette.accent
  context.fillRect(BODY_X, 930, 240, 8)
  context.fillStyle = palette.muted
  context.font = `800 23px ${UI_FONT}`
  wrapText(context, cleanInlineMarkdown(slide.body), 820).slice(0, 2).forEach((line, index) => context.fillText(line, BODY_X, 1010 + index * 34))
}

function drawCta(context, palette, logo) {
  if (logo) context.drawImage(logo, 420, 360, 240, 240)
  context.fillStyle = palette.text
  context.textAlign = "center"
  context.font = `900 48px ${UI_FONT}`
  context.fillText("Continue on", 540, 760)
  context.font = `900 54px ${UI_FONT}`
  context.fillText("RationalGrid.ai", 540, 830)
  context.textAlign = "left"
}

function drawFooter(context, slideIndex, slideCount, palette) {
  context.strokeStyle = palette.border
  context.beginPath()
  context.moveTo(130, 1210)
  context.lineTo(950, 1210)
  context.stroke()
  context.fillStyle = palette.muted
  context.font = `700 18px ${UI_FONT}`
  context.fillText(`${slideIndex} / ${slideCount} · Learn more at rationalgrid.ai`, 130, 1248)
}

function drawSlide(canvas, slide, slideIndex, slideCount, style, logo, coverCard) {
  const context = canvas.getContext("2d")
  const palette = paletteFor(style)
  canvas.width = WIDTH
  canvas.height = HEIGHT
  context.clearRect(0, 0, WIDTH, HEIGHT)
  drawBackground(context, palette)

  if (slide.kind === "cta" || slide.label === "Learn more") {
    drawCta(context, palette, logo)
    return
  }

  if (slide.kind === "cover" && coverCard) {
    context.drawImage(coverCard, 0, 0, WIDTH, HEIGHT)
    return
  }

  drawHeader(context, palette)
  if (slide.kind === "cover" || slide.kind === "node_title") drawCover(context, slide, palette)
  else if (slide.kind === "quote" || slide.kind === "highlight") drawQuote(context, slide, palette)
  else drawNode(context, slide, palette)
  drawFooter(context, slideIndex, slideCount, palette)
}

function canvasBlob(canvas) {
  return new Promise(resolve => canvas.toBlob(resolve, "image/png"))
}

function loadImage(source) {
  return new Promise(resolve => {
    const image = new Image()
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

      const image = document.getElementById(control.dataset.previewTarget)
      const canvas = document.getElementById(control.dataset.previewCanvas)
      if (image && canvas) image.src = canvas.toDataURL("image/png")
      else if (image && control.dataset.previewUrl) image.src = control.dataset.previewUrl

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
      const logo = await loadImage(this.root.dataset.logoSrc || "/images/rg_logo.webp")
      const coverCard = this.root.dataset.coverCardUrl
        ? await loadImage(this.root.dataset.coverCardUrl)
        : null
      const targets = this.root.querySelectorAll("[data-canvas-slide]")

      targets.forEach(target => {
        const index = Number(target.dataset.slideIndex)
        const slide = slides[index - 1]
        const canvas = target
        if (!slide || !canvas) return
        drawSlide(canvas, slide, index, slides.length, style, logo, coverCard)
        canvas.classList.remove("hidden")
        const image = target.parentElement?.querySelector("img")
        if (image) image.classList.add("hidden")
      })

      const previewIndex = Number(this.root.dataset.previewSlide || 1)
      const previewCanvas = Array.from(targets).find(
        target => Number(target.dataset.slideIndex) === previewIndex
      )
      const mainPreview = document.getElementById(this.root.dataset.mainPreviewId)
      if (previewCanvas && mainPreview) mainPreview.src = previewCanvas.toDataURL("image/png")

      const status = this.root.querySelector("[data-browser-render-status]")
      if (status) status.textContent = "Browser-rendered preview"

      if (this.root.dataset.videoPreviewId) {
        const fingerprint = `${this.root.dataset.slides}|${style}|${this.root.dataset.coverCardUrl || ""}`
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
    const fingerprint = options.fingerprint || `${this.root.dataset.slides}|${this.root.dataset.style}|${this.root.dataset.coverCardUrl || ""}`
    const slides = JSON.parse(this.root.dataset.slides || "[]")
    const frameIndexes = slides.map((_slide, index) => index + 1)
    const targets = this.root.querySelectorAll("[data-canvas-slide]")
    const status = this.root.querySelector("[data-browser-render-status]")
    const uploadUrl = this.root.dataset.uploadUrl.startsWith("/api/")
      ? this.root.dataset.uploadUrl
      : `/api${this.root.dataset.uploadUrl}`
    this.uploadingFrames = true
    uploadButton.disabled = true
    if (!automatic) uploadButton.textContent = "Saving browser frames…"

    try {
      for (const index of frameIndexes) {
        const target = Array.from(targets).find(item => Number(item.dataset.slideIndex) === index)
        const canvas = target
        if (!canvas) continue
        const blob = await canvasBlob(canvas)
        const form = new FormData()
        form.append("slide", String(index))
        form.append("frame", blob, `slide-${index}.png`)
        const response = await fetch(uploadUrl, {
          method: "POST",
          headers: {accept: "application/json"},
          body: form,
        })
        if (!response.ok) throw new Error(`Frame ${index} failed`)
      }

      if (status) {
        status.textContent = this.root.dataset.videoPreviewId
          ? "Video rebuilt from browser-rendered frames"
          : "Browser frames saved for images and video"
      }
      uploadButton.textContent = "Browser frames saved"
      this.uploadedFrameFingerprint = fingerprint
      this.reloadVideoFromBrowserFrames()
    } catch (_error) {
      if (status) status.textContent = "Could not save browser frames"
      uploadButton.textContent = "Retry browser render"
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
