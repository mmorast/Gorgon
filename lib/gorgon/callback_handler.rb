class CallbackHandler
  def initialize(config)
    @config = config || {}
  end

  def before_start
    load(@config[:before_start]) if @config[:before_start]
  end

  def after_complete
    load(@config[:after_complete]) if @config[:after_complete]
  end

  def before_creating_workers
    load(@config[:before_creating_workers]) if @config[:before_creating_workers]
  end
end
