import { Controller } from "@hotwired/stimulus"

// 질문 입력: 글자 수, 개인정보 패턴 경고, Ctrl/Cmd+Enter 보내기, 예시 질문 채우기.
// 서버(Answers::Masking)가 어차피 가리므로 여기 패턴은 사용자에게 미리 알려 주는 용도다.
const PERSONAL_INFO_PATTERNS = [
  /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/,
  /(?<!\d)\d{6}\s*-?\s*[1-8]\d{6}(?!\d)/,
  /(?<!\d)01[016789][\s-]?\d{3,4}[\s-]?\d{4}(?!\d)/,
  /(?<!\d)\d{4}(?:[\s-]?\d{4}){3}(?!\d)/
]

export default class extends Controller {
  static targets = ["input", "count", "warning"]
  static values = { max: Number }

  connect() {
    this.update()
  }

  update() {
    const text = this.inputTarget.value
    this.countTarget.textContent = text.length.toLocaleString("ko-KR")
    this.countTarget.classList.toggle("over-limit", this.hasMaxValue && text.length > this.maxValue)
    this.warningTarget.hidden = !PERSONAL_INFO_PATTERNS.some((pattern) => pattern.test(text))
  }

  submitOnShortcut(event) {
    if (event.key === "Enter" && (event.metaKey || event.ctrlKey) && !event.isComposing) {
      event.preventDefault()
      this.element.requestSubmit()
    }
  }

  fill({ params: { text } }) {
    this.inputTarget.value = text
    this.update()
    this.inputTarget.focus()
  }
}
