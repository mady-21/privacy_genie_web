# 여러 화면에서 되풀이되는 Tailwind 클래스 묶음. 색·모양을 바꿀 때는 여기만 고친다.
# notice-warning, badge-pending 같은 이름은 스타일이 없는 hook 클래스로, 테스트와 화면 구조를 가리키는 데 쓴다.
module UiHelper
  CARD = "rounded-xl border border-stone-200 bg-white dark:border-stone-800 dark:bg-stone-900".freeze

  BUTTON = "inline-flex min-h-10 cursor-pointer items-center justify-center rounded-lg border px-4 font-semibold " \
    "no-underline aria-busy:cursor-progress aria-busy:opacity-70 disabled:opacity-70 " \
    "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-blue-600".freeze
  BUTTON_SECONDARY = "#{BUTTON} border-stone-300 bg-white text-stone-900 hover:border-stone-400 " \
    "dark:border-stone-600 dark:bg-stone-900 dark:text-stone-100 dark:hover:border-stone-500".freeze
  BUTTON_PRIMARY = "#{BUTTON} border-blue-700 bg-blue-700 text-white hover:bg-blue-600 " \
    "dark:border-blue-400 dark:bg-blue-400 dark:text-stone-950 dark:hover:bg-blue-300".freeze

  NOTICE = {
    info: "border-stone-200 bg-stone-50 dark:border-stone-700 dark:bg-stone-800/50",
    warning: "border-amber-300 bg-amber-50 text-amber-900 dark:border-amber-800 dark:bg-amber-950 dark:text-amber-200",
    danger: "border-red-300 bg-red-50 text-red-900 dark:border-red-800 dark:bg-red-950 dark:text-red-200"
  }.freeze

  BADGE = {
    neutral: "bg-stone-100 text-stone-600 dark:bg-stone-800 dark:text-stone-300",
    success: "bg-green-50 text-green-800 dark:bg-green-950 dark:text-green-300",
    warning: "bg-amber-50 text-amber-800 dark:bg-amber-950 dark:text-amber-300"
  }.freeze

  # 답변 본문·안내 문구 안의 [n] 인용 표시
  CITE = "cite mx-px inline-block min-w-6 rounded bg-blue-50 px-1 text-center align-[0.1em] text-xs/5 font-bold " \
    "text-blue-800 no-underline hover:outline-2 hover:outline-blue-600 focus-visible:outline-2 " \
    "focus-visible:outline-blue-600 dark:bg-blue-950 dark:text-blue-200".freeze

  # 회색 작은 머리말(질문, 답변, 근거 조문)
  EYEBROW = "mb-2 text-[13px] font-semibold text-stone-500 dark:text-stone-400".freeze
  HINT = "text-[13px] text-stone-500 dark:text-stone-400".freeze

  def notice_tag(kind = :info, **options, &block)
    hooks = [ "notice", ("notice-#{kind}" unless kind == :info) ]
    extra = options.delete(:class)
    tag.div(**options, class: [ *hooks, "mb-3 rounded-lg border px-3.5 py-2.5 [&_p+p]:mt-1", NOTICE.fetch(kind), extra ], &block)
  end

  def badge_tag(text, kind = :neutral, hook: nil)
    tag.span(text, class: [ "badge", hook, "inline-block rounded-full px-2 text-xs/6 font-semibold", BADGE.fetch(kind) ])
  end
end
