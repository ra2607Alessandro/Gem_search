import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="citation"
export default class extends Controller {
  static targets = ["preview", "link"]

  connect() {
    // Add hover listeners to citation links
    this.linkTargets.forEach(link => {
      link.addEventListener('mouseenter', this.showPreview.bind(this))
      link.addEventListener('mouseleave', this.hidePreview.bind(this))
    })
  }

  disconnect() {
    // Clean up event listeners
    this.linkTargets.forEach(link => {
      link.removeEventListener('mouseenter', this.showPreview)
      link.removeEventListener('mouseleave', this.hidePreview)
    })
  }

  // Show citation preview on hover
  showPreview(event) {
    const link = event.target
    const citationId = link.dataset.citationId

    if (!citationId) return

    // Create or update preview
    let preview = this.findOrCreatePreview(link)

    // Position preview near the link
    this.positionPreview(preview, link)

    // Load citation content if not already loaded
    if (!preview.dataset.loaded) {
      this.loadCitationContent(preview, citationId)
    }

    preview.classList.remove('hidden')
  }

  // Hide citation preview
  hidePreview(event) {
    const preview = this.element.querySelector('.citation-preview')
    if (preview) {
      preview.classList.add('hidden')
    }
  }

  // Copy citation to clipboard
  copyCitation(event) {
    event.preventDefault()

    const link = event.target.closest('[data-citation-id]')
    if (!link) return

    const citationText = this.getCitationText(link)

    navigator.clipboard.writeText(citationText).then(() => {
      this.showCopyFeedback(link)
    }).catch(err => {
      console.error('Failed to copy citation:', err)
    })
  }

  // Scroll to source document
  scrollToSource(event) {
    event.preventDefault()

    const link = event.target.closest('[data-citation-id]')
    if (!link) return

    const sourceId = link.dataset.sourceId
    const sourceElement = document.getElementById(`source-${sourceId}`)

    if (sourceElement) {
      sourceElement.scrollIntoView({
        behavior: 'smooth',
        block: 'center'
      })

      // Highlight the source temporarily
      sourceElement.classList.add('bg-yellow-100')
      setTimeout(() => {
        sourceElement.classList.remove('bg-yellow-100')
      }, 2000)
    }
  }

  // Helper: Find or create preview element
  findOrCreatePreview(link) {
    let preview = this.element.querySelector('.citation-preview')

    if (!preview) {
      preview = document.createElement('div')
      preview.className = 'citation-preview hidden fixed z-50 bg-white border border-gray-300 rounded-lg shadow-lg p-4 max-w-sm'
      preview.innerHTML = `
        <div class="text-sm">
          <div class="font-medium text-gray-900 mb-2">Citation Preview</div>
          <div class="text-gray-600 loading">Loading...</div>
        </div>
      `
      this.element.appendChild(preview)
    }

    return preview
  }

  // Helper: Position preview near link
  positionPreview(preview, link) {
    const rect = link.getBoundingClientRect()
    const previewRect = preview.getBoundingClientRect()

    let top = rect.top - previewRect.height - 10
    let left = rect.left

    // Adjust if preview would go off-screen
    if (top < 10) {
      top = rect.bottom + 10
    }

    if (left + previewRect.width > window.innerWidth) {
      left = window.innerWidth - previewRect.width - 10
    }

    preview.style.top = `${top}px`
    preview.style.left = `${left}px`
  }

  // Helper: Load citation content
  loadCitationContent(preview, citationId) {
    // For now, we'll simulate loading citation content
    // In a real implementation, you might fetch this via AJAX
    const content = preview.querySelector('.loading')

    setTimeout(() => {
      content.innerHTML = `
        <div class="mb-2">
          <strong>Source:</strong> Example Website
        </div>
        <div class="mb-2">
          <strong>URL:</strong> <a href="#" class="text-blue-600 hover:text-blue-800">https://example.com/article</a>
        </div>
        <div class="text-xs text-gray-500">
          Click to view full source
        </div>
      `
      preview.dataset.loaded = 'true'
    }, 200)
  }

  // Helper: Get citation text for copying
  getCitationText(link) {
    const citationId = link.dataset.citationId
    const sourceId = link.dataset.sourceId

    return `Citation [${citationId}] from source ${sourceId}`
  }

  // Helper: Show copy feedback
  showCopyFeedback(link) {
    const originalText = link.textContent
    link.textContent = 'Copied!'
    link.classList.add('text-green-600')

    setTimeout(() => {
      link.textContent = originalText
      link.classList.remove('text-green-600')
    }, 1000)
  }
}
