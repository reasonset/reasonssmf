#!/usr/bin/ruby

require 'mail'
require 'date'
require 'socket'
require 'yaml'

tmpfile = "/tmp/mailfilter.#{$$}"
MAILCONTENT = STDIN.read
STATUS_CONTAINER = {exitstatus: nil}
CUR_USER = ARGV[0]
FILTER_TARGET = ARGV[1]
LDA_PATH = "/var/run/dovelda.sock"
File.open(tmpfile, "w") {|f| f.write MAILCONTENT }

def deliver_mail(folder=nil)
  UNIXSocket.open(LDA_PATH) do |sock|
    YAML.dump({"dest" => CUR_USER, "folder" => folder, "mail" => MAILCONTENT}, sock)
  end
end

class MailObj
  attr_accessor :from, :subject, :futuredate, :date, :jpmail, :nilmail, :to, :content_type, :body, :sender, :header, :mailer, :list
  def initialize
    @body = nil
    @mailer = nil
    @list = nil
  end
  
  def save(folder=nil)
    deliver_mail(folder)
    throw :filter
  end
  
  def junk(reject=false)
    deliver_mail
    STATUS_CONTAINER[:exitstatus] = 67 if reject
    throw :filter
  end
  
  def reject
    STATUS_CONTAINER[:exitstatus] = 67
    throw :filter
  end
  
  def transport(to)
    io.popen(["sendmail", "-i", "-f", self.sender, to], "w") {|io| io.write MAILCONTENT}
    throw :filter
  end
  
  def filter
    raise "UNDEFINED FILTER #{FILTER_TARGET}" unless FILTER[FILTER_TARGET]
    FILTER[FILTER_TARGET].call(self)
  end
end

begin
  unless File.exist? "/etc/reasonssmf.rb"
    abort "Configuration File not exist."
  end

  load("/etc/reasonssmf.rb")

  mailparts = [ Mail.read(tmpfile) ]
  envmail = mail = mailparts.first

  m = MailObj.new
  nilmail = nil
  
  raw_source = mailparts.first.body.raw_source
  if raw_source.nil? || raw_source.empty?
    raise "UNREADABLE MESSAGE"
  end


  while (cm = mailparts.shift)&.multipart?
    cm.parts.each do |i|
      if i.multipart?
        mailparts.push(i)
      elsif %w:text/plain message/rfc822 text/html:.any? {|x| i.content_type&.downcase.to_s.include? x }
        mail = i
        break
      end
    end
  end


  if envmail.date && envmail.date > (Date.today + 1)
    m.futuredate = true
  else
    m.futuredate = false
  end

  begin
    if ( mail.decoded =~ /\p{Kana}|\p{Hiragana}|\p{Katakana}/ )
      m.jpmail = true
    else
      m.jpmail = false
    end
  rescue
    m.jpmail = false
    nilmail = true
  end

  if nilmail || envmail.from_addrs.empty?
    m.nilmail = true
  else
    m.nilmail = false
  end

  m.from = envmail.from_addrs
  m.to = envmail.to_addrs
  m.subject = envmail.subject
  m.date = envmail.date
  m.sender = envmail.envelope_from
  m.content_type = mail.content_type
  m.header = envmail.header
  hd = envmail.header
  if hd["X-Mailer"]
    if hd["X-Mailer"].is_a? Array
      m.mailer = hd["X-Mailer"].map {|i| i.to_s }
    else
      m.mailer = [ hd["X-Mailer"].to_s ]
    end
  end
  if hd["X-Mailing-List"]
    if hd["X-Mailing-List"].is_a? Array
      m.mailer = hd["X-Mailing-List"].map {|i| i.to_s}
    else
      m.mailer = [ hd["X-Mailing-List"].to_s ]
    end
  end
  m.body = mail.decoded rescue nil

  catch(:filter) do
    m.filter
    deliver_mail
  end
rescue => e
  pp e
  deliver_mail
  File.open("/var/log/reasonssmf.log", "a") do |f|
    f.flock(File::LOCK_EX)
    f.puts("#{Time.now}\t#{e.to_s}")
    f.flock(File::LOCK_UN)
  end
ensure
  File.delete(tmpfile)
end

if STATUS_CONTAINER[:exitstatus]
  exit STATUS_CONTAINER[:exitstatus]
end
