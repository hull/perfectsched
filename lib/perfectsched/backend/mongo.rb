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

require 'mongo'

module PerfectSched
  module Backend
    class MongoBackend
      include BackendHelper
      MAX_RETRY = 10

      class Token < Struct.new(:row_id, :scheduled_time, :cron, :delay, :timezone)
      end

      def initialize(client, config)
        super

        url = config[:url]
        unless url
          raise ConfigError, "url option is required for the mongo backend"
        end

        @mongo = Mongo::Client.new(url)
        @db = @mongo.database
        @collection = @db[config[:collection] || "perfectsched"]
        @mutex = Mutex.new

        connect {
          # connection test
        }
      end

      MAX_SELECT_ROW = 4

      attr_reader :collection, :db

      def init_database(options)
        # TODO: ensure index
      end


      def find(criteria = {}, options = {})
        if criteria.is_a?(Hash)
          Enumerator.new do |y|
            cursor = @collection.find(criteria)
            if options[:sort]
              cursor = cursor.sort(options[:sort])
            end
            if options[:limit]
              cursor = cursor.limit(options[:limit])
            end
            cursor.map do |i|
              y << i.symbolize_keys
            end
          end
        else
          ret = @collection.find({ _id: criteria }).first
          ret && ret.symbolize_keys
        end
      end

      def get_schedule_metadata(key, options={})
        connect {
          row = find(key)
          unless row
            raise NotFoundError, "schedule key=#{key} does not exist"
          end
          attributes = create_attributes(row)
          return ScheduleWithMetadata.new(@client, key, attributes)
        }
      end

      def list(options, &block)
        connect {
          find.each { |row|
            attributes = create_attributes(row)
            sched = ScheduleWithMetadata.new(@client, row[:_id], attributes)
            yield sched
          }
        }
      end

      def add(key, type, cron, delay, timezone, data, next_time, next_run_time, options)
        connect {
          data = data ? data.dup : {}
          data['type'] = type
          begin
            @collection.insert_one({
              _id: key,
              timeout: next_run_time,
              next_time: next_time,
              cron: cron,
              delay: delay,
              data: data.to_json,
              timezone: timezone
            })
            return Schedule.new(@client, key)
          rescue Mongo::Error::OperationFailure => err
            raise IdempotentAlreadyExistsError, "schedule key=#{key} already exists" if err.code == 11000
          end
        }
      end

      def delete(key, options)
        connect {
          res = @collection.delete_one({ _id: key })
          if res.deleted_count <= 0
            raise IdempotentNotFoundError, "schedule key=#{key} does no exist"
          end
        }
      end

      def modify(key, options)
        connect {
          attrs = options.slice(:cron, :delay, :timezone)
          return nil unless attrs.present?

          res = @collection.update_one({ _id: key }, {'$set' => attrs })
          if res.n <= 0
            raise NotFoundError, "schedule key=#{key} does not exist"
          end
        }
      end

      def acquire(alive_time, max_acquire, options)
        now = (options[:now] || Time.now).to_i
        next_timeout = now + alive_time

        connect {
          while true
            rows = 0
            find({ timeout: { '$lte' => now } }, sort: { timeout: 1 }, limit: MAX_SELECT_ROW).map { |row|
              res = @collection.update_one({ _id: row[:_id], timeout: row[:timeout] }, { '$set' => { timeout: next_timeout } })
              if res.n > 0
                scheduled_time = row[:next_time]
                attributes = create_attributes(row)
                task_token = Token.new(row[:_id], row[:next_time], attributes[:cron], attributes[:delay], attributes[:timezone])
                task = Task.new(@client, row[:_id], attributes, scheduled_time, task_token)
                return [task]
              end
              rows += 1
            }
            if rows < MAX_SELECT_ROW
              return nil
            end
          end
        }
      end

      def heartbeat(task_token, alive_time, options)
        now = (options[:now] || Time.now).to_i
        row_id = task_token.row_id
        scheduled_time = task_token.scheduled_time
        next_run_time = now + alive_time

        connect {
          res = @collection.update_one({ _id: row_id, next_time: scheduled_time }, { '$set' => { timeout: next_run_time } })
          if res.n <= 0  # TODO fix
            row = find({ _id: row_id, next_time: scheduled_time }).first
            if row == nil
              raise PreemptedError, "task #{task_token.inspect} does not exist or preempted."
            elsif row[:timeout] == next_run_time
              # ok
            else
              raise PreemptedError, "task time=#{Time.at(scheduled_time).utc} is preempted"
            end
          end
        }
      end

      def finish(task_token, options)
        row_id = task_token.row_id
        scheduled_time = task_token.scheduled_time
        next_time = PerfectSched.next_time(task_token.cron, scheduled_time, task_token.timezone)
        next_run_time = next_time + task_token.delay

        connect {
          ret = @collection.update_one({ _id: row_id, next_time: scheduled_time }, { '$set' => { timeout: next_run_time, next_time: next_time, last_time: Time.now.to_i } })
          
          if ret.n <= 0
            rec = @collection.find(_id: row_id).first
            STDERR.puts "[perfectsched][IdempotentAlreadyFinishedError] task id=#{row_id} task=#{rec} next_time=#{scheduled_time} time=#{Time.at(scheduled_time).utc} is already finished\n"
            raise IdempotentAlreadyFinishedError, "task id=#{row_id} task=#{rec} next_time=#{scheduled_time} time=#{Time.at(scheduled_time).utc} is already finished"
          end
        }
      end

      protected

      def connect(&block)
        @mutex.synchronize do
          retry_count = 0
          begin
            block.call
          rescue
            # workaround for "Mysql2::Error: Deadlock found when trying to get lock; try restarting transaction" error
            if $!.to_s.include?('try restarting transaction')
              err = ([$!] + $!.backtrace.map {|bt| "  #{bt}" }).join("\n")
              retry_count += 1
              if retry_count < MAX_RETRY
                STDERR.puts err + "\n  retrying."
                sleep 0.5
                retry
              else
                STDERR.puts err + "\n  abort."
              end
            end
            raise
          ensure
            @mongo.close
          end
        end
      end

      def create_attributes(row)
        timezone = row[:timezone] || 'UTC'
        delay = row[:delay] || 0
        cron = row[:cron]
        last_time = row[:last_time]
        next_time = row[:next_time]
        next_run_time = row[:timeout]

        d = row[:data]
        if d == nil || d == ''
          data = {}
        elsif d.is_a?(Hash)
          data = d
        elsif d.is_a?(String)
          begin
            data = JSON.parse(d)
          rescue
            data = {}
          end
        end

        type = data.delete('type')
        if type == nil || type.empty?
          type = row[:_id].split(/\./, 2)[0]
        end

        attributes = {
          :timezone => timezone,
          :delay => delay,
          :cron => cron,
          :data => data,
          :last_time => last_time,
          :next_time => next_time,
          :next_run_time => next_run_time,
          :type => type,
          :message => nil,  # not supported
          :node => nil,  # not supported
        }
      end

    end
  end
end

