$:.unshift(File.dirname(__FILE__))
require 'stringio'
require 'drb'
require 'drb/unix'
require 'rbconfig'
require 'irb'
require 'irb/completion'
require 'hijack/console'
require 'hijack/gdb'
require 'hijack/payload'
require 'hijack/helper'
require 'hijack/workspace'

module Hijack
  def self.start(pid, options)
    @@options = options
    Console.new(pid)
  end

  def self.options
    @@options
  end

  def self.socket_for(pid)
    "drbunix:/#{socket_path_for(pid)}"
  end

  def self.socket_path_for(pid)
    "/tmp/hijack.#{pid}.sock"
  end
end
