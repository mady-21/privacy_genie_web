import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// 답변이 진행 중일 때 붙는다. 보통은 Job이 보내는 Turbo refresh로 화면이 바뀌지만,
// 구독이 붙기 전에 Job이 끝나 refresh를 놓친 경우를 위해 주기적으로 페이지를 다시 그린다.
// 답변이 끝나면 이 요소가 화면에서 빠지면서 disconnect로 멈춘다.
export default class extends Controller {
  static values = { interval: { type: Number, default: 5000 } }

  connect() {
    this.timer = setInterval(() => this.refresh(), this.intervalValue)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  refresh() {
    if (document.visibilityState !== "visible") return

    if (Turbo.session.refresh) {
      Turbo.session.refresh(window.location.href)
    } else {
      Turbo.visit(window.location.href, { action: "replace" })
    }
  }
}
