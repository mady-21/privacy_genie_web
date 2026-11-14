require "test_helper"

class Answers::MaskingTest < ActiveSupport::TestCase
  test "masks each kind of personal information" do
    {
      "연락처는 010-1234-5678입니다" => [ "연락처는 [전화번호]입니다", [ "전화번호" ] ],
      "01012345678로 연락" => [ "[전화번호]로 연락", [ "전화번호" ] ],
      "사무실 02-123-4567" => [ "사무실 [전화번호]", [ "전화번호" ] ],
      "메일 hong.gildong@example.co.kr 로" => [ "메일 [이메일] 로", [ "이메일" ] ],
      "주민번호 900101-1234567 유출" => [ "주민번호 [주민등록번호] 유출", [ "주민등록번호" ] ],
      "외국인 9001015234567" => [ "외국인 [주민등록번호]", [ "주민등록번호" ] ],
      "카드 1234-5678-9012-3456 결제" => [ "카드 [카드번호] 결제", [ "카드번호" ] ],
      "계좌 110-123-456789로 입금" => [ "계좌 [계좌번호]로 입금", [ "계좌번호" ] ]
    }.each do |input, (text, kinds)|
      result = Answers::Masking.call(input)

      assert_equal text, result.text, input
      assert_equal kinds, result.kinds, input
      assert result.masked?
    end
  end

  test "leaves dates, amounts and article numbers alone" do
    text = "2026-11-14에 제21조 위반으로 과태료 3,000만원(시행령 제63조), 1,000명 이상 정보 유출"

    result = Answers::Masking.call(text)

    assert_equal text, result.text
    assert_empty result.kinds
    assert_not result.masked?
  end

  test "lists each kind once in order of the rules" do
    result = Answers::Masking.call("010-1111-2222, a@b.com, 010-3333-4444")

    assert_equal "[전화번호], [이메일], [전화번호]", result.text
    assert_equal [ "이메일", "전화번호" ], result.kinds
  end
end
