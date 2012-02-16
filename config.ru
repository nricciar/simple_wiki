require 'rubygems'
require 'bundler'
require 'i18n'
I18n.load_path += Dir[File.join(File.dirname(__FILE__),"lang/*.yml")].collect

Bundler.require

require 'wiki'

use S3::Tracker if defined?(RubyTorrent)
use S3::Admin
run S3::Application
