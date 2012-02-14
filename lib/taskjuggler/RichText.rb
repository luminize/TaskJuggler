#!/usr/bin/env ruby -w
# encoding: UTF-8
#
# = RichText.rb -- The TaskJuggler III Project Management Software
#
# Copyright (c) 2006, 2007, 2008, 2009, 2010, 2011, 2012
#               by Chris Schlaeger <chris@linux.com>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of version 2 of the GNU General Public License as
# published by the Free Software Foundation.
#

require 'taskjuggler/RichText/Element'
require 'taskjuggler/RichText/Parser'
require 'taskjuggler/MessageHandler'

class TaskJuggler

  # RichText is a MediaWiki markup parser and HTML generator implemented in
  # pure Ruby. It can also generate plain text versions of the original markup
  # text.  It is based on the TextParser class to implement the
  # RichTextParser. The scanner is implemented in the RichTextScanner class.
  # The read-in text is converted into a tree of RichTextElement objects.
  # These can then be turned into HTML element trees modelled by XMLElement or
  # plain text.
  #
  # This class supports the following mark-ups:
  #
  # The following markups are block commands and must start at the beginning of
  # the line.
  #
  #  == Headline 1 ==
  #  === Headline 2 ===
  #  ==== Headline 3 ====
  #
  #  ---- creates a horizontal line
  #
  #  * Bullet 1
  #  ** Bullet 2
  #  *** Bullet 3
  #
  #  # Enumeration Level 1
  #  ## Enumeration Level 2
  #  ### Enumeration Level 3
  #
  #   Preformatted text start with
  #   a single space at the start of
  #   each line.
  #
  #
  # The following are in-line mark-ups and can occur within any text block
  #
  #  This is an ''italic'' word.
  #  This is a '''bold''' word.
  #  This is a ''''monospaced'''' word. This is not part of the original
  #  MediaWiki markup, but we needed monospaced as well.
  #  This is a '''''italic and bold''''' word.
  #
  # Linebreaks are ignored if not followed by a blank line.
  #
  #  [http://www.taskjuggler.org] A web link
  #  [http://www.taskjuggler.org The TaskJuggler Web Site] another link
  #
  #  [[item]] site internal internal reference (in HTML .html gets appended
  #                                             automatically)
  #  [[item An item]] another internal reference
  #  [[function:path arg1 arg2 ...]]
  #
  #  <nowiki> ... </nowiki> Disable markup interpretation for the enclosed
  #  portion of text.
  #
  class RichText

    attr_reader :inputText

    # The Parser uses complex to setup data structures that are identical for
    # all RichText instances. So, we'll share them across the instances.
    @@parser = nil

    # Create a rich text object by passing a String with markup elements to it.
    # _text_ must be plain text with MediaWiki compatible markup elements. In
    # case an error occurs, an exception of type TjException will be raised.
    # _functionHandlers_ is a Hash that maps RichTextFunctionHandler objects
    # by their function name.
    def initialize(text, functionHandlers = [])
      # Keep a copy of the original text.
      @inputText = text
      @functionHandlers = functionHandlers
    end

    # Convert the @inputText into an abstract syntax tree that can then be
    # converted into the various output formats. _sectionCounter_ is an Array
    # that holds the initial values for the section counters.
    def generateIntermediateFormat(sectionCounter = [ 0, 0, 0], tokenSet = nil)
      rti = RichTextIntermediate.new(self)
      # Copy the function handlers.
      @functionHandlers.each do |h|
        rti.registerFunctionHandler(h)
      end

      # We'll setup the RichTextParser once and share it across all instances.
      if @@parser
        # We already have a RichTextParser that we can reuse.
        @@parser.reuse(rti, sectionCounter, tokenSet)
      else
        # There is no RichTextParser yet, create one.
        @@parser = RichTextParser.new(rti, sectionCounter, tokenSet)
      end

      @@parser.open(@inputText)
      # Parse the input text and convert it to the intermediate representation.
      return nil if (tree = @@parser.parse(:richtext)) == false

      # In case the result is empty, use an empty RichTextElement as result
      tree = RichTextElement.new(rti, :richtext, nil) unless tree
      tree.cleanUp
      rti.tree = tree
      rti
    end

    # Return the RichTextFunctionHandler for the function _name_. _block_
    # specifies whether we are looking for a block or inline function.
    def functionHandler(name, block)
      @functionHandlers.each do |handler|
        return handler if handler.function == name &&
                          handler.blockFunction == block
      end
      nil
    end

    private

  end

  # The RichTextIntermediate is a container for the intermediate
  # representation of a RichText object. By calling the to_* members it can be
  # converted into the respective formats. A RichTextIntermediate object is
  # generated by RichText::generateIntermediateFormat.
  class RichTextIntermediate

    attr_reader :richText, :functionHandlers
    attr_accessor :blockMode, :sectionNumbers,
                  :lineWidth, :indent, :titleIndent, :parIndent, :listIndent,
                  :preIndent,
                  :linkTarget, :cssClass, :tree

    def initialize(richText)
      # A reference to the corresponding RichText object the RTI is derived
      # from.
      @richText = richText
      # The root of the generated intermediate format. This is a
      # RichTextElement.
      @tree = nil
      # The blockMode specifies whether the RichText should be interpreted as
      # a line of text or a block (default).
      @blockMode = true
      # Set this to false to disable automatically generated section numbers.
      @sectionNumbers = true
      # Set this to the maximum width used for text output.
      @lineWidth = 80
      # The indentation used for all text output.
      @indent = 0
      # Additional indentation used for titles in text output.
      @titleIndent = 0
      # Additional indentation used for paragraph text output.
      @parIndent = 0
      # Additional indentation used for lists in text output.
      @listIndent = 1
      # Additional indentation used for <pre> sections in text output.
      @preIndent = 0
      # The target used for hypertext links.
      @linkTarget = nil
      # The CSS class used for some key HTML elements.
      @cssClass = nil
      # These are the RichTextFunctionHandler objects to handle references with
      # a function specification.
      @functionHandlers = {}
    end

    # Use this function to register new RichTextFunctionHandler objects with
    # this class.
    def registerFunctionHandler(functionHandler)
      raise "Bad function handler" unless functionHandler
      @functionHandlers[functionHandler.function] = functionHandler.dup
    end

    # Return the handler for the given _function_ or raise an exception if it
    # does not exist.
    def functionHandler(function)
      @functionHandlers[function]
    end

    # Return true if the RichText has no content.
    def empty?
      @tree.empty?
    end

    # Recursively extract the section headings from the RichTextElement and
    # build the TableOfContents _toc_ with the gathered sections.  _fileName_
    # is the base name (without .html or other suffix) of the file the
    # TOCEntries should point to.
    def tableOfContents(toc, fileName)
      @tree.tableOfContents(toc, fileName)
    end

    # Return an Array with all other snippet names that are referenced by
    # internal references in this RichTextElement.
    def internalReferences
      @tree.internalReferences
    end

    # Convert the intermediate format into a plain text String object.
    def to_s
      str = @tree.to_s
      str.chomp! while str[-1] == ?\n
      str
    end

    # Convert the intermediate format into a XMLElement objects tree.
    def to_html
      html = @tree.to_html
      html.chomp! while html[-1] == ?\n
      html
    end

    # Convert the intermediate format into a tagged syntax String object.
    def to_tagged
      @tree.to_tagged
    end

  end

end

