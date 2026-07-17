import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["content"]
  static values = {
    url: String,
    interval: Number,
    limit: Number
  }

  connect() {
    this.refresh()
    this.startPolling()
  }

  disconnect() {
    this.stopPolling()
  }

  async refresh() {
    if (!this.urlValue) return

    try {
      const response = await fetch(this.buildMenuUrl(), {
        headers: { Accept: "application/json" },
        credentials: "same-origin"
      })

      if (!response.ok) return

      const payload = await response.json()
      if (this.hasContentTarget && typeof payload.menu_html === "string") {
        this.contentTarget.innerHTML = payload.menu_html
      }

      const nextInterval = Number(payload.polling_interval_seconds)
      if (Number.isFinite(nextInterval) && nextInterval > 0 && nextInterval !== this.intervalValue) {
        this.intervalValue = nextInterval
        this.startPolling()
      }
    } catch (_error) {
      // Ignore transient polling failures and retry on the next interval.
    }
  }

  startPolling() {
    this.stopPolling()

    const interval = this.normalizedIntervalSeconds()
    this.pollingTimer = window.setInterval(() => {
      this.refresh()
    }, interval * 1000)
  }

  stopPolling() {
    if (!this.pollingTimer) return

    window.clearInterval(this.pollingTimer)
    this.pollingTimer = null
  }

  buildMenuUrl() {
    const url = new URL(this.urlValue, window.location.origin)

    if (this.hasLimitValue && this.limitValue > 0) {
      url.searchParams.set("limit", String(this.limitValue))
    }

    return url.toString()
  }

  normalizedIntervalSeconds() {
    const interval = this.intervalValue
    return Number.isFinite(interval) && interval > 0 ? interval : 60
  }
}