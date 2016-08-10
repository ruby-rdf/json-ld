#!/usr/bin/env ruby
require "bundler/setup"
require 'json/ld'
require 'benchmark/ips'

source = JSON.parse %({
  "@context": "http://schema.org/",
  "@type": "SoftwareApplication",
  "name": "EtherSia",
  "description": "IPv6 library for the ENC28J60 Ethernet controller",
  "url": "https://github.com/njh/EtherSia",
  "author": {
    "@type": "Person",
    "name": "Nicholas Humfrey <njh@aelius.com>"
  },
  "applicationCategory": "Communication",
  "operatingSystem": "Arduino",
  "downloadUrl": "http://downloads.arduino.cc/libraries/njh/EtherSia-1.0.0.zip",
  "softwareVersion": "1.0.0",
  "fileSize": 77
})


Benchmark.ips do |x|
  x.config(time: 10, warmup: 1)
  x.report('toRdf') {JSON::LD::API.toRdf(source)}
end
