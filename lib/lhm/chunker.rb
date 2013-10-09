# Copyright (c) 2011 - 2013, SoundCloud Ltd., Rany Keddo, Tobias Bielohlawek, Tobias
# Schmidt

require 'lhm/command'
require 'lhm/sql_helper'

module Lhm
  class Chunker
    include Command
    include SqlHelper

    attr_reader :connection

    # Copy from origin to destination in chunks of size `stride`. Sleeps for
    # `throttle` milliseconds between each stride.
    def initialize(migration, connection = nil, options = {})
      @migration = migration
      @connection = connection
      @throttler = options[:throttler]
      @start = options[:start] || select_start
      @limit = options[:limit] || select_limit
    end

    def execute
      return unless @start && @limit
      @next_to_insert = @start
      until @next_to_insert >= @limit
        stride = @throttler.stride
        affected_rows = @connection.update(copy(bottom, top(stride)))

        if @throttler && affected_rows > 0
          @throttler.run
        end

        print "."
        @next_to_insert = top(stride) + 1
      end
      print "\n"
    end

  private

    def bottom
      @next_to_insert
    end

    def top(stride)
      [(@next_to_insert + stride - 1), @limit].min
    end

    def copy(lowest, highest)
      "insert ignore into `#{ destination_name }` (#{ columns }) " +
      "select #{ select_columns } from `#{ origin_name }` " +
      "#{ conditions } #{ origin_name }.`id` between #{ lowest } and #{ highest }"
    end

    def select_start
      start = connection.select_value("select min(id) from #{ origin_name }")
      start ? start.to_i : nil
    end

    def select_limit
      limit = connection.select_value("select max(id) from #{ origin_name }")
      limit ? limit.to_i : nil
    end

    def conditions
      @migration.conditions ? "#{@migration.conditions} and" : "where"
    end

    def destination_name
      @migration.destination.name
    end

    def origin_name
      @migration.origin.name
    end

    def columns
      @columns ||= @migration.intersection.joined
    end

    def select_columns
      @select_columns ||= @migration.intersection.typed(origin_name)
    end

    def validate
      if @start && @limit && @start > @limit
        error("impossible chunk options (limit must be greater than start)")
      end
    end
  end
end
