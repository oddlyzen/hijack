module Hijack
  class Console
    def initialize(pid)
      @pid = pid
      @remote = nil
      check_pid
      str = "=> Hijacking..."
      $stdout.write(str)
      $stdout.flush
      Payload.inject(@pid)
      connect
      $stdout.write("\b" * str.size)
      $stdout.flush
      mirror_process
      banner
      execute_file
      OutputReceiver.start(@remote) unless Hijack.options[:mute]
      start_irb
    end

  protected
    def check_pid
      begin
        Process.kill(0, @pid.to_i)
      rescue Errno::EPERM
        puts "=> You do not have the correct permissions to hijack #{@pid}"
        exit 1
      rescue Errno::ESRCH
        puts "=> No such process #{@pid}"
        exit 1
      end
    end

    def connect
      loop do
        break if File.exists?(Hijack.socket_path_for(@pid))
        sleep 0.01
      end
      @remote = DRbObject.new(nil, Hijack.socket_for(@pid))
    end

    module OutputReceiver
      class << self
        def mute
          @mute = true
        end

        def unmute(remote)
          start(remote) unless @started
          @mute = false
        end

        def write(where, str)
          Object.const_get(where.upcase).write(str) unless @mute
        end

        def puts(where, str)
          Object.const_get(where.upcase).puts(str) unless @mute
        end

        def start(remote)
          DRb.start_service(Hijack.socket_for(Process.pid), self)
          remote.evaluate("__hijack_output_receiver_ready_#{Process.pid}")
          @started = true
        end
      end
    end

    def mirror_process
      # Attempt to require all files currently loaded by the remote process so DRb can dump as many objects as possible.
      #
      # We have to first require everything in reverse order and then in the original order.
      # This is because when you require file_a.rb which first sets a constant then requires file_b.rb
      # the $" array will contain file_b.rb before file_a.rb. But if we require file_b.rb before file_a.rb
      # we'll get a missing constant error.
      load_path, loaded_files = @remote.evaluate('[$:, $"]')
      to_load = (loaded_files - $").uniq
      completion_percentage = 0
      str = '=> Mirroring: '
      percent_str = ''
      $stdout.write(str)
      $stdout.flush
      $:.clear
      $:.push(*load_path)
      orig_stderr = $stderr
      $stderr = File.open('/dev/null')
      (to_load.reverse + to_load).each_with_index do |file, i|
        begin
          require file
        rescue Exception, LoadError
        end
        $stdout.write("\b" * percent_str.size)
        $stdout.flush
        percent_str = "#{(((i + 1) / (to_load.size * 2).to_f) * 100.0).round}%"
        $stdout.write(percent_str)
        $stdout.flush
      end
      $stderr = orig_stderr
      $stdout.write("\b" * (str.size + percent_str.size))
      $stdout.flush
    end

    def start_irb
      ARGV.replace ["--simple-prompt"]
      IRB.setup(nil)
      workspace = Hijack::Workspace.new
      workspace.remote = @remote
      workspace.pid = @pid
      irb = IRB::Irb.new(workspace)
      @CONF = IRB.instance_variable_get(:@CONF)
      @CONF[:IRB_RC].call irb.context if @CONF[:IRB_RC]
      @CONF[:MAIN_CONTEXT] = irb.context
      @CONF[:PROMPT_MODE] = :SIMPLE
      trap('SIGINT') { irb.signal_handle }
      catch(:IRB_EXIT) { irb.eval_input }
    end

    def banner
      script, ruby_version, platform, hijack_version = @remote.evaluate('[$0, RUBY_VERSION, RUBY_PLATFORM]')
      puts "=> Hijacked #{@pid} (#{script}) (ruby #{ruby_version} [#{platform}])"
    end

    def execute_file
      if Hijack.options[:execute]
        if File.exists?(Hijack.options[:execute])
          $stdout.write("=> Executing #{Hijack.options[:execute]}... ")
          $stdout.flush
          @remote.evaluate(File.read(Hijack.options[:execute]))
          puts "done!"
          exit
        else
          puts "=> Can't find #{Hijack.options[:execute]} to execute!"
        end
      end
    end
  end
end
