const el = (id) => document.getElementById(id)

const HEART_FULL = "❤"
const HEART_EMPTY = "🖤"

export class GameUI {
  constructor() {
    this.buffExpiresAtLocal = null
    this._tickTimer = setInterval(() => this.tickBuff(), 250)
  }

  // -- name overlay ---------------------------------------------------------

  showNameOverlay() {
    el("name-overlay").classList.remove("hidden")
    el("name-input").focus()
  }

  hideNameOverlay() {
    el("name-overlay").classList.add("hidden")
  }

  onNameSubmit(callback) {
    const submit = () => {
      const name = el("name-input").value.trim()
      if (name) callback(name)
    }
    el("name-submit").addEventListener("click", submit)
    el("name-input").addEventListener("keydown", (e) => {
      if (e.key === "Enter") submit()
    })
  }

  // -- player stat panel ------------------------------------------------

  updatePlayer(player) {
    el("hearts").textContent =
      HEART_FULL.repeat(Math.max(player.hearts, 0)) +
      HEART_EMPTY.repeat(Math.max(player.max_hearts - player.hearts, 0))

    el("level-value").textContent = `Lv. ${player.level}`
    el("xp-value").textContent = `${player.xp} XP`
    // There's no fixed level-up threshold in this game (see spec) — the bar
    // is a lightweight rolling indicator, not tied to a specific max.
    el("xp-bar-fill").style.width = `${Math.min(player.xp % 100, 100)}%`

    const list = el("equipment-list")
    list.innerHTML = ""
    if (player.equipment.length === 0) {
      const li = document.createElement("li")
      li.textContent = "(empty)"
      list.appendChild(li)
    } else {
      for (const item of player.equipment) {
        const li = document.createElement("li")
        li.textContent = `${item.name} (+${item.damage})`
        list.appendChild(li)
      }
    }

    if (player.buff) {
      this.buffExpiresAtLocal = Date.now() + player.buff.remaining_ms
    } else {
      this.buffExpiresAtLocal = null
    }
    this.tickBuff()
  }

  tickBuff() {
    const indicator = el("buff-indicator")
    if (!this.buffExpiresAtLocal) {
      indicator.classList.remove("active")
      return
    }

    const remaining = this.buffExpiresAtLocal - Date.now()
    if (remaining <= 0) {
      this.buffExpiresAtLocal = null
      indicator.classList.remove("active")
      return
    }

    indicator.classList.add("active")
    el("buff-timer").textContent = `${(remaining / 1000).toFixed(1)}s`
  }

  // -- combat log -------------------------------------------------------

  log(message, kind) {
    const list = el("combat-log")
    const li = document.createElement("li")
    li.textContent = message
    if (kind) li.className = kind
    list.insertBefore(li, list.firstChild)
    while (list.children.length > 30) list.removeChild(list.lastChild)
  }

  // -- door prompt --------------------------------------------------------

  showDoorPrompt(text) {
    const prompt = el("door-prompt")
    prompt.textContent = text
    prompt.classList.add("visible")
  }

  hideDoorPrompt() {
    el("door-prompt").classList.remove("visible")
  }
}
