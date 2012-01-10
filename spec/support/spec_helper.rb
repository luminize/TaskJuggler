#!/usr/bin/env ruby -w
# encoding: UTF-8
#
# = spec_helper.rb -- The TaskJuggler III Project Management Software
#
# Copyright (c) 2006, 2007, 2008, 2009, 2010, 2011
#               by Chris Schlaeger <chris@linux.com>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of version 2 of the GNU General Public License as
# published by the Free Software Foundation.
#

RSpec.configure do |c|
  c.filter_run_excluding :ruby => lambda {|version|
    !(RUBY_VERSION.to_s =~ /^#{version.to_s}/)
  }
end

