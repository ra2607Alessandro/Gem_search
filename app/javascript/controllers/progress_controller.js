import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="progress"
export default class extends Controller {
  static targets = ["bar", "percentage", "status", "spinner"]

  static values = {
    current: { type: Number, default: 0 },
    max: { type: Number, default: 100 }
  }

  connect() {
    this.animateProgress()
  }

  // Update progress value
  setProgress(value) {
    this.currentValue = Math.min(Math.max(value, 0), this.maxValue)
    this.animateProgress()
    this.updateDisplay()
  }

  // Animate progress bar
  animateProgress() {
    if (this.hasBarTarget) {
      this.barTarget.style.width = `${this.currentValue}%`
    }
  }

  // Update text displays
  updateDisplay() {
    if (this.hasPercentageTarget) {
      this.percentageTarget.textContent = `${Math.round(this.currentValue)}%`
    }
  }

  // Update status message
  setStatus(message) {
    if (this.hasStatusTarget) {
      this.statusTarget.textContent = message
    }
  }

  // Show/hide loading spinner
  setLoading(loading) {
    if (this.hasSpinnerTarget) {
      if (loading) {
        this.spinnerTarget.classList.remove('hidden')
      } else {
        this.spinnerTarget.classList.add('hidden')
      }
    }
  }

  // Handle different status types
  handleStatus(status, data = {}) {
    switch (status) {
      case 'pending':
        this.setProgress(0)
        this.setStatus('Preparing your search...')
        this.setLoading(true)
        break

      case 'processing':
        const progress = data.progress || 0
        this.setProgress(progress)
        this.setStatus(`Searching... ${data.sources_found || 0} sources found`)
        this.setLoading(true)
        break

      case 'completed':
        this.setProgress(100)
        this.setStatus(`Search completed! ${data.sources_found || 0} sources found`)
        this.setLoading(false)
        this.showCompletion()
        break

      case 'failed':
        this.setProgress(0)
        this.setStatus('Search failed. Please try again.')
        this.setLoading(false)
        this.showError()
        break

      default:
        this.setStatus('Unknown status')
    }
  }

  // Show completion animation
  showCompletion() {
    if (this.hasBarTarget) {
      this.barTarget.classList.add('bg-green-500')
      this.barTarget.classList.remove('bg-blue-600')
    }

    // Add completion checkmark effect
    setTimeout(() => {
      if (this.hasStatusTarget) {
        this.statusTarget.innerHTML = '✅ Search completed successfully!'
      }
    }, 500)
  }

  // Show error state
  showError() {
    if (this.hasBarTarget) {
      this.barTarget.classList.add('bg-red-500')
      this.barTarget.classList.remove('bg-blue-600')
    }

    if (this.hasStatusTarget) {
      this.statusTarget.innerHTML = '❌ Search failed'
    }
  }

  // Pulse animation for active processing
  pulse() {
    if (this.hasBarTarget && this.currentValue > 0 && this.currentValue < 100) {
      this.barTarget.classList.add('animate-pulse')
    } else {
      this.barTarget.classList.remove('animate-pulse')
    }
  }

  // Auto-pulse every few seconds
  startAutoPulse() {
    this.pulseInterval = setInterval(() => {
      this.pulse()
    }, 2000)
  }

  // Stop auto-pulse
  stopAutoPulse() {
    if (this.pulseInterval) {
      clearInterval(this.pulseInterval)
      this.pulseInterval = undefined
    }
  }

  disconnect() {
    this.stopAutoPulse()
  }
}
