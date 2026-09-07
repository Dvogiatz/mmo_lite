import { Socket } from "phoenix"

const TOKEN_KEY = "mmo_lite_token"

export function storedToken() {
  try {
    return window.sessionStorage.getItem(TOKEN_KEY)
  } catch (_e) {
    return null
  }
}

function storeToken(token) {
  try {
    window.sessionStorage.setItem(TOKEN_KEY, token)
  } catch (_e) {
    // sessionStorage unavailable (private mode, etc) — session just won't survive a refresh.
  }
}

export function clearToken() {
  try {
    window.sessionStorage.removeItem(TOKEN_KEY)
  } catch (_e) {
    // ignore
  }
}

export class GameConnection {
  constructor() {
    this.socket = null
    this.channel = null
    this.handlers = {}
  }

  on(event, fn) {
    this.handlers[event] = fn
  }

  emit(event, payload) {
    if (this.handlers[event]) this.handlers[event](payload)
  }

  // joinParams: {token} or {name}. Resolves with the join reply, rejects with the join error.
  connect(joinParams) {
    return new Promise((resolve, reject) => {
      this.socket = new Socket("/mmo_lite/socket")
      this.socket.connect()

      this.channel = this.socket.channel("game:play", joinParams)

      this.channel.on("state_update", (payload) => this.emit("state_update", payload))
      this.channel.on("player_update", (payload) => this.emit("player_update", payload))

      this.channel
        .join()
        .receive("ok", (reply) => {
          if (reply.token) storeToken(reply.token)
          resolve(reply)
        })
        .receive("error", (reply) => reject(reply))
        .receive("timeout", () => reject({ reason: "timeout" }))
    })
  }

  move(dir) {
    return new Promise((resolve, reject) => {
      this.channel
        .push("move", { dir })
        .receive("ok", resolve)
        .receive("error", reject)
    })
  }

  enterDoor() {
    return new Promise((resolve, reject) => {
      this.channel
        .push("enter_door", {})
        .receive("ok", resolve)
        .receive("error", reject)
    })
  }

  disconnect() {
    if (this.socket) this.socket.disconnect()
  }
}
