ARG RUBY_VERSION=3.2
ARG DISTRO=bullseye

FROM ruby:$RUBY_VERSION-$DISTRO

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    libxml2 \
    libxslt-dev \
    libxslt1-dev zlib1g-dev \
    openjdk-11-jre-headless \
    raptor2-utils \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# set default test config
COPY config/config.test.rb config/config.rb

COPY Gemfile* *.gemspec ./

# Copy only the `version.rb` file to prevent missing file errors!
COPY lib/ontologies_linked_data/version.rb lib/ontologies_linked_data/


#Install the exact Bundler version from Gemfile.lock (if it exists)
RUN gem update --system && \
    if [ -f Gemfile.lock ]; then \
      BUNDLER_VERSION=$(grep -A 1 "BUNDLED WITH" Gemfile.lock | tail -n 1 | tr -d ' '); \
      gem install bundler -v "$BUNDLER_VERSION"; \
    else \
      gem install bundler; \
    fi

RUN bundle config set --global no-document 'true'
RUN bundle install --jobs 4 --retry 3

COPY . ./

CMD ["bundle", "exec", "rake"]
