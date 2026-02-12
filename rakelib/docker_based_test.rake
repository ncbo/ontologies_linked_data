# Docker compose driven unit test orchestration
#
# Notes:
# - Backend names match compose profile names (ag, fs, vo, gd).
# - Hostnames are NOT set here. The app defaults them (localhost for host runs).
# - Linux container env is provided via compose override files:
#     dev/compose/linux/ag.yml
#     dev/compose/linux/fs.yml
#     dev/compose/linux/vo.yml
#     dev/compose/linux/gd.yml
namespace :test do
  namespace :docker do
    BASE_COMPOSE = 'docker-compose.yml'
    LINUX_OVERRIDE_DIR = 'dev/compose/linux'
    LINUX_NO_PORTS_OVERRIDE = "#{LINUX_OVERRIDE_DIR}/no-ports.yml"
    TIMEOUT = (ENV['OP_TEST_DOCKER_TIMEOUT'] || '600').to_i
    DEFAULT_BACKEND = (ENV['OP_TEST_DOCKER_BACKEND'] || 'fs').to_sym

    # Minimal per-backend config for host runs only.
    # Do not set hostnames here. The app defaults them.
    BACKENDS = {
      ag: {
        host_env: {
          'GOO_BACKEND_NAME' => 'allegrograph',
          'GOO_PORT' => '10035',
          'GOO_PATH_QUERY' => '/repositories/ontoportal_test',
          'GOO_PATH_DATA' => '/repositories/ontoportal_test/statements',
          'GOO_PATH_UPDATE' => '/repositories/ontoportal_test/statements'
        }
      },
      fs: {
        host_env: {
          'GOO_BACKEND_NAME' => '4store',
          'GOO_PORT' => '9000',
          'GOO_PATH_QUERY' => '/sparql/',
          'GOO_PATH_DATA' => '/data/',
          'GOO_PATH_UPDATE' => '/update/'
        }
      },
      vo: {
        host_env: {
          'GOO_BACKEND_NAME' => 'virtuoso',
          'GOO_PORT' => '8890',
          'GOO_PATH_QUERY' => '/sparql',
          'GOO_PATH_DATA' => '/sparql',
          'GOO_PATH_UPDATE' => '/sparql'
        }
      },
      gd: {
        host_env: {
          'GOO_BACKEND_NAME' => 'graphdb',
          'GOO_PORT' => '7200',
          'GOO_PATH_QUERY' => '/repositories/ontoportal_test',
          'GOO_PATH_DATA' => '/repositories/ontoportal_test/statements',
          'GOO_PATH_UPDATE' => '/repositories/ontoportal_test/statements'
        }
      }
    }.freeze

    def abort_with(msg)
      warn(msg)
      exit(1)
    end

    def shell!(cmd)
      system(cmd) || abort_with("Command failed: #{cmd}")
    end

    def cfg!(key)
      cfg = BACKENDS[key]
      abort_with("Unknown backend key: #{key}. Supported: #{BACKENDS.keys.join(', ')}") unless cfg
      cfg
    end

    def compose_files(*files)
      files.flatten.map { |f| "-f #{f}" }.join(' ')
    end

    def linux_override_for(key)
      "#{LINUX_OVERRIDE_DIR}/#{key}.yml"
    end

    def compose_up(key, files:)
      # Host tests use only the backend profile. Linux tests add the linux profile.
      # `docker compose up --wait` only applies to services started by `up`,
      # so linux runs still call `run` separately after this wait completes.
      shell!("docker compose #{compose_files(files)} --profile #{key} up -d --wait --wait-timeout #{TIMEOUT}")
    end

    def compose_down(files:)
      return puts('OP_KEEP_CONTAINERS=1 set, skipping docker compose down') if ENV['OP_KEEP_CONTAINERS'] == '1'

      shell!(
        "docker compose #{compose_files(files)} " \
        '--profile ag --profile fs --profile vo --profile gd --profile linux down'
      )
    end

    def apply_host_env(key)
      cfg!(key)[:host_env].each { |k, v| ENV[k] = v }
    end

    def run_host_tests(key)
      apply_host_env(key)
      files = [BASE_COMPOSE]

      compose_up(key, files: files)
      Rake::Task['test'].invoke
    end

    def run_linux_tests(key)
      override = linux_override_for(key)
      abort_with("Missing compose override file: #{override}") unless File.exist?(override)
      abort_with("Missing compose override file: #{LINUX_NO_PORTS_OVERRIDE}") unless File.exist?(LINUX_NO_PORTS_OVERRIDE)

      files = [BASE_COMPOSE, override, LINUX_NO_PORTS_OVERRIDE]
      # docker compose is handleling wait_for_healthy
      compose_up(key, files: files)

      shell!(
        "docker compose #{compose_files(files)} --profile linux --profile #{key} " \
        'run --rm --build test-linux bundle exec rake test TESTOPTS="-v"'
      )
    end

    def run_linux_shell(key)
      override = linux_override_for(key)
      abort_with("Missing compose override file: #{override}") unless File.exist?(override)
      abort_with("Missing compose override file: #{LINUX_NO_PORTS_OVERRIDE}") unless File.exist?(LINUX_NO_PORTS_OVERRIDE)

      files = [BASE_COMPOSE, override, LINUX_NO_PORTS_OVERRIDE]
      compose_up(key, files: files)

      shell!(
        "docker compose #{compose_files(files)} --profile linux --profile #{key} " \
        'run --rm --build test-linux bash'
      )
    end

    #
    # Public tasks
    #

    desc 'Run unit tests with AllegroGraph backend (docker deps, host Ruby)'
    task :ag do
      run_host_tests(:ag)
    ensure
      Rake::Task['test'].reenable
      compose_down(files: [BASE_COMPOSE])
    end

    desc 'Run unit tests with AllegroGraph backend (docker deps, Linux container)'
    task 'ag:linux' do
      files = [BASE_COMPOSE, linux_override_for(:ag)]
      begin
        run_linux_tests(:ag)
      ensure
        compose_down(files: files)
      end
    end

    desc 'Run unit tests with 4store backend (docker deps, host Ruby)'
    task :fs do
      run_host_tests(:fs)
    ensure
      Rake::Task['test'].reenable
      compose_down(files: [BASE_COMPOSE])
    end

    desc 'Run unit tests with 4store backend (docker deps, Linux container)'
    task 'fs:linux' do
      files = [BASE_COMPOSE, linux_override_for(:fs)]
      begin
        run_linux_tests(:fs)
      ensure
        compose_down(files: files)
      end
    end

    desc 'Run unit tests with Virtuoso backend (docker deps, host Ruby)'
    task :vo do
      run_host_tests(:vo)
    ensure
      Rake::Task['test'].reenable
      compose_down(files: [BASE_COMPOSE])
    end

    desc 'Run unit tests with Virtuoso backend (docker deps, Linux container)'
    task 'vo:linux' do
      files = [BASE_COMPOSE, linux_override_for(:vo)]
      begin
        run_linux_tests(:vo)
      ensure
        compose_down(files: files)
      end
    end

    desc 'Run unit tests with GraphDB backend (docker deps, host Ruby)'
    task :gd do
      run_host_tests(:gd)
    ensure
      Rake::Task['test'].reenable
      compose_down(files: [BASE_COMPOSE])
    end

    desc 'Run unit tests with GraphDB backend (docker deps, Linux container)'
    task 'gd:linux' do
      files = [BASE_COMPOSE, linux_override_for(:gd)]
      begin
        run_linux_tests(:gd)
      ensure
        compose_down(files: files)
      end
    end

    desc 'Start a shell in the Linux test container (default backend: fs)'
    task :shell, [:backend] do |_t, args|
      key = (args[:backend] || DEFAULT_BACKEND).to_sym
      cfg!(key)
      files = [BASE_COMPOSE, linux_override_for(key), LINUX_NO_PORTS_OVERRIDE]
      begin
        run_linux_shell(key)
      ensure
        compose_down(files: files)
      end
    end

    desc 'Start backend services for development (default backend: fs)'
    task :up, [:backend] do |_t, args|
      key = (args[:backend] || DEFAULT_BACKEND).to_sym
      cfg!(key)
      compose_up(key, files: [BASE_COMPOSE])
    end

    desc 'Stop backend services for development (default backend: fs)'
    task :down, [:backend] do |_t, args|
      compose_down(files: [BASE_COMPOSE])
    end
  end
end
