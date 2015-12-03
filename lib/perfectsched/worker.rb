#
# PerfectSched
#
# Copyright (C) 2012 FURUHASHI Sadayuki
#
#    Licensed under the Apache License, Version 2.0 (the "License");
#    you may not use this file except in compliance with the License.
#    You may obtain a copy of the License at
#
#        http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific language governing permissions and
#    limitations under the License.
#

module PerfectSched

  class Worker
    def self.run(runner, config=nil, &block)
      new(runner, config, &block).run
    end

    def initialize(runner, config=nil, &block)
      # initial logger
      STDERR.sync = true
      @log = DaemonsLogger.new(STDERR)

      @runner = runner
      block = Proc.new { config } if config
      @config_load_proc = block
      @finished = false
    end

    def run
      @sig = install_signal_handlers
      begin
        @engine = Engine.new(@runner, load_config)
        begin
          until @finished
            @engine.run
          end
        ensure
          @engine.shutdown
        end
      ensure
        @sig.stop
      end
      return nil
    rescue
      @log.error "#{$!.class}: #{$!}"
      $!.backtrace.each {|x| @log.error "  #{x}" }
      return nil
    end

    def stop
      @log.info "stop"
      begin
        @finished = true
        @engine.stop if @engine
      rescue
        @log.error "failed to stop: #{$!}"
        $!.backtrace.each {|bt| @log.warn "\t#{bt}" }
        return false
      end
      return true
    end

    def restart
      @log.info "Received restart"
      begin
        engine = Engine.new(@runner, load_config)
        current = @engine
        @engine = engine
        current.shutdown
      rescue
        @log.error "failed to restart: #{$!}"
        $!.backtrace.each {|bt| @log.warn "\t#{bt}" }
        return false
      end
      return true
    end

    def replace(command=[$0]+ARGV)
      @log.info "replace"
      begin
        return if @replaced_pid
        stop
        @replaced_pid = Process.spawn(*command)
      rescue
        @log.error "failed to replace: #{$!}"
        $!.backtrace.each {|bt| @log.warn "\t#{bt}" }
        return false
      end
      self
    end

    def logrotated
      @log.info "reopen a log file"
      begin
        @log.reopen!
      rescue
        @log.error "failed to restart: #{$!}"
        $!.backtrace.each {|bt| @log.warn "\t#{bt}" }
        return false
      end
      return true
    end

    private
    def load_config
      raw_config = @config_load_proc.call
      config = {}
      raw_config.each_pair {|k,v| config[k.to_sym] = v }

      log = DaemonsLogger.new(config[:log] || STDERR)
      if old_log = @log
        old_log.close
      end
      @log = log

      config[:logger] = log

      return config
    end

    def install_signal_handlers(&block)
      s = self
      SignalThread.new do |st|
        st.trap :TERM do
          s.stop
        end
        st.trap :INT do
          s.stop
        end

        st.trap :QUIT do
          s.stop
        end

        st.trap :USR1 do
          s.restart
        end

        st.trap :HUP do
          s.restart
        end

        st.trap :USR2 do
          s.logrotated
        end
      end
    end
  end

end

