#!/usr/bin/env ruby -w
# encoding: UTF-8
#
# = Tj3AppBase.rb -- The TaskJuggler III Project Management Software
#
# Copyright (c) 2006, 2007, 2008, 2009, 2010, 2011
#               by Chris Schlaeger <chris@linux.com>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of version 2 of the GNU General Public License as
# published by the Free Software Foundation.
#

require 'rubygems'
require 'optparse'
require 'taskjuggler/Tj3Config'
require 'taskjuggler/RuntimeConfig'
require 'taskjuggler/TjTime'
require 'taskjuggler/TextFormatter'
require 'taskjuggler/Log'

class TaskJuggler

  class TjRuntimeError < RuntimeError
  end

  class Tj3AppBase

    def initialize
      # Indent and width of options. The deriving class may has to change
      # this.
      @optsSummaryWidth = 22
      @optsSummaryIndent = 5
      # Show some progress information by default
      @silent = false
      @configFile = nil
      @mandatoryArgs = ''
      @mininumRubyVersion = '1.9.2'
    end

    def processArguments(argv)
      @opts = OptionParser.new
      @opts.summary_width = @optsSummaryWidth
      @opts.summary_indent = ' ' * @optsSummaryIndent

      @opts.banner = "#{AppConfig.softwareName} v#{AppConfig.version} - " +
                     "#{AppConfig.packageInfo}\n\n" +
                     "Copyright (c) #{AppConfig.copyright.join(', ')}\n" +
                     "              by #{AppConfig.authors.join(', ')}\n\n" +
                     "#{AppConfig.license}\n" +
                     "For more info about #{AppConfig.softwareName} see " +
                     "#{AppConfig.contact}\n\n" +
                     "Usage: #{AppConfig.appName} [options] " +
                     "#{@mandatoryArgs}\n\n"
      @opts.separator ""
      @opts.on('-c', '--config <FILE>', String,
               format('Use the specified YAML configuration file')) do |arg|
         @configFile = arg
      end
      @opts.on('--silent',
               format("Don't show program and progress information")) do
        @silent = true
        TaskJuggler::Log.silent = true
      end
      @opts.on('--debug', format('Enable Ruby debug mode')) do
        $DEBUG = true
      end

      yield

      @opts.on_tail('-h', '--help', format('Show this message')) do
        puts @opts.to_s
        quit
      end
      @opts.on_tail('--version', format('Show version info')) do
        puts "#{AppConfig.softwareName} v#{AppConfig.version} - " +
          "#{AppConfig.packageInfo}"
        quit
      end

      begin
        files = @opts.parse(argv)
      rescue OptionParser::ParseError => msg
        puts @opts.to_s + "\n"
        error(msg.message, 2)
      end

      files
    end

    def main(argv = ARGV)
      if Gem::Version.new(RUBY_VERSION.dup) <
         Gem::Version.new(@mininumRubyVersion)
        error('This program requires at least Ruby version ' +
              "#{@mininumRubyVersion}!")
      end

      # Install signal handler to exit gracefully on CTRL-C.
      intHandler = Kernel.trap('INT') do
        error("Aborting on user request!")
      end

      begin
        args = processArguments(argv)

        # If DEBUG mode has been enabled, we restore the INT trap handler again
        # to get Ruby backtrackes.
        Kernel.trap('INT', intHandler) if $DEBUG

        unless @silent
          puts "#{AppConfig.softwareName} v#{AppConfig.version} - " +
               "#{AppConfig.packageInfo}\n\n" +
               "Copyright (c) #{AppConfig.copyright.join(', ')}\n" +
               "              by #{AppConfig.authors.join(', ')}\n\n" +
               "#{AppConfig.license}\n"
        end

        @rc = RuntimeConfig.new(AppConfig.packageName, @configFile)

        appMain(args)
      rescue Exception => e
        if e.is_a?(SystemExit) || e.is_a?(Interrupt)
          # Don't show backtrace on user interrupt unless we are in debug mode.
          $stderr.puts e.backtrace.join("\n") if $DEBUG
          1
        else
          error("Ups, you have triggered a bug in #{AppConfig.softwareName}!\n" +
                "#{e}\n" +
                e.backtrace.join("\n") +
                "Please see the user manual on how to get this bug fixed!")
        end
      end
    end

    private

    def quit
      exit 0
    end

    def error(message, exitVal = 1)
      $stderr.puts "\nERROR: #{message}"
      exit exitVal
    end

    def format(str, indent = nil)
      indent = @optsSummaryWidth + @optsSummaryIndent + 1 unless indent
      TextFormatter.new(79, indent).format(str)[indent..-1]
    end

  end

end

