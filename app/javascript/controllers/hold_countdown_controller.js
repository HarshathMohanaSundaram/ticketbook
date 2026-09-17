import { Controller } from "@hotwired/stimulus"

// The server owns the deadline. This only renders the remaining time and, when it
// reaches zero, asks the server what happened rather than assuming the hold died.
export default class extends Controller {
  static targets = ["clock"]
  static values = { expiresAt: String }

  connect() {
    this.tick()
    this.timer = setInterval(() => this.tick(), 1000)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  tick() {
    const remaining = Math.max(0, new Date(this.expiresAtValue) - Date.now())

    this.clockTarget.textContent = format(remaining)
    this.clockTarget.classList.toggle("text-red-600", remaining < 60_000)

    if (remaining === 0) {
      clearInterval(this.timer)
      window.location.reload()
    }
  }
}

function format(ms) {
  const total = Math.floor(ms / 1000)
  return `${Math.floor(total / 60)}:${String(total % 60).padStart(2, "0")}`
}
