import "phoenix_html"
import { GameConnection, storedToken, clearToken } from "./game/net"
import { GameRenderer } from "./game/canvas"
import { GameUI } from "./game/ui"

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

  conn.on("state_update", (payload) => {
    renderer.applyStateUpdate(payload)
    updateDoorPrompt()
  })

  conn.on("player_update", (payload) => {
    ui.updatePlayer(payload)
    ui.setFloor(payload.floor)
  })

  // The socket dropped and Phoenix rejoined on its own — resync everything.
  conn.on("rejoined", (reply) => applyJoinReply(reply))

  // A rejoin was refused: the server no longer knows this token (restart/deploy).
  conn.on("session_lost", () => {
    clearToken()
    renderer.reset()
    ui.hideDoorPrompt()
    ui.log("Your session expired — enter a name to start a new run.", "loss")
    ui.showNameOverlay()
  })

  function updateDoorPrompt() {
    if (renderer.isOnDoor()) {
      ui.showDoorPrompt("Press E to use the door")
    } else {
      ui.hideDoorPrompt()
    }
  }

  function applyJoinReply(reply) {
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

  let moving = false

  document.addEventListener("keydown", async (e) => {
    if (!conn.isJoined() || e.target instanceof HTMLInputElement) return

    const dir = KEY_DIRS[e.key]
    if (dir) {
      // Arrow keys would otherwise scroll the page under the board.
      e.preventDefault()
      if (moving) return

      moving = true
      try {
        const result = await conn.move(dir)
        describeOutcome(result, ui)
      } catch (err) {
        if (err.reason === "timeout") ui.log("The server didn't respond — try again.", "loss")
      } finally {
        moving = false
      }
      return
    }

    if ((e.key === "e" || e.key === "Enter") && renderer.isOnDoor()) {
      e.preventDefault()
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
  })
}

document.addEventListener("DOMContentLoaded", main)
