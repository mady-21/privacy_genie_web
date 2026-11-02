FROM ruby:3.4-slim

WORKDIR /app

RUN apt-get update -qq && \
    apt-get install -y \
    build-essential \
    libpq-dev \
    curl \
    git \
    && rm -rf /var/lib/apt/lists/*

# 실행 중에는 레포가 /app에 마운트되므로, 이미지의 gem도 Gemfile.lock과 같은 버전이어야 한다.
COPY Gemfile Gemfile.lock ./

RUN bundle install

COPY . .

EXPOSE 3000

CMD ["bin/rails", "server", "-b", "0.0.0.0"]