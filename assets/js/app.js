import "phoenix_html"
import { GameConnection, storedToken, clearToken, setNotice, takeNotice } from "./game/net"
import { GameRenderer } from "./game/canvas"
import { GameUI } from "./game/ui"
import { Swipe } from "./game/swipe"

const KEY_DIRS = {
  ArrowUp: "up",
  ArrowDown: "down",
  ArrowLeft: "left",
  ArrowRight: "right",
  w: "up",
  s: "down",
  a: "left",
  d: "right",
}

// Headroom over the server's move cooldown, so network jitter doesn't push
// two paced moves closer together than it allows.
const MOVE_PACING_MARGIN_MS = 10

const TOUCH = window.matchMedia("(pointer: coarse)").matches

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms))

function describeOutcome(result, ui) {
  switch (result.outcome) {
    case "moved":
    case "blocked":
      return

    case "win":
      ui.log(
        `Defeated a Lv.${result.monster.level} monster — found ${result.loot.name}! ` +
          `+${result.levels_gained} level(s), now Lv.${result.level}.`,
        "win"
      )
      return

    case "tie_win":
      ui.log(
        `Won an evenly-matched fight (rolled ${result.roll})! Defeated a Lv.${result.monster.level} ` +
          `monster — +${result.levels_gained} level(s), now Lv.${result.level}.`,
        "win"
      )
      return

    case "upset_win":
      ui.log(
        `Upset victory (rolled 6)! Defeated a Lv.${result.monster.level} monster — ` +
          `+${result.levels_gained} level(s), now Lv.${result.level}.`,
        "win"
      )
      return

    case "flee":
      ui.log(`Fled from the monster (rolled ${result.roll}).`, "flee")
      return

    case "loss":
      if (result.full_reset) {
        ui.log("You ran out of hearts — all equipment lost, back to floor 0.", "loss")
      } else {
        ui.log(`Lost a heart in combat (rolled ${result.roll}).`, "loss")
      }
      return
  }
}

async function main() {
  const canvas = document.getElementById("game-canvas")
  const renderer = new GameRenderer(canvas)
  const ui = new GameUI()
  const conn = new GameConnection()

  ui.onStatsChange = () => {
    renderer.setPlayerStats({ power: ui.power(), level: ui.player.level })
    updateDoorPrompt()
  }

  // Movement: at most one move in flight plus one queued (the latest key
  // wins), so holding a key walks steadily instead of dropping key repeats.
  let moving = false
  let queued = null
  let lastMoveAt = 0
  let moveCooldownMs = 50
  // Own position per the latest move reply. A move's state_update arrives
  // just after its reply, so renderer.origin briefly lags behind it.
  let knownOrigin = null

  conn.on("state_update", (payload) => {
    knownOrigin = null
    renderer.applyStateUpdate(payload)
    updateDoorPrompt()
  })

  conn.on("player_update", (payload) => {
    ui.updatePlayer(payload)
    ui.setFloor(payload.floor)
  })

  // The socket dropped and Phoenix rejoined on its own — resync everything.
  conn.on("rejoined", (reply) => applyJoinReply(reply))

  // A rejoin was refused: the server no longer knows this token, so it
  // restarted — usually a deploy. Reload to pick up the new assets (this
  // page's code may not match the new server), explaining why afterwards.
  conn.on("session_lost", () => {
    clearToken()
    setNotice("Your session expired — enter a name to start a new run.")
    window.location.reload()
  })

  function updateDoorPrompt() {
    if (!renderer.isOnDoor()) {
      ui.hideDoorPrompt()
      return
    }

    const level = ui.player ? ui.player.level : 0
    const required = renderer.doorLevel

    if (level >= required) {
      ui.showDoorPrompt(TOUCH ? "Tap here to use the door" : "Press E to use the door")
    } else {
      ui.showDoorPrompt(`The door needs Lv. ${required} — you're Lv. ${level}`)
    }
  }

  function applyJoinReply(reply) {
    if (reply.move_cooldown_ms) moveCooldownMs = reply.move_cooldown_ms
    knownOrigin = null
    ui.hideNameOverlay()
    ui.setName(reply.name)
    ui.setFloor(reply.floor)
    ui.updatePlayer(reply)
    renderer.applyStateUpdate(reply.visible)
    updateDoorPrompt()
  }

  async function join(params) {
    applyJoinReply(await conn.connect(params))
  }

  function requestMove(dir, repeat) {
    queued = { dir, repeat }
    if (!moving) runMoves()
  }

  async function runMoves() {
    moving = true
    try {
      while (queued) {
        // Pace moves to the server's cooldown so none get rejected as too fast.
        const wait = lastMoveAt + moveCooldownMs + MOVE_PACING_MARGIN_MS - performance.now()
        if (wait > 0) await sleep(wait)
        if (!queued || !conn.isJoined()) break

        const { dir } = queued
        queued = null
        // Walls are known client-side: skip the round trip for a blocked move.
        if (!renderer.canMove(dir, knownOrigin || renderer.origin)) continue

        lastMoveAt = performance.now()
        try {
          const result = await conn.move(dir)
          if (result.position) knownOrigin = result.position
          describeOutcome(result, ui)
        } catch (err) {
          if (err.reason === "timeout") ui.log("The server didn't respond — try again.", "loss")
        }
      }
    } finally {
      moving = false
    }
  }

  const notice = takeNotice()
  if (notice) ui.log(notice, "loss")

  const existingToken = storedToken()
  if (existingToken) {
    try {
      await join({ token: existingToken })
    } catch (err) {
      // Only drop the token when the server says it's gone — a timeout
      // shouldn't throw away a session that may still exist.
      if (err.reason === "unknown_token") clearToken()
      ui.showNameOverlay()
    }
  } else {
    ui.showNameOverlay()
  }

  ui.onNameSubmit(async (name) => {
    try {
      await join({ name })
    } catch (err) {
      ui.log(`Could not join: ${err.reason || "unknown error"}`, "loss")
    }
  })

  async function tryEnterDoor() {
    if (!conn.isJoined() || !renderer.isOnDoor()) return

    try {
      await conn.enterDoor()
      ui.log("Descended to the next floor.")
    } catch (err) {
      if (err.reason === "level_too_low") {
        ui.log(`The door requires level ${err.required}.`, "loss")
      } else if (err.reason === "timeout") {
        ui.log("The server didn't respond — try again.", "loss")
      }
    }
  }

  // Releasing a held key drops its pending repeat move, so the player stops
  // where they let go instead of one step later.
  // Deliberate taps (non-repeat presses) still go through.
  function cancelRepeat(dir) {
    if (queued && queued.repeat && queued.dir === dir) queued = null
  }

  document.addEventListener("keydown", (e) => {
    if (!conn.isJoined() || e.target instanceof HTMLInputElement) return

    const dir = KEY_DIRS[e.key]
    if (dir) {
      // Arrow keys would otherwise scroll the page under the board.
      e.preventDefault()
      requestMove(dir, e.repeat)
    } else if ((e.key === "e" || e.key === "Enter") && renderer.isOnDoor()) {
      e.preventDefault()
      tryEnterDoor()
    }
  })

  document.addEventListener("keyup", (e) => cancelRepeat(KEY_DIRS[e.key]))

  // The door prompt doubles as a button, for touch screens.
  document.getElementById("door-prompt").addEventListener("click", (e) => {
    // Otherwise a later Enter would press it again on top of the key handler.
    e.currentTarget.blur()
    tryEnterDoor()
  })

  // Touch: every swipe on the map is exactly one deliberate step, so nothing
  // keeps walking once the finger stops.
  new Swipe(canvas, document.getElementById("swipe-arrow"), (dir) => {
    if (conn.isJoined()) requestMove(dir, false)
  })
}

document.addEventListener("DOMContentLoaded", main)
