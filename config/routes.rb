Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # 질문 테스트용 검색 확인 화면. 개발 도구라 운영 환경에는 라우트를 두지 않는다.
  resource :search, only: :show if Rails.env.local?

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # 사용자용 질의응답 화면. 답변 URL은 추측할 수 없는 토큰을 쓴다.
  root "answers#new"
  resources :answers, only: %i[new create show], param: :token do
    post :retry, on: :member
  end
end
