import { Socket } from "phoenix"

const TOKEN_KEY = "mmo_lite_token"
const NOTICE_KEY = "mmo_lite_notice"

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

// A one-off message to show after the next page load (e.g. why a reload happened).
export function setNotice(text) {
  try {
    window.sessionStorage.setItem(NOTICE_KEY, text)
  } catch (_e) {
    // ignore — the reload just won't explain itself
  }
}

export function takeNotice() {
  try {
    const text = window.sessionStorage.getItem(NOTICE_KEY)
    window.sessionStorage.removeItem(NOTICE_KEY)
    return text
  } catch (_e) {
    return null
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
  //
  // After the first successful join, Phoenix transparently rejoins whenever the
  // socket reconnects: those rejoins emit "rejoined" (with a fresh join reply) or
  // "session_lost" (the server no longer knows this token, e.g. after a restart).
  connect(joinParams) {
    // Tear down any previous attempt, otherwise a failed join keeps retrying
    // in the background on its own socket.
    this.disconnect()

    return new Promise((resolve, reject) => {
      let joined = false

      this.socket = new Socket("/mmo_lite/socket")
      this.socket.connect()

      // Evaluated on every (re)join: once a token has been issued, an automatic
      // rejoin resumes that player instead of creating a new one from `name`.
      this.channel = this.socket.channel("game:play", () => {
        const token = storedToken()
        return token ? { token } : joinParams
      })

      this.channel.on("state_update", (payload) => this.emit("state_update", payload))
      this.channel.on("player_update", (payload) => this.emit("player_update", payload))
      this.channel.on("roster_update", (payload) => this.emit("roster_update", payload))

      this.channel
        .join()
        .receive("ok", (reply) => {
          if (reply.token) storeToken(reply.token)

          if (joined) {
            this.emit("rejoined", reply)
          } else {
            joined = true
            resolve(reply)
          }
        })
        .receive("error", (reply) => {
          this.disconnect()
          if (joined) {
            this.emit("session_lost", reply)
          } else {
            reject(reply)
          }
        })
        .receive("timeout", () => {
          // Once joined, Phoenix keeps retrying on its own; only fail the initial join.
          if (!joined) {
            this.disconnect()
            reject({ reason: "timeout" })
          }
        })
    })
  }

  isJoined() {
    return !!this.channel && this.channel.isJoined()
  }

  move(dir) {
    return this.push("move", { dir })
  }

  enterDoor() {
    return this.push("enter_door", {})
  }

  push(event, payload) {
    return new Promise((resolve, reject) => {
      this.channel
        .push(event, payload)
        .receive("ok", resolve)
        .receive("error", reject)
        .receive("timeout", () => reject({ reason: "timeout" }))
    })
  }

  disconnect() {
    if (this.channel) this.channel.leave()
    if (this.socket) this.socket.disconnect()
    this.channel = null
    this.socket = null
  }
}
