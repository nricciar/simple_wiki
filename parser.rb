require 'database'
require 'zlib'
require 'wikicloth'
require 'wikicloth/extensions/source'
require 'wikicloth/extensions/math'
require 'wikicloth/extensions/lua'
require 'wikicloth/extensions/capture'

class WikiParser < WikiCloth::Parser

  def initialize(options={})
    @options = { :params => { "NAMESPACE" => "" } }.merge(options)
    @bucket = Bucket.find_root(options[:params]['NAMESPACE'].blank? ? "wiki" : options[:params]['NAMESPACE'].downcase)

    unless options[:params]['PAGENAME'].nil?
      tmp = {}
      # retreive all cache fragments for page
      TemplateCache.find(:all, :conditions => ['page_name = ?', full_page_name]).each do |item|
        tmp[item.template_name] ||= {}
        tmp[item.template_name][item.md5] = item.content
      end
      # pass fragments to wikicloth
      options[:cache] = tmp
    end

    super(options)
  end

  def to_html(opt={})
    # get rendered document from wikicloth
    html = super(opt)

    unless self.internal_links.empty?
      # identify links that do not have pages yet
      fixed_in_links = self.internal_links.collect { |i| i.strip.gsub(/\s+/,'_') }.uniq
      Slot.find(:all, :conditions => ['deleted = 0 AND parent_id = ? AND name IN(?)', @bucket.id, fixed_in_links]).each do |slot|
        md5 = Zlib.crc32(slot.name)
        fixed_in_links.delete(slot.name)
        html.gsub!(/ILINK#{md5}/, "")
      end
      # assign new css class to all links for pages that do not exist
      fixed_in_links.each do |in_link|
        md5 = Zlib.crc32(in_link)
        html.gsub!(/ILINK#{md5}/, "new")
      end
    end

    # save link info to db
    PageLink.delete_all [ "page_name = ?", full_page_name ]
    self.categories.each { |c| PageLink.create(:page_name => full_page_name, :page_link => c.strip.gsub(/\s+/,'_'), :link_type => "category" ) }
    self.internal_links.each { |i| PageLink.create(:page_name => full_page_name, :page_link => i.strip.gsub(/\s+/,'_'), :link_type => "internal" ) }
    self.external_links.each { |e| PageLink.create(:page_name => full_page_name, :page_link => e.strip.gsub(/\s+/,'_'), :link_type => "external" ) }
    self.languages.each { |k,v| PageLink.create(:page_name => full_page_name, :page_link => "#{k}:#{v.strip.gsub(/\s+/,'_')}", :link_type => "language" ) }

    # FIXME: need to clear out old unused template cache fragments

    # return html
    html
  end

  def page_name
    @options[:params]['PAGENAME'].gsub(/\s+/,'_')
  end

  def full_page_name
    @bucket.name != "wiki" ? "#{namespace}:#{page_name}" : page_name
  end

  def namespace
    WikiCloth::Parser.localise_ns(@bucket.name, @options[:locale] || :en)
  end

  section_link do |section|
    "?edit&section=#{section}"
  end

  url_for do |page|
    p = "/wiki/#{page.strip.gsub(/\s+/,'_')}"
    p = "/#{$1.downcase}/#{$2}" if page =~ /^([A-Za-z]+):(.*)$/
    p
  end

  link_attributes_for do |page|
    { :href => url_for(page), :class => "ILINK#{Zlib.crc32(page.strip.gsub(/\s+/,'_'))}" }
  end

  external_link do |url,text|
    self.external_links << url
    "<a href=\"#{url}\" target=\"_blank\" class=\"exlink\">#{text.blank? ? url : text}</a>"
  end

  cache do |item|
    tmp = TemplateCache.find(:first, :conditions => [ 'page_name = ? AND template_name = ? AND md5 = ?', self.page_name, item[:name], item[:md5] ])
    return unless tmp.nil?
    TemplateCache.create(:page_name => page_name, :template_name => item[:name], :md5 => item[:md5], :content => item[:content])
  end

  template do |template|
    case template
    when "FULLPAGENAMEE"
      ret = self.params.has_key?("NAMESPACE") && !self.params["NAMESPACE"].blank? ? "#{self.params["NAMESPACE"]}:" : ""
      ret += self.params["PAGENAME"]
    when "CURRENTYEAR"
      Time.now.year.to_s
    when "CURRENTMONTH"
      Time.now.strftime("%d")
    when "CURRENTMONTHNAME"
      Time.now.strftime("%B")
    when "CURRENTMONTHABBREV"
      Time.now.strftime("%b")
    when "CURRENTDAY"
      Time.now.strftime("%e")
    when "CURRENTDAY2"
      Time.now.strftime("%d")
    when "CURRENTDOW"
      Time.now.strftime("%u")
    when "CURRENTDAYNAME"
      Time.now.strftime("%A")
    when "CURRENTTIME"
      Time.now.strftime("%R")
    when "CURRENTHOUR"
      Time.now.strftime("%H")
    when "CURRENTWEEK"
      Time.now.strftime("%U").to_i.to_s
    when "CURRENTTIMESTAMP"
      Time.now.strftime("%Y%m%d%H%M%S")
    when "SITENAME"
      "Simple Wiki"
    when "CURRENTVERSION"
      WikiCloth::VERSION
    else
      begin
        slot = Bucket.find_root('templates').find_slot(template.to_s.strip.gsub(/\s+/,'_'))
        slot.nil? ? nil : File.read(File.join(S3::STORAGE_PATH, slot.obj.path))
      rescue S3::NoSuchKey
        nil
      end
    end
  end

end
