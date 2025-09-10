import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// Connects to data-controller="search-updates"
export default class extends Controller {
  static targets = ["status", "results", "aiResponse"]

  // Refresh search results by reloading the Turbo Frame
  refreshResults() {
    if (!this.hasResultsTarget) return
    Turbo.visit(window.location.href, { frame: "search_results" })
  }

  // Refresh AI response by reloading the Turbo Frame
  refreshAiResponse() {
    if (!this.hasAiResponseTarget) return
    Turbo.visit(window.location.href, { frame: "ai_response" })
  }
}
