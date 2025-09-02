import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="search-form"
export default class extends Controller {
  static targets = ["query", "goal", "rules", "submit", "queryCount", "goalCount", "rulesCount"]

  connect() {
    this.updateCharacterCounts()
  }

  // Auto-expand textareas as user types
  autoExpand(event) {
    const textarea = event.target
    textarea.style.height = 'auto'
    textarea.style.height = textarea.scrollHeight + 'px'
    this.updateCharacterCount(textarea)
  }

  // Update character count for a specific field
  updateCharacterCount(textarea) {
    const countTarget = this[`${textarea.dataset.field}CountTarget`]
    if (countTarget) {
      const current = textarea.value.length
      const max = textarea.getAttribute('maxlength') || 1000
      countTarget.textContent = `${current}/${max}`

      // Change color based on usage
      if (current > max * 0.9) {
        countTarget.classList.remove('text-gray-500')
        countTarget.classList.add('text-red-500')
      } else if (current > max * 0.7) {
        countTarget.classList.remove('text-gray-500', 'text-red-500')
        countTarget.classList.add('text-yellow-500')
      } else {
        countTarget.classList.remove('text-yellow-500', 'text-red-500')
        countTarget.classList.add('text-gray-500')
      }
    }
  }

  // Update all character counts
  updateCharacterCounts() {
    [this.queryTarget, this.goalTarget, this.rulesTarget].forEach(textarea => {
      if (textarea) this.updateCharacterCount(textarea)
    })
  }

  // Validate form before submission
  validate(event) {
    const query = this.queryTarget.value.trim()

    if (query.length < 3) {
      event.preventDefault()
      this.showError("Please enter a search query with at least 3 characters")
      return false
    }

    if (query.length > 1000) {
      event.preventDefault()
      this.showError("Search query is too long (maximum 1000 characters)")
      return false
    }

    return true
  }

  // Show error message
  showError(message) {
    // Remove existing error
    this.removeError()

    // Create error element
    const errorDiv = document.createElement('div')
    errorDiv.className = 'mt-2 text-red-600 text-sm error-message'
    errorDiv.textContent = message

    // Insert after submit button
    this.submitTarget.parentNode.insertBefore(errorDiv, this.submitTarget.nextSibling)

    // Auto-remove after 5 seconds
    setTimeout(() => this.removeError(), 5000)
  }

  // Remove error message
  removeError() {
    const error = this.element.querySelector('.error-message')
    if (error) error.remove()
  }

  // Handle form submission
  submit(event) {
    if (!this.validate(event)) return

    // Disable form and show loading state
    this.setLoadingState(true)

    // Auto-expand textareas one more time
    this.autoExpand({ target: this.queryTarget })
    if (this.goalTarget.value) this.autoExpand({ target: this.goalTarget })
    if (this.rulesTarget.value) this.autoExpand({ target: this.rulesTarget })
  }

  // Set loading state
  setLoadingState(loading) {
    const submitBtn = this.submitTarget

    if (loading) {
      submitBtn.disabled = true
      submitBtn.dataset.originalText = submitBtn.textContent
      submitBtn.textContent = "Searching..."
      submitBtn.classList.add('opacity-75', 'cursor-not-allowed')
    } else {
      submitBtn.disabled = false
      submitBtn.textContent = submitBtn.dataset.originalText || "Search the Web"
      submitBtn.classList.remove('opacity-75', 'cursor-not-allowed')
    }
  }

  // Reset form
  reset() {
    this.element.reset()
    this.setLoadingState(false)
    this.removeError()
    this.updateCharacterCounts()
  }
}
