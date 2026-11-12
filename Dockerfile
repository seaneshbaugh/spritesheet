# syntax=docker/dockerfile:1

ARG RUBY_VERSION=4.0.9
FROM ruby:${RUBY_VERSION}-slim

WORKDIR /app

ENV APP_PORT=3000 \
    RACK_ENV=development

RUN apt-get update && \
    apt-get install --no-install-recommends -y build-essential libyaml-dev imagemagick fonts-dejavu-core && \
    rm -rf /var/lib/apt/lists/*

COPY Gemfile Gemfile.lock .ruby-version ./
RUN bundle install

COPY . .

EXPOSE 3000
CMD ["bin/server"]
