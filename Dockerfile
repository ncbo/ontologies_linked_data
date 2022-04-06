FROM ruby:2.6

RUN apt-get update -yqq && apt-get install -yqq --no-install-recommends \
  openjdk-11-jre-headless \
  raptor2-utils \
  wait-for-it \
  && rm -rf /var/lib/apt/lists/*
RUN adduser --system ontoportal

# The Gemfile Caching Trick
RUN mkdir -p /srv/ontoportal/ontologies_linked_data
COPY Gemfile* /srv/ontoportal/ontologies_linked_data/
WORKDIR /srv/ontoportal/ontologies_linked_data
RUN gem install bundler
#ENV BUNDLE_PATH=/bundle
RUN bundle install

COPY . /srv/ontoportal/ontologies_linked_data

# unit tests have to run with unprivileged user
# otherwise TestOWLApi#test_command_KO_output test fails
RUN chown -R ontoportal  /srv/ontoportal/ontologies_linked_data
USER ontoportal
