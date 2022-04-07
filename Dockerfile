ARG RUBY_VERSION
ARG DISTRO_NAME=bullseye

FROM ruby:$RUBY_VERSION-$DISTRO_NAME

RUN apt-get update -yqq && apt-get install -yqq --no-install-recommends \
  openjdk-11-jre-headless \
  raptor2-utils \
  wait-for-it \
  && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /srv/ontoportal/ontologies_linked_data
RUN mkdir -p /srv/ontoportal/bundle
COPY Gemfile* /srv/ontoportal/ontologies_linked_data/

WORKDIR /srv/ontoportal/ontologies_linked_data

RUN gem update --system
RUN gem install bundler
ENV BUNDLE_PATH=/srv/ontoportal/bundle
RUN bundle install

COPY . /srv/ontoportal/ontologies_linked_data
