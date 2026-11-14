# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc,
  # 사용자 질문은 개인정보가 섞일 수 있다. DB에는 Answers::Masking을 거친 것만 남기므로 로그에도 원문을 남기지 않는다.
  # /search의 q는 기호(:q)로 쓰면 이름에 q가 든 모든 파라미터가 걸리므로 정확히 q만 고른다.
  :question, /\Aq\z/
]
