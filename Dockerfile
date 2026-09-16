# Development image. Ruby 3.3 + Rails 7.2, no Node — importmap serves the JS and
# tailwindcss-rails ships a standalone binary.
FROM ruby:3.3.6-slim

ENV LANG=C.UTF-8 \
    TZ=Asia/Kolkata \
    RAILS_ENV=development \
    BUNDLE_PATH=/usr/local/bundle

RUN apt-get update -qq \
 && apt-get install -y --no-install-recommends \
      build-essential \
      libpq-dev \
      libyaml-dev \
      postgresql-client \
      git \
      curl \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copied first so a code change doesn't reinstall every gem.
COPY Gemfile Gemfile.lock ./
RUN gem install bundler && bundle install

COPY . .

EXPOSE 3000
CMD ["bin/rails", "server", "-b", "0.0.0.0"]