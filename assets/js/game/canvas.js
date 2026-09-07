const GRID_SIZE = 10

function key([x, y]) {
  return `${x},${y}`
}

export class GameRenderer {
  constructor(canvas) {
    this.ctx = canvas.getContext("2d")
    this.width = canvas.width
    this.height = canvas.height
    this.cellPx = this.width / GRID_SIZE

    // Tiles ever seen persist for the dim-vs-black fog rendering; monsters
    // and players are always drawn fresh from the latest snapshot only.
    this.seenTiles = new Map()
    this.origin = [0, 0]
    this.currentVisible = new Set()
    this.door = null
    this.monsters = []
    this.players = []
  }

  applyStateUpdate(payload) {
    this.origin = payload.origin
    this.door = payload.door
    this.monsters = payload.monsters || []
    this.players = payload.players || []

    this.currentVisible = new Set()
    for (const tile of payload.tiles || []) {
      const k = key(tile.cell)
      this.seenTiles.set(k, tile.open)
      this.currentVisible.add(k)
    }

    this.draw()
  }

  draw() {
    const { ctx, width, height, cellPx } = this
    ctx.fillStyle = "#000"
    ctx.fillRect(0, 0, width, height)

    const half = Math.floor(GRID_SIZE / 2)
    const [ox, oy] = this.origin

    for (let gy = 0; gy < GRID_SIZE; gy++) {
      for (let gx = 0; gx < GRID_SIZE; gx++) {
        const worldX = ox + (gx - half)
        const worldY = oy + (gy - half)
        const k = `${worldX},${worldY}`
        const open = this.seenTiles.get(k)
        if (!open) continue

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
    const dirs = new Set(open)

    ctx.beginPath()
    if (!dirs.has("north")) {
      ctx.moveTo(px, py)
      ctx.lineTo(px + size, py)
    }
    if (!dirs.has("south")) {
      ctx.moveTo(px, py + size)
      ctx.lineTo(px + size, py + size)
    }
    if (!dirs.has("west")) {
      ctx.moveTo(px, py)
      ctx.lineTo(px, py + size)
    }
    if (!dirs.has("east")) {
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

    ctx.fillStyle = "#ff5c5c"
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
    ctx.fillText(String(monster.level), x, y - r - 4)
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

    ctx.fillStyle = "#fff"
    ctx.beginPath()
    ctx.arc(x, y, cellPx * 0.28, 0, Math.PI * 2)
    ctx.fill()
    ctx.strokeStyle = "#5b8cff"
    ctx.lineWidth = 3
    ctx.stroke()
  }

  isOnDoor() {
    return !!this.door && this.door[0] === this.origin[0] && this.door[1] === this.origin[1]
  }
}
