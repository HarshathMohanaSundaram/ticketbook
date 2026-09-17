import { Controller } from "@hotwired/stimulus"

// Tracks which seats are pencilled in before submit. Nothing here decides
// availability -- the server re-adjudicates every seat under a row lock, so this
// is presentation only.
export default class extends Controller {
  static targets = ["seat", "input", "count", "total", "submit", "notice"]
  static values = { maxSeats: Number }

  connect() {
    this.selected = new Map()   // seatId -> price in paise
    this.render()
  }

  toggle(event) {
    const seat = event.currentTarget
    const id = seat.dataset.seatId

    if (this.selected.has(id)) {
      this.selected.delete(id)
    } else if (this.selected.size >= this.maxSeatsValue) {
      this.flashLimit(seat)
      return
    } else {
      this.selected.set(id, Number(seat.dataset.price))
    }

    seat.setAttribute("aria-pressed", this.selected.has(id))
    this.render()
  }

  render() {
    const totalPaise = [...this.selected.values()].reduce((sum, paise) => sum + paise, 0)

    this.countTarget.textContent = this.selected.size
    this.totalTarget.textContent = formatINR(totalPaise)
    this.inputTarget.value = [...this.selected.keys()].join(",")
    this.submitTarget.disabled = this.selected.size === 0
  }

  // animate-pulse alone was a 2s opacity fade cut off after 600ms -- technically
  // running, practically invisible. A red ring plus a sentence says what happened.
  flashLimit(seat) {
    seat.classList.add("ring-2", "ring-red-500")
    this.noticeTarget.textContent = `You can hold at most ${this.maxSeatsValue} seats at a time.`
    this.noticeTarget.classList.remove("invisible")

    clearTimeout(this.noticeTimer)
    this.noticeTimer = setTimeout(() => {
      seat.classList.remove("ring-2", "ring-red-500")
      this.noticeTarget.classList.add("invisible")
    }, 2500)
  }

  // Turbo swaps pages without reloading, so a pending timer would outlive the page.
  disconnect() {
    clearTimeout(this.noticeTimer)
  }
}

function formatINR(paise) {
  return "₹" + (paise / 100).toLocaleString("en-IN", { maximumFractionDigits: 0 })
}
