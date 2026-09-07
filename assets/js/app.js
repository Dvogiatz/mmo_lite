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
      ui.log(`Defeated a Lv.${result.monster.level} monster — found ${result.loot.name}!`, "win")
      return

    case "upset_win":
      ui.log(`Upset victory (rolled 6)! Defeated a Lv.${result.monster.level} monster.`, "win")
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

  conn.on("player_update", (payload) => ui.updatePlayer(payload))

  function updateDoorPrompt() {
    if (renderer.isOnDoor()) {
      ui.showDoorPrompt("Press E to use the door")
    } else {
      ui.hideDoorPrompt()
    }
  }

  async function join(params) {
    const reply = await conn.connect(params)
    ui.hideNameOverlay()
    ui.updatePlayer(reply)
    renderer.applyStateUpdate(reply.visible)
    updateDoorPrompt()
  }

  const existingToken = storedToken()
  if (existingToken) {
    try {
      await join({ token: existingToken })
    } catch (_err) {
      clearToken()
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
    if (!conn.channel) return

    const dir = KEY_DIRS[e.key]
    if (dir && !moving) {
      moving = true
      try {
        const result = await conn.move(dir)
        describeOutcome(result, ui)
      } finally {
        moving = false
      }
      return
    }

    if ((e.key === "e" || e.key === "Enter") && renderer.isOnDoor()) {
      try {
        await conn.enterDoor()
        ui.log("Descended to the next floor.")
      } catch (err) {
        if (err.reason === "level_too_low") {
          ui.log(`The door requires level ${err.required}.`, "loss")
        }
      }
    }
  })
}

document.addEventListener("DOMContentLoaded", main)
