#!/usr/bin/env ruby 
#
#
#
require 'rubygems'
require 'nokogiri'
require 'unirest'
require 'tty'
require 'concurrent'
require 'pry'

module Bookmarks
  
  def load_bookmarks file_name
    Nokogiri::HTML(File.read(file_name)) 
  end

  def get_links(format, page)


    case format
    when :safari
      # Grab each list of links
      links = page.css('//a')
      links = links.reject { |v| !v.attributes.has_key? 'href' }
      links = links.reject { |v| !v.attributes['href'].value.match(/^(http|https)/) }
      links = links.collect { |v| v.attributes['href'].value }  
    else
      raise BookmarksError.new "Didn't specify a valid brower to get_links" 
    end

    if links
      safe_array = Concurrent::Array.new
      safe_array << links.clone
      safe_array.flatten!
    end

    return safe_array || nil
      

  end

  class BookmarksError < RuntimeError; end

end

include Bookmarks

OK = 200
CREATED = 201
ACCEPTED = 202
NON_AUTHORITATIVE_INFORMATION = 203
NO_CONTENT = 204
RESET_CONTENT = 205
PARTIAL_CONTENT = 206
MOVED_PERMANENTLY = 301
FOUND = 302
SEE_OTHER = 303
TEMPORARY_REDIRECT = MOVED_TEMPORARILY = 307
BAD_REQUEST = 400
UNAUTHORIZED = 401
FORBIDDEN = 403
NOT_FOUND = 404
PROXY_AUTHENTICATE_REQUIRED = 407
INTERNAL = 500

STATUS_CODE_MAP = {
	OK => 'OK',
	CREATED => "Created",
	NON_AUTHORITATIVE_INFORMATION => "Non-Authoritative Information",
	NO_CONTENT => "No Content",
	RESET_CONTENT => "Reset Content",
	PARTIAL_CONTENT => "Partial Content",
	MOVED_PERMANENTLY => 'Moved Permanently',
	FOUND => 'Found',
	SEE_OTHER => 'See Other',
	TEMPORARY_REDIRECT => 'Temporary Redirect',
	MOVED_TEMPORARILY => 'Temporary Redirect',
	BAD_REQUEST => 'Bad Request',
	INTERNAL => 'Internal Server Error',
  FORBIDDEN => "Forbidden",
  NOT_FOUND => "Not Found",
}

# only test links if a last run.json doens't exist, just parse the data
test =  !File.exist?("last_run.json")
page = load_bookmarks 'safaribookmarks.html'
links = get_links(:safari, page)


bar = TTY::ProgressBar.new("Testing #{links.size} Bookmarks [:bar]", total: links.size)

case test
when true
  # Set up some tables for storing info 
  results = Concurrent::Array.new

  puts "Testing bookmarks..."


  pool = Concurrent::FixedThreadPool.new(Concurrent::processor_count)  
  
  links.each do |link|
    pool.post do 
      results << { link: link, code: Unirest.get(link).code }
      bar.advance
    end
  end

  puts "===== Working ===== "
  while pool.queue_length > 0
   sleep 1
  end

  File.open('last_run.json', 'w') do |file|
    file.write(JSON.generate(results))
    file.close
  end

  puts
  puts  "Finished"
when false

  puts "Loading data from file"
  results = JSON.parse(File.open("last_run.json").read, { :symbolize_names => true })
end


# Testing code
codes = results.collect do |n|
  n[:code]
end.uniq

puts codes




counts = results.reduce(Hash.new(0)) do |s,n|  
  s[n[:code]] += 1
  s
end 

table = TTY::Table.new(header: ['Response', 'Count']) do |t|
  counts.each do |k,v|
    t << [STATUS_CODE_MAP[k],v]
  end
end


table.display
