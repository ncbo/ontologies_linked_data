FROM ruby:2.6

RUN apt-get update -yqq && apt-get install -yqq --no-install-recommends vim openjdk-11-jre-headless raptor2-utils
# The Gemfile Caching Trick
RUN mkdir -p /srv/ontoportal/ontologies_linked_data
COPY Gemfile* /srv/ontoportal/ontologies_linked_data
WORKDIR /srv/ontoportal/ontologies_linked_data
RUN gem install bundler -v "$(grep -A 1 "BUNDLED WITH" Gemfile.lock | tail -n 1)"
RUN bundle install --binstubs

COPY . /srv/ontoportal/ontologies_linked_data

# unit tests have to run with unprivileged user
# otherwise TestOWLApi#test_command_KO_output test fails
RUN adduser --disabled-password ontoportal
RUN chown -R ontoportal  /srv/ontoportal/ontologies_linked_data
USER ontoportal
