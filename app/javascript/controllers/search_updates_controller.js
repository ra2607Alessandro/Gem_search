import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="search-updates"
export default class extends Controller {
  static targets = ["status", "results", "aiResponse"]
  static values = {
    searchId: String,
    streamUrl: String
  }

  connect() {
    this.connectToStream()
  }

  disconnect() {
    this.disconnectFromStream()
  }

  // Connect to Server-Sent Events stream
  connectToStream() {
    if (!this.hasSearchIdValue) return

    const streamUrl = this.streamUrlValue || `/searches/${this.searchIdValue}/stream_status`

    this.eventSource = new EventSource(streamUrl)

    this.eventSource.onmessage = this.handleMessage.bind(this)
    this.eventSource.onerror = this.handleError.bind(this)

    console.log(`Connected to search stream: ${streamUrl}`)
  }

  // Disconnect from stream
  disconnectFromStream() {
    if (this.eventSource) {
      this.eventSource.close()
      this.eventSource = null
      console.log('Disconnected from search stream')
    }
  }

  // Handle incoming messages
  handleMessage(event) {
    try {
      const data = JSON.parse(event.data)
      console.log('Received search update:', data)

      // Update progress controller if present
      this.updateProgress(data)

      // Handle different message types
      if (data.status) {
        this.handleStatusUpdate(data)
      }

      if (data.completed) {
        this.handleCompletion(data)
      }

    } catch (error) {
      console.error('Error parsing search update:', error)
    }
  }

  // Handle stream errors
  handleError(event) {
    console.error('Search stream error:', event)

    // Attempt to reconnect after a delay
    setTimeout(() => {
      console.log('Attempting to reconnect to search stream...')
      this.disconnectFromStream()
      this.connectToStream()
    }, 5000)
  }

  // Update progress controller
  updateProgress(data) {
    const progressController = this.application.getControllerForElementAndIdentifier(
      this.element,
      'progress'
    )

    if (progressController) {
      progressController.handleStatus(data.status, data)
    }
  }

  // Handle status updates
  handleStatusUpdate(data) {
    // Update status display
    if (this.hasStatusTarget) {
      this.updateStatusContent(data)
    }

    // Refresh results if sources found
    if (data.sources_found > 0) {
      this.refreshResults()
    }
  }

  // Handle search completion
  handleCompletion(data) {
    console.log('Search completed:', data)

    // Disconnect from stream
    this.disconnectFromStream()

    // Refresh all content
    this.refreshResults()
    this.refreshAiResponse()

    // Show completion message
    this.showCompletionNotification(data)
  }

  // Update status content
  updateStatusContent(data) {
    // This would be handled by Turbo Streams from the server
    // For now, just log the update
    console.log('Status updated:', data)
  }

  // Refresh search results
  refreshResults() {
    if (this.hasResultsTarget) {
      // Trigger a refresh of the results section
      // This could be done via Turbo or by making an AJAX request
      console.log('Refreshing search results...')
    }
  }

  // Refresh AI response
  refreshAiResponse() {
    if (this.hasAiResponseTarget) {
      console.log('Refreshing AI response...')
    }
  }

  // Show completion notification
  showCompletionNotification(data) {
    // Create a temporary notification
    const notification = document.createElement('div')
    notification.className = 'fixed top-4 right-4 bg-green-500 text-white px-6 py-3 rounded-lg shadow-lg z-50'
    notification.innerHTML = `
      <div class="flex items-center">
        <span class="text-lg mr-2">✅</span>
        <span>Search completed! Found ${data.sources_found || 0} sources.</span>
      </div>
    `

    document.body.appendChild(notification)

    // Auto-remove after 5 seconds
    setTimeout(() => {
      if (notification.parentNode) {
        notification.remove()
      }
    }, 5000)
  }

  // Manual refresh (for debugging)
  refresh() {
    this.disconnectFromStream()
    this.connectToStream()
  }

  // Get stream URL
  get streamUrl() {
    return this.streamUrlValue || `/searches/${this.searchIdValue}/stream_status`
  }
}
