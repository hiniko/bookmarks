#!/usr/bin/env ruby 
#
#
#
require 'rubygems'
require 'nokogiri'
require 'httparty'
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

ACCEPTED = 202
BAD_REQUEST = 400
CREATED = 201
FORBIDDEN = 403
FOUND = 302
INTERNAL = 500
MOVED_PERMANENTLY = 301
NON_AUTHORITATIVE_INFORMATION = 203
NOT_ACCEPTABLE = 406
NOT_ALLOWED = 405
NOT_FOUND = 404
NO_CONTENT = 204
OK = 200
PARTIAL_CONTENT = 206
PROXY_AUTHENTICATE_REQUIRED = 407
RESET_CONTENT = 205
SEE_OTHER = 303
TEMPORARY_REDIRECT = MOVED_TEMPORARILY = 307
UNAUTHORIZED = 401
UNAVAILABLE = 503
DNS_ERROR = 666666

STATUS_CODE_MAP = {
  BAD_REQUEST => 'Bad Request',
  CREATED => "Created",
  FOUND => 'Found',
  INTERNAL => 'Internal Server Error',
  MOVED_PERMANENTLY => 'Moved Permanently',
  MOVED_TEMPORARILY => 'Temporary Redirect',
  NON_AUTHORITATIVE_INFORMATION => "Non-Authoritative Information",
  NO_CONTENT => "No Content",
  OK => 'OK',
  PARTIAL_CONTENT => "Partial Content",
  RESET_CONTENT => "Reset Content",
  SEE_OTHER => 'See Other',
  TEMPORARY_REDIRECT => 'Temporary Redirect',
  FORBIDDEN => "Forbidden",
  NOT_ACCEPTABLE => "Not Acceptable",
  NOT_ALLOWED => "Method Not Allowed",
  NOT_FOUND => "Not Found",
  UNAVAILABLE => "Service Unavailable",
  DNS_ERROR => "DNS Lookup Failed",
}

# only test links if a last run.json doens't exist, just parse the data
test =  !File.exist?("last_run.json")
page = load_bookmarks 'safaribookmarks.html'

links = get_links(:safari, page)

links = links.slice(1,100)


bar = TTY::ProgressBar.new("Testing Bookmarks (:current/#{links.size}) [:bar] ", head: '>>', total: links.size)

case test
when true
  # Set up some tables for storing info 
  results = Concurrent::Array.new

  pool = Concurrent::FixedThreadPool.new(Concurrent::processor_count, max_queue: 1000)  
  
  links.each do |link|
    pool.post do 
      #puts "#{pool.scheduled_task_count} - #{pool.completed_task_count} - #{link}"
      begin
	code = HTTParty.head(link, timeout: 5, follow_redirects: true)
	puts "got link #{link}"
	results << { link: link, code: code }
      rescue SocketError  
	results << {link: link, code: 666666}
      end
      bar.advance
      bar.log("(#{bar.current}) " + link)
    end
  end

  while !bar.complete?
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


counts = results.reduce(Hash.new(0)) do |s,n|  
  s[n[:code]] += 1
  s
end 

table = TTY::Table.new(header: ['Response', 'Count']) do |t|
  counts.each do |k,v|
    t << [ (STATUS_CODE_MAP[k] ? "#{STATUS_CODE_MAP[k]} (#{k})" : "Unknown Code (#{k})") ,v]
  end
end


puts table.render(:unicode, width: 80)
