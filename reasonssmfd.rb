#!/usr/bin/ruby

require 'socket'
require 'yaml'

load "/etc/reasonssmf/config.rb" rescue abort "Failed to read config file."

begin
UNIXServer.open(LDA_SOCK_PATH) do |serv|
  File.chmod
  while s = serv.accept
    begin
      param = YAML.load(s)
    rescue
      next
    end
    cmdline = [LDA_PATH, "-d", param["dest"] ]
    cmdline += ["-m", param["folder"] ] if param["folder"]
    IO.popen(cmdline, "w") {|io| io.write param["mail"]}
    if $?.exitstatus != 0
      File.open("/var/log/reasonssmf.log", "a") do |f|
        f.flock(File::LOCK_EX)
        f.puts("#{Time.now}\tLDA exitted by status #{$?.exitstatus}")
        f.flock(File::LOCK_UN)
      end
      IO.popen(["sendmail", "-i", "-f", "root", ADMIN_DESTINATION])
    end
  end
end
ensure
  File.delete(LDA_SOCK_PATH)
end
