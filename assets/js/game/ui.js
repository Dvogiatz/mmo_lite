const el = (id) => document.getElementById(id)

function renderSlot(id, item, unit) {
  el(id).textContent = item ? `${item.name} (+${item.value} ${unit})` : "(empty)"
}

export class GameUI {
  constructor() {
    this.player = null
    this.buffExpiresAtLocal = null
    // Called whenever power or level may have changed (new stats, buff expiry).
    this.onStatsChange = null
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

  setName(name) {
    el("player-name-badge").textContent = name
  }

  setFloor(floor) {
    el("floor-value").textContent = floor
  }

  updatePlayer(player) {
    const heartsRow = el("hearts")
    heartsRow.innerHTML = ""
    for (let i = 0; i < player.max_hearts; i++) {
      const dot = document.createElement("span")
      dot.className = i < player.hearts ? "heart full" : "heart empty"
      heartsRow.appendChild(dot)
    }
    el("hearts-count").textContent = `${player.hearts} / ${player.max_hearts}`

    el("level-value").textContent = `Lv. ${player.level}`

    renderSlot("weapon-slot", player.equipment.weapon, "dmg")
    renderSlot("armor-slot", player.equipment.armor, "hearts")
    renderSlot("boots-slot", player.equipment.boots, "flee")

    this.player = player
    this.buffExpiresAtLocal = player.buff ? Date.now() + player.buff.remaining_ms : null
    this.tickBuff()
    this.renderPower()
  }

  // Current attack power: level + equipped weapon's damage + the Killing
  // Spree buff while it lasts — the same sum as MmoLite.Player.power/1,
  // which combat compares against a monster's level + armor.
  power() {
    if (!this.player) return 0
    const buffDamage = this.buffExpiresAtLocal ? this.player.buff.damage : 0
    const weaponDamage = this.player.equipment.weapon ? this.player.equipment.weapon.value : 0
    return this.player.level + weaponDamage + buffDamage
  }

  renderPower() {
    el("power-value").textContent = `Power: ${this.power()}`
    if (this.onStatsChange) this.onStatsChange()
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
      this.renderPower()
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
