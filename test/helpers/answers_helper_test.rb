require "test_helper"

class AnswersHelperTest < ActionView::TestCase
  test "splits paragraphs and lists and links citation marks" do
    html = answer_body("첫 문단입니다 [1].\n둘째 줄 [2]\n\n- 목록 하나 [1]\n- 목록 둘\n이어지는 문단")
    cite = ->(number) { %(<a class="#{UiHelper::CITE}" data-turbo="false" aria-label="근거 조문 #{number}" href="#citation-#{number}">#{number}</a>) }

    assert_dom_equal <<~HTML.gsub(/\n\s*/, ""), html
      <p class="mb-3">첫 문단입니다 #{cite.(1)}.<br>둘째 줄 #{cite.(2)}</p>
      <ul class="mb-3 list-disc space-y-1 pl-5"><li>목록 하나 #{cite.(1)}</li><li>목록 둘</li></ul>
      <p class="mb-3">이어지는 문단</p>
    HTML
  end

  test "escapes html in the answer" do
    html = answer_body("<script>alert(1)</script> [1]")

    assert_includes html, "&lt;script&gt;alert(1)&lt;/script&gt;"
    assert_not_includes html, "<script>"
  end
end
