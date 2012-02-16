require 'rubygems'
require 'bundler'
Bundler.require

require 'sinatra-s3/tasks'

namespace :db do
  desc "Setup Wiki"
  task(:setup_wiki => :migrate) do
    begin
      Bucket.find_root('wiki')
      puts "Wiki aready setup."
    rescue S3::NoSuchBucket
      wiki_owner = User.find_by_login('wiki')
      if wiki_owner.nil?
	class S3KeyGen
	  include S3::Helpers
	  def secret() generate_secret(); end;
	  def key() generate_key(); end;
	end
	puts "** No wiki user found, creating the `wiki' user."
	wiki_owner = User.create :login => "wiki", :password => S3::DEFAULT_PASSWORD,
	  :email => "wiki@parkplace.net", :key => S3KeyGen.new.key(), :secret => S3KeyGen.new.secret(),
	  :activated_at => Time.now
      end
      wiki_bucket = Bucket.create(:name => 'wiki', :owner_id => wiki_owner.id, :access => 438)
      templates_bucket = Bucket.create(:name => 'templates', :owner_id => wiki_owner.id, :access => 438)
      if defined?(Git)
	puts "** Creating the `wiki' and `templates' namespaces."
	wiki_bucket.git_init
	templates_bucket.git_init
      else
	puts "!! Git support not found therefore Wiki history is disabled."
      end
      puts "Wiki setup."
    end
  end
end
