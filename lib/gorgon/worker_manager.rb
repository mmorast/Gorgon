require "gorgon/g_logger"

class WorkerManager
  include GLogger

  def self.build listener_config_file
    @listener_config_file = listener_config_file
    config = Configuration.load_configuration_from_file(listener_config_file)

    new config
  end

  def initialize config
    initialize_logger config[:log_file]
    log "Initializing Worker Manager"

    @config = config

    payload = Yajl::Parser.new(:symbolize_keys => true).parse($stdin.read)
    @job_definition = JobDefinition.new(payload)

    @callback_handler = CallbackHandler.new(config[:callback_handler])
    @available_worker_slots = config[:worker_slots]
  end

  def manage
    fork_workers @available_worker_slots
  end

  private

  def fork_workers n_workers
    log "Forking #{n_workers} worker(s)"

    EventMachine.run do
      n_workers.times do
        fork_a_worker
      end
    end
  end

  def fork_a_worker
    @available_worker_slots -= 1
    ENV["GORGON_CONFIG_PATH"] = @listener_config_filename
    pid, stdin, stdout, stderr = pipe_fork
    stdin.write(@job_definition.to_json)
    stdin.close

    watcher = proc do
      ignore, status = Process.waitpid2 pid
      log "Worker #{pid} finished"
      status
    end

    worker_complete = proc do |status|
      if status.exitstatus != 0
        log_error "Worker #{pid} crashed with exit status #{status.exitstatus}!"
        reply = {:type => :crash,
          :hostname => Socket.gethostname,
          :stdout => stdout.read,
          :stderr => stderr.read}
        @reply_exchange.publish(Yajl::Encoder.encode(reply))
      end
    end
    EventMachine.defer(watcher, worker_complete)
  end

  def pipe_fork
    pid = fork do
      bind_to_fifos

      exit
    end

    fifo_in = pipe_file pid, "in"
    fifo_out = pipe_file pid, "out"
    fifo_err = pipe_file pid, "err"

    return pid, File.open(fifo_in, "w"), File.open(fifo_out, "w"), File.open(fifo_err, "w")
  end

  def pipe_file pid, stream
    "#{pid}_#{stream}.pipe"
  end

  def bind_to_fifos
    fifo_in = pipe_file $$, "in"
    fifo_out = pipe_file $$, "out"
    fifo_err = pipe_file $$, "err"

    system("mkfifo '#{fifo_in}'")
    system("mkfifo '#{fifo_out}'")
    system("mkfifo '#{fifo_err}'")

    @@old_in = $stdin
    $stdin = File.open(fifo_in)

    @@old_out = $stdout
    $stdout = File.open(fifo_out)

    @@old_err = $stderr
    $stderr = File.open(fifo_err)
  end
end
