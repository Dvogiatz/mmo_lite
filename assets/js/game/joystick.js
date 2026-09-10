// A floating joystick for touch screens: pressing anywhere on `zone` drops
// the stick under the finger, and dragging past a small dead zone picks one
// of the four grid directions. `onDirection(dir)` fires whenever that choice
// changes — "up" | "down" | "left" | "right", or null when released or
// re-centred.

const DEAD_ZONE_PX = 14
const KNOB_TRAVEL_PX = 40
// How strongly the other axis must dominate before the direction switches,
// so a drag near a diagonal doesn't flicker between two directions.
const SWITCH_BIAS = 1.3

export class Joystick {
  constructor(zone, el, onDirection) {
    this.zone = zone
    this.el = el
    this.host = el.parentElement
    this.knob = el.querySelector(".joystick-knob")
    this.onDirection = onDirection
    this.pointerId = null
    this.start = null
    this.dir = null

    zone.addEventListener("pointerdown", (e) => this.begin(e))
    zone.addEventListener("pointermove", (e) => this.drag(e))
    zone.addEventListener("pointerup", (e) => this.end(e))
    zone.addEventListener("pointercancel", (e) => this.end(e))
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

    const host = this.host.getBoundingClientRect()
    this.el.style.left = `${e.clientX - host.left}px`
    this.el.style.top = `${e.clientY - host.top}px`
    this.setKnob(0, 0)
    this.el.classList.add("active")
  }

  drag(e) {
    if (e.pointerId !== this.pointerId) return

    const dx = e.clientX - this.start.x
    const dy = e.clientY - this.start.y
    const dist = Math.hypot(dx, dy)
    const travel = Math.min(dist, KNOB_TRAVEL_PX)

    this.setKnob(dist ? (dx / dist) * travel : 0, dist ? (dy / dist) * travel : 0)
    this.setDirection(dist < DEAD_ZONE_PX ? null : pickDirection(dx, dy, this.dir))
  }

  end(e) {
    if (e.pointerId !== this.pointerId) return

    this.pointerId = null
    this.el.classList.remove("active")
    this.setDirection(null)
  }

  setKnob(x, y) {
    this.knob.style.transform = `translate(${x}px, ${y}px)`
  }

  setDirection(dir) {
    if (dir === this.dir) return

    this.dir = dir
    this.el.dataset.dir = dir || ""
    this.onDirection(dir)
  }
}

function pickDirection(dx, dy, current) {
  const horizontal = dx > 0 ? "right" : "left"
  const vertical = dy > 0 ? "down" : "up"
  const ax = Math.abs(dx)
  const ay = Math.abs(dy)

  if (current === "left" || current === "right") {
    return ay > ax * SWITCH_BIAS ? vertical : horizontal
  }

  if (current === "up" || current === "down") {
    return ax > ay * SWITCH_BIAS ? horizontal : vertical
  }

  return ax > ay ? horizontal : vertical
}
