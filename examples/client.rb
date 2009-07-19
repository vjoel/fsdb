#!/usr/bin/env ruby

require 'drb'

uri = ARGV.shift || "druby://localhost:9300"

DRb.start_service
db = DRbObject.new(nil, uri)

db['foo'] = {:zap => 1}
db['bar'] = "BAR"

p db['foo']
p db['bar']

db.edit 'foo' do |foo|
  foo[:zap] = 2 # This has no effect because it is operating on a local copy.
end

p db['foo']

db.replace 'foo' do |foo|
  foo[:zap] = 2 # This works because we are sending back a new copy of foo.
  foo # remember to return the object from the block
end

p db['foo']
