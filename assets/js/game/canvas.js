// Matches the server's vision radius (MmoLite.Config.vision_radius/0 = 6):
// diameter 2*6+1 = 13 cells, so every tile the server sends is actually
// rendered instead of clipped at the canvas edge.
const GRID_SIZE = 13

// Open-direction bits in each tile's mask (MmoLite.Wire.tiles/1).
const NORTH = 1
const EAST = 2
const SOUTH = 4
const WEST = 8

const DIR_BITS = { up: NORTH, down: SOUTH, left: WEST, right: EAST }

// Fight odds against a monster, per MmoLite.Combat.resolve/3: more power is
// an outright win, equal power wins on a 2-6, less wins only on a 6.
const ODDS_COLORS = { sure: "#4cd07d", even: "#e0b84b", risky: "#ff5c5c" }
// Matches --evasion in assets/css/app.css.
const EVASION_COLOR = "#9b6bff"

export class GameRenderer {
  constructor(canvas) {
    this.canvas = canvas
    this.ctx = canvas.getContext("2d")
    // Drawing uses fixed logical coordinates (the canvas's width attribute);
    // resize() maps them onto however many device pixels it really covers.
    this.size = canvas.width
    this.cellPx = this.size / GRID_SIZE

    // Tiles ever seen persist for the dim-vs-black fog rendering; monsters
    // and players are always drawn fresh from the latest snapshot only.
    this.seenTiles = new Map()
    this.floor = null
    this.origin = [0, 0]
    this.currentVisible = new Set()
    this.door = null
    this.doorLevel = null
    this.monsters = []
    this.players = []
    // The player's own {power, level}, for colouring monster odds and the door.
    this.stats = null

    this.resize()
    window.addEventListener("resize", () => this.resize())
  }

  // Sizes the backing store to the canvas's on-screen size × devicePixelRatio,
  // so it stays sharp on high-DPI screens and when CSS shrinks it to fit.
  resize() {
    const cssSize = this.canvas.getBoundingClientRect().width || this.size
    const px = Math.round(cssSize * (window.devicePixelRatio || 1))

    if (this.canvas.width !== px) {
      this.canvas.width = px
      this.canvas.height = px
    }

    const scale = px / this.size
    this.ctx.setTransform(scale, 0, 0, scale, 0, 0)
    this.draw()
  }

  setPlayerStats(stats) {
    this.stats = stats
    this.draw()
  }

  applyStateUpdate(payload) {
    // Tiles are keyed by coordinates only, so a different floor's maze would
    // otherwise show through the fog.
    if (payload.floor !== this.floor) {
      this.seenTiles.clear()
      this.floor = payload.floor
    }

    this.origin = payload.origin
    this.door = payload.door
    this.doorLevel = payload.door_level
    this.monsters = payload.monsters || []
    this.players = payload.players || []

    this.currentVisible = new Set()
    for (const [x, y, open] of payload.tiles || []) {
      const k = `${x},${y}`
      this.seenTiles.set(k, open)
      this.currentVisible.add(k)
    }

    this.draw()
  }

  draw() {
    const { ctx, size, cellPx } = this
    ctx.fillStyle = "#000"
    ctx.fillRect(0, 0, size, size)

    const half = Math.floor(GRID_SIZE / 2)
    const [ox, oy] = this.origin

    for (let gy = 0; gy < GRID_SIZE; gy++) {
      for (let gx = 0; gx < GRID_SIZE; gx++) {
        const worldX = ox + (gx - half)
        const worldY = oy + (gy - half)
        const k = `${worldX},${worldY}`
        const open = this.seenTiles.get(k)
        if (open === undefined) continue

        const visible = this.currentVisible.has(k)
        const px = gx * cellPx
        const py = gy * cellPx

        ctx.fillStyle = visible ? "#23273a" : "#171922"
        ctx.fillRect(px, py, cellPx, cellPx)

        ctx.strokeStyle = visible ? "#454b63" : "#252a38"
        ctx.lineWidth = 2
        this.drawWalls(px, py, cellPx, open)

        if (this.door && this.door[0] === worldX && this.door[1] === worldY) {
          ctx.fillStyle = visible ? "#e0b84b" : "#5a4d28"
          ctx.fillRect(px + cellPx * 0.3, py + cellPx * 0.3, cellPx * 0.4, cellPx * 0.4)

          // The level needed to use it, so nobody walks over just to find it locked.
          const unlocked = this.stats && this.stats.level >= this.doorLevel
          ctx.fillStyle = unlocked ? ODDS_COLORS.sure : ODDS_COLORS.risky
          ctx.font = `${Math.floor(cellPx * 0.26)}px sans-serif`
          ctx.textAlign = "center"
          ctx.fillText(`Lv.${this.doorLevel}`, px + cellPx / 2, py + cellPx * 0.25)
        }
      }
    }

    for (const monster of this.monsters) {
      this.drawMonster(monster, ox, oy, half)
    }

    for (const player of this.players) {
      this.drawPlayer(player, ox, oy, half, "#5b8cff")
    }

    // Self, always centered.
    this.drawSelf(half)
  }

  drawWalls(px, py, size, open) {
    const { ctx } = this

    ctx.beginPath()
    if (!(open & NORTH)) {
      ctx.moveTo(px, py)
      ctx.lineTo(px + size, py)
    }
    if (!(open & SOUTH)) {
      ctx.moveTo(px, py + size)
      ctx.lineTo(px + size, py + size)
    }
    if (!(open & WEST)) {
      ctx.moveTo(px, py)
      ctx.lineTo(px, py + size)
    }
    if (!(open & EAST)) {
      ctx.moveTo(px + size, py)
      ctx.lineTo(px + size, py + size)
    }
    ctx.stroke()
  }

  cellCenter(worldX, worldY, ox, oy, half) {
    const gx = worldX - ox + half
    const gy = worldY - oy + half
    return [gx * this.cellPx + this.cellPx / 2, gy * this.cellPx + this.cellPx / 2]
  }

  drawMonster(monster, ox, oy, half) {
    const [x, y] = this.cellCenter(monster.position[0], monster.position[1], ox, oy, half)
    const { ctx, cellPx } = this
    const r = cellPx * 0.3
    const power = monster.level + monster.armor

    ctx.fillStyle = this.oddsColor(power)
    ctx.beginPath()
    ctx.arc(x, y, r, 0, Math.PI * 2)
    ctx.fill()

    if (monster.armor > 0) {
      ctx.strokeStyle = "#c9d1e0"
      ctx.lineWidth = 1 + Math.min(monster.armor, 5) * 0.6
      ctx.beginPath()
      ctx.arc(x, y, r + 3, 0, Math.PI * 2)
      ctx.stroke()
    }

    ctx.fillStyle = "#fff"
    ctx.font = `${Math.floor(cellPx * 0.28)}px sans-serif`
    ctx.textAlign = "center"
    ctx.fillText(String(power), x, y - r - 4)
  }

  oddsColor(monsterPower) {
    // Evasive: contact never starts a fight, so power comparisons don't
    // apply — read as "safe to walk through" instead.
    if (this.stats && this.stats.evading) return EVASION_COLOR
    if (!this.stats || this.stats.power < monsterPower) return ODDS_COLORS.risky
    return this.stats.power > monsterPower ? ODDS_COLORS.sure : ODDS_COLORS.even
  }

  drawPlayer(player, ox, oy, half, color) {
    const [x, y] = this.cellCenter(player.position[0], player.position[1], ox, oy, half)
    const { ctx, cellPx } = this

    ctx.fillStyle = color
    ctx.beginPath()
    ctx.arc(x, y, cellPx * 0.25, 0, Math.PI * 2)
    ctx.fill()

    const label = `${player.name} (Lv.${player.level})`
    ctx.font = `${Math.floor(cellPx * 0.24)}px sans-serif`
    ctx.textAlign = "center"
    ctx.fillStyle = "#000"
    ctx.fillText(label, x, y - cellPx * 0.35 + 1)
    ctx.fillStyle = "#fff"
    ctx.fillText(label, x, y - cellPx * 0.35)
  }

  drawSelf(half) {
    const { ctx, cellPx } = this
    const x = half * cellPx + cellPx / 2
    const y = half * cellPx + cellPx / 2
    const evading = this.stats && this.stats.evading

    ctx.fillStyle = "#fff"
    ctx.beginPath()
    ctx.arc(x, y, cellPx * 0.28, 0, Math.PI * 2)
    ctx.fill()
    ctx.strokeStyle = evading ? EVASION_COLOR : "#5b8cff"
    ctx.lineWidth = 3
    ctx.stroke()

    if (evading) {
      ctx.strokeStyle = EVASION_COLOR
      ctx.lineWidth = 2
      ctx.setLineDash([4, 3])
      ctx.beginPath()
      ctx.arc(x, y, cellPx * 0.42, 0, Math.PI * 2)
      ctx.stroke()
      ctx.setLineDash([])
    }
  }

  // Whether the walls already known client-side allow stepping `dir` from
  // `from`. An unknown tile counts as open; the server has the final say.
  canMove(dir, from = this.origin) {
    const open = this.seenTiles.get(`${from[0]},${from[1]}`)
    return open === undefined || (open & DIR_BITS[dir]) !== 0
  }

  isOnDoor() {
    return !!this.door && this.door[0] === this.origin[0] && this.door[1] === this.origin[1]
  }
}
