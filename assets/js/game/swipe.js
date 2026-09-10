// Swipe-to-step for touch screens: each touch on `zone` that travels far
// enough becomes exactly one step in its dominant direction, reported via
// `onSwipe(dir)` ("up" | "down" | "left" | "right"). Holding or dragging
// further within the same touch does nothing more, so the player never
// overshoots.

// Roughly one map cell on a phone-sized map.
const SWIPE_THRESHOLD_PX = 24

export class Swipe {
  constructor(zone, arrow, onSwipe) {
    this.zone = zone
    this.arrow = arrow
    this.host = arrow.parentElement
    this.onSwipe = onSwipe
    this.pointerId = null
    this.start = null
    this.fired = false

    zone.addEventListener("pointerdown", (e) => this.begin(e))
    zone.addEventListener("pointermove", (e) => this.track(e))
    zone.addEventListener("pointerup", (e) => this.end(e, true))
    zone.addEventListener("pointercancel", (e) => this.end(e, false))
  }

  begin(e) {
    // Mouse users have the keyboard; this is for fingers and pens.
    if (e.pointerType === "mouse" || this.pointerId !== null) return
    e.preventDefault()

    try {
      // Keep receiving this finger's moves even if it slides off the map.
      this.zone.setPointerCapture(e.pointerId)
    } catch (_e) {
      // The pointer is already gone; its pointerup will still arrive.
    }

    this.pointerId = e.pointerId
    this.start = { x: e.clientX, y: e.clientY }
    this.fired = false
  }

  track(e) {
    // Firing as soon as the threshold is crossed (not on release) feels instant.
    if (e.pointerId === this.pointerId && !this.fired) this.maybeFire(e)
  }

  end(e, lifted) {
    if (e.pointerId !== this.pointerId) return

    // A fast flick can lift before any move event crossed the threshold.
    if (lifted && !this.fired) this.maybeFire(e)
    this.pointerId = null
  }

  maybeFire(e) {
    const dx = e.clientX - this.start.x
    const dy = e.clientY - this.start.y
    if (Math.hypot(dx, dy) < SWIPE_THRESHOLD_PX) return

    const dir = dominantDirection(dx, dy)
    this.fired = true
    this.showArrow(dir)
    this.onSwipe(dir)
  }

  // Flashes a chevron where the swipe started, pointing the way it went.
  showArrow(dir) {
    const host = this.host.getBoundingClientRect()
    this.arrow.style.left = `${this.start.x - host.left}px`
    this.arrow.style.top = `${this.start.y - host.top}px`
    this.arrow.dataset.dir = dir

    // Restart the animation even if the previous flash hasn't finished.
    this.arrow.classList.remove("show")
    void this.arrow.offsetWidth
    this.arrow.classList.add("show")
  }
}

function dominantDirection(dx, dy) {
  if (Math.abs(dx) > Math.abs(dy)) return dx > 0 ? "right" : "left"
  return dy > 0 ? "down" : "up"
}
