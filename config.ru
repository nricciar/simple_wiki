require 'rubygems'
require 'sinatra-s3'
require 'wiki'

use S3::Tracker if defined?(RubyTorrent)
use S3::Admin
run S3::Application