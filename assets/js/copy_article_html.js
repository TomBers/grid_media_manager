export const CopyArticleHTML = {
  mounted() {
    this.button = this.el.querySelector("button")
    this.status = this.el.querySelector("[role=status]")
    this.copy = async () => {
      const source = document.getElementById(this.el.dataset.source)
      if (!source) return
      const html = source.innerHTML
      const plain = this.plainText(source.content)
      this.button.disabled = true
      this.status.textContent = "Copying…"
      try {
        if (!navigator.clipboard?.write || !window.ClipboardItem) throw new Error("Unavailable")
        await navigator.clipboard.write([new ClipboardItem({
          "text/html": new Blob([html], {type: "text/html"}),
          "text/plain": new Blob([plain], {type: "text/plain"}),
        })])
        this.status.textContent = "Copied. Paste into the Substack post body with ⌘V or Ctrl+V."
      } catch (_error) {
        const copied = this.copyFallback(html, plain)
        this.status.textContent = copied
          ? "Copied. Paste into the Substack post body with ⌘V or Ctrl+V."
          : "Copy was blocked. Open the formatted document, select its text, and copy with ⌘C or Ctrl+C."
      } finally {
        this.button.disabled = false
      }
    }
    this.button.addEventListener("click", this.copy)
  },

  copyFallback(html, plain) {
    const selection = window.getSelection()
    const ranges = Array.from({length: selection.rangeCount}, (_, index) => selection.getRangeAt(index).cloneRange())
    const container = document.createElement("div")
    container.innerHTML = html
    container.style.cssText = "position:fixed;left:-10000px;top:0"
    document.body.appendChild(container)
    const range = document.createRange()
    range.selectNodeContents(container)
    selection.removeAllRanges()
    selection.addRange(range)
    let handled = false
    const copyEvent = event => {
      if (!event.clipboardData) return
      event.preventDefault()
      event.clipboardData.setData("text/html", html)
      event.clipboardData.setData("text/plain", plain)
      handled = true
    }
    document.addEventListener("copy", copyEvent)
    try {
      return document.execCommand("copy") && handled
    } catch (_error) {
      return false
    } finally {
      document.removeEventListener("copy", copyEvent)
      container.remove()
      selection.removeAllRanges()
      ranges.forEach(saved => selection.addRange(saved))
    }
  },

  plainText(node) {
    if (node.nodeType === Node.TEXT_NODE) return node.nodeValue
    const text = Array.from(node.childNodes, child => this.plainText(child)).join("")
    if (node.nodeName === "BR" || node.nodeName === "HR") return "\n"
    if (node.nodeName === "LI") return `• ${text}\n`
    if (/^(P|H[1-6]|BLOCKQUOTE|UL|OL)$/.test(node.nodeName)) return `${text}\n\n`
    return text
  },

  destroyed() {
    this.button.removeEventListener("click", this.copy)
  },
}
