def docker_setup(forks = 1)
  container_ids = []
  services = %w(fourstore redis solr)
  internal_ports = {"fourstore" => 8080, "redis" => 6379, "solr" => 8983}

  # Start docker containers (serially, docker seems to have problems with concurrency)
  ports = {}
  puts "Creating #{forks} infrastructure environments"
  forks.times do |i|
    # Start redis, solr, and 4store
    services.each do |srv|
      started = false
      attempts = 0
      container_id = nil
      until started || attempts > 10
        if container_id
          `docker kill #{container_id}`
          `docker rm #{container_id}`
        end
        container_id = `docker run -t -d -p #{internal_ports[srv]} palexander/#{srv}`.strip
        started = $?.success?
        attempts += 1
      end
      container_ids << container_id
      ports["#{srv}#{i}"] = `docker port #{container_id} #{internal_ports[srv]}`.split(":").last.to_i
    end
  end

  # Let docker start
  sleep(15)

  return ports, container_ids
end

def docker_tests
  test_files = Dir["**/test_*.rb"]
  test_files.each {|f| File.expand_path(test_files, __FILE__)}
  exit
  begin
    ports, container_ids = docker_setup(1)

    require_relative '../lib/ontologies_linked_data'

    LinkedData.config do |config|
      config.goo_port          = ports["fourstore#{0}"]
      config.goo_redis_port    = ports["redis#{0}"]
      config.http_redis_port   = ports["redis#{0}"]
      config.search_server_url = "http://localhost:#{ports["solr0"]}/solr/"
    end

    require_relative "test_case"
    test_files.each {|f| require f}

    Minitest.run
  rescue => e
    puts e.message
    puts e.backtrace.join("\n\t")
  ensure
    puts "\n\nStopping docker containers"
    container_ids.each {|id| `docker kill #{id} && docker rm #{id}`} if container_ids
  end
end

def docker_tests_forked(forks)
  forks = forks || ENV['forks'] || 4

  ports, container_ids = docker_setup(forks)

  require_relative '../lib/ontologies_linked_data'

  test_files = FileList['**/test*.rb'].shuffle
  test_files_sliced = test_files.each_slice(test_files.length / forks).to_a

  begin
    pids = []
    forks.times do |i|
      pids << fork do
        puts "Fork #{i} testing #{test_files_sliced[i].join(", ")}"

        begin
          # redirect stdout
          require 'stringio'
          sio = StringIO.new
          $stdout = sio
          $stderr = sio

          LinkedData.config do |config|
            config.goo_port          = ports["fourstore#{i}"]
            config.goo_redis_port    = ports["redis#{i}"]
            config.http_redis_port   = ports["redis#{i}"]
            config.search_server_url = "http://localhost:#{ports["solr"+i.to_s]}/solr/"
          end

          require_relative "test_case"

          test_files_sliced[i].each {|f| require f}

          Minitest.run
        rescue => e
          sio << "\n#{e.message}\n#{e.backtrace.join("\t\n")}"
        ensure
          # reset stdout
          $stdout = STDOUT
          sio.rewind

          puts "", "", "Fork #{i} completed, output:", sio.read, ""
          Kernel.exit! # force the fork to end without running at_exit bindings
        end
      end
    end

    pids.each {|pid| Process.wait(pid)}
  rescue => e
    puts e.message
    puts e.backtrace.join("\n\t")
  ensure
    puts "\n\nStopping docker containers"
    container_ids.each {|id| `docker kill #{id} && docker rm #{id}`} if container_ids
    Kernel.exit! # force the process to quit without minitest's autorun (triggered on at_exit)
  end
end
