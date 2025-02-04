ARG RUBY_VERSION=3.0
ARG DISTRO_NAME=bullseye

FROM ruby:$RUBY_VERSION-$DISTRO_NAME

RUN apt-get update -yqq && apt-get install -yqq --no-install-recommends \
  openjdk-11-jre-headless \
  raptor2-utils \
  && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /srv/ontoportal/ontologies_linked_data
RUN mkdir -p /srv/ontoportal/bundle
COPY Gemfile* /srv/ontoportal/ontologies_linked_data/

WORKDIR /srv/ontoportal/ontologies_linked_data

RUN gem update --system 3.5.11
RUN gem install bundler -v 2.5.11
ENV BUNDLE_PATH=/srv/ontoportal/bundle
RUN bundle install

COPY . /srv/ontoportal/ontologies_linked_data
