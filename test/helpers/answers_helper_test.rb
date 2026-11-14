require "test_helper"

class AnswersHelperTest < ActionView::TestCase
  test "splits paragraphs and lists and links citation marks" do
    html = answer_body("첫 문단입니다 [1].\n둘째 줄 [2]\n\n- 목록 하나 [1]\n- 목록 둘\n이어지는 문단")

    assert_dom_equal <<~HTML.gsub(/\n\s*/, ""), html
      <p>첫 문단입니다 <a class="cite" data-turbo="false" aria-label="근거 조문 1" href="#citation-1">1</a>.<br>둘째 줄 <a class="cite" data-turbo="false" aria-label="근거 조문 2" href="#citation-2">2</a></p>
      <ul><li>목록 하나 <a class="cite" data-turbo="false" aria-label="근거 조문 1" href="#citation-1">1</a></li><li>목록 둘</li></ul>
      <p>이어지는 문단</p>
    HTML
  end

  test "escapes html in the answer" do
    html = answer_body("<script>alert(1)</script> [1]")

    assert_includes html, "&lt;script&gt;alert(1)&lt;/script&gt;"
    assert_not_includes html, "<script>"
  end
end
