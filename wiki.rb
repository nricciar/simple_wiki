require 'sinatra-s3'
require 'parser'

S3::Application.callback :mime_type => 'text/wiki' do
  headers["Content-Type"] = "text/html; charset=UTF-8"
  p = { "PAGENAME" => @slot.name, "NAMESPACE" => WikiCloth::Parser.localise_ns(@bucket.name,:en) }
  headers.each { |k,v| p[$1.upcase.gsub(/\-/,'_')] = v if k =~ /x-amz-(.*)/ }

  @wiki = WikiParser.new({
    :data => params[:preview] ? params[:file] : (response.body.respond_to?(:read) ? response.body.read : response.body.to_s),
    :params => p,
    :use_cache => params.has_key?('version-id') || params[:preview] ? false : true,
    :locale => I18n.locale
  })

  if params.has_key?('edit')
    r :edit, I18n.t("editing page", :name => @slot.name.gsub(/_/,' '))
  elsif params.has_key?('diff')
    @diff = Bit.diff(params[:diff],params[:to])
    r :diff, I18n.t("changes to", :name => @slot.name.gsub(/_/,' '))
  elsif params.has_key?('history')
    @history = Slot.find(:all, :conditions => [ 'name = ? AND parent_id = ?', @slot.name, @slot.parent_id ], :order => "id DESC", :limit => 20)
    r :history, I18n.t("revision history", :name => @slot.name.gsub(/_/,' '))
  else
    if WikiCloth::Parser.namespace_type(@wiki.namespace) == :category
      @cat_links = {}
      PageLink.find(:all, :conditions => [ 'page_link = ? AND link_type = ?', @slot.name, 'category' ]).each do |cat|
        first_char = cat.page_name[0,1].upcase
        first_char = first_char =~ /^[A-Z]$/ ? first_char : '#'
        @cat_links[first_char] ||= []
        @cat_links[first_char] << cat.page_name
      end
      @cat_links = @cat_links.to_a.sort { |x,y| x[0] <=> y[0] }
      r :category, @slot.name.gsub(/_/,' ')
    else
      r :wiki, @slot.name.gsub(/_/,' ')
    end
  end
end

S3::Application.callback :error => 'NoSuchKey' do
  headers["Content-Type"] = "text/html; charset=UTF-8"
  if params.has_key?('edit')
    r :edit, I18n.t("edit page")
  elsif params.has_key?('preview') && params.has_key?('file')
    if env['PATH_INFO'] =~ /([^\/]+)\/(.*)$/
      p = { "NAMESPACE" => ($1 == "wiki" ? "" : WikiCloth::Parser.localise_ns($1,:en)), "PAGENAME" => $2.split("/").last.gsub('_',' ') }
    else
      p = { "PAGENAME" => "Main Page", "NAMESPACE" => "" }
    end
    @wiki = WikiParser.new({ :data => params[:file], :params => p, :use_cache => false, :locale => I18n.locale })
    r :wiki, p["PAGENAME"]
  else
    r :does_not_exist, I18n.t("page does not exist")
  end
end

S3::Application.callback :error => 'AccessDenied' do
  if env['PATH_INFO'].nil? || env['PATH_INFO'] == '/'
    redirect '/wiki/Main_Page'
  else
    status 401
    headers["WWW-Authenticate"] = %(Basic realm="wiki")
    headers["Content-Type"] = "text/html"
    r :access_denied, I18n.t("access denied")
  end
end

S3::Application.callback :when => 'before' do
  if env['HTTP_AUTHORIZATION'].to_s =~ /AWS/
    disable_callbacks_for_request
  else
    # update section
    if params[:section] && params[:file]
      wiki = WikiParser.new({ :data => params[:file], :params => { } })
      params[:section].each { |k,v| wiki.put_section(k, v) }
      params[:file] = wiki.to_wiki
    end

    #fix some caching issues
    if params.any? { |k,v| ["edit","history","diff"].include?(k) }
      env.delete('HTTP_IF_MODIFIED_SINCE')
      env.delete('HTTP_IF_NONE_MATCH')
    end

    if params[:preview]
      env.delete('HTTP_IF_MODIFIED_SINCE')
      env.delete('HTTP_IF_NONE_MATCH')
      env["REQUEST_METHOD"] = "GET"
    end

    auth = Rack::Auth::Basic::Request.new(env)
    next unless auth.provided? && auth.basic?

    user = User.find_by_login(auth.credentials[0])
    next if user.nil?

    # Convert a valid basic authorization into a proper S3 AWS
    # Authorization header
    if user.password == hmac_sha1( auth.credentials[1], user.secret )
      uri = env['PATH_INFO']
      uri += "?" + env['QUERY_STRING'] if S3::RESOURCE_TYPES.include?(env['QUERY_STRING'])
      canonical = [env['REQUEST_METHOD'], env['HTTP_CONTENT_MD5'], env['CONTENT_TYPE'],
        (env['HTTP_X_AMZ_DATE'] || env['HTTP_DATE']), uri]
      env['HTTP_AUTHORIZATION'] = "AWS #{user.key}:" + hmac_sha1(user.secret, canonical.map{|v|v.to_s.strip} * "\n")
    end
  end
end

class S3::Application < Sinatra::Base; enable :inline_templates; end

__END__

@@ layout
%html{ :dir => "ltr" }
  %head
    %title #{@title}
    %style{:type => "text/css"} @import '/control/s/css/control.css';
    %style{:type => "text/css"} @import '/wiki.css';
    %script{ :type => "text/javascript", :language => "JavaScript", :src => "/control/s/js/prototype.js" }
    %script{ :type => "text/javascript", :language => "JavaScript", :src => "/wiki.js" }
  %body
    %div#header
      %h1
        %a{:href => "/"} Simple Wiki
    %div#page
      - if status < 300
        %div.menu
          %ul
            %li
              %a{ :href => "#{env['PATH_INFO']}", :class => (!params.any? { |k,v| ["diff","history","edit"].include?(k) } ? "active" : "") }= I18n.t("content tab")
            %li
              %a{ :href => "#{env['PATH_INFO']}?edit", :class => (params.has_key?('edit') ? "active" : "") }= I18n.t("edit tab")
            - if defined?(Git)
              %li
                %a{ :href => "#{env['PATH_INFO']}?history", :class => (params.any? { |k,v| ["diff","history"].include?(k) } ? "active" : "") }= I18n.t("history tab")
      %h1 #{env['PATH_INFO'] =~ /\/([^\/]+)$/ ? "#{$1.gsub('_',' ')}" : "Sinatra-S3 Wiki"}
      = yield

@@ access_denied
%h2= I18n.t("access denied")
%p= I18n.t("access denied message")

@@ diff
%div#content
  %p= I18n.t("change summary", :insertions => @diff.stats[:total][:insertions], :deletions => @diff.stats[:total][:deletions])
  - @lines = @diff.patch.gsub('<','&lt;').gsub('>','&gt;').split("\n")
  - @lines[4..-1].each do |line|
    - case
    - when line =~ /\-([0-9]+)(,([0-9]+)|) \+([0-9]+),([0-9]+)/
      %div{ :style => "font-weight:bold;padding:5px 0" }= I18n.t("line no", :line => $1)
    - when line[0,1] == "\\"
    - when line[0,1] == "+"
      %ins{ :style => "background-color:#99ff99" } &nbsp;#{line[1,line.length]}
    - when line[0,1] == "-"
      %del{ :style => "background-color:#ff9999" } &nbsp;#{line[1,line.length]}
    - else
      %div{ :style => "background-color:#ebebeb" } &nbsp;#{line}

@@ does_not_exist
%h2= I18n.t("page does not exist")
%p
  = I18n.t("page does not exist message")
  %a{ :href => "#{env['PATH_INFO']}?edit" }= I18n.t("create it")
  ?

@@ edit
%h2 #{@slot.nil? ? I18n.t("edit page") : I18n.t("editing page", :name => @wiki.full_page_name.gsub(/_/,' '))}
%form#edit_page_form.create{ :method => "POST", :action => env['PATH_INFO'] }
  %input{ :type => "hidden", :name => "redirect", :value => env['PATH_INFO'] }
  %input{ :type => "hidden", :name => "Content-Type", :value => "text/wiki" }
  %div.required
    %label{ :for => "page_contents" }= I18n.t("contents")
    - if !params["edit"].blank?
      %textarea{ :name => "section[#{params[:edit]}]", :id => "page_contents", :style => "width:100%;height:20em" }
        = preserve @wiki.get_section(params[:edit]).gsub(/&/,'&amp;')
      %input{ :type => "hidden", :name => "file", :value => @wiki.to_wiki }
    - else
      %textarea{ :name => "file", :id => "page_contents", :style => "width:100%;height:20em" }
        = preserve @wiki.nil? ? "" : @wiki.to_wiki.gsub(/&/,'&amp;')
  %div.required
    %label{ :for => "page_summary" }= I18n.t("summary")
    %input{ :type => "text", :name => "x-amz-meta-comment", :id => "page_summary" }
  %input{ :type => "submit", :value => I18n.t("update"), :onclick => "this.form.target='_self';return true;" }
  %input{ :type => "submit", :value => I18n.t("preview"), :name => "preview", :onclick => "this.form.target='_blank';return true;" }
- @wiki.to_html( :blahtex_png_path => File.join(File.dirname(__FILE__),'public/math') ) unless @wiki.nil?
- unless @wiki.nil? || @wiki.included_templates.empty?
  %h3= I18n.t("resources")
  %ul
    - @wiki.included_templates.each do |key,value|
      %li
        %a{ :href => "/templates/#{key}" }= key

@@ history
%h2= I18n.t("revision history", :name => @slot.name.gsub(/_/,' '))
%form{ :action => env['PATH_INFO'], :method => "GET" }
  %table#revision_history
    - @history.each_with_index do |rev, count|
      %tr
        - if @history.length > 1
          %td.check
            %input.from{ :type => "radio", :name => "diff", :value => rev.version, :checked => (count == 1 ? true : false), :style => (count > 0 ? nil : "display:none") }
          %td.check
            %input.to{ :type => "radio", :name => "to", :value => rev.version, :checked => (count == 0 ? true : false) }
        %td
          %a{ :href => "#{env['PATH_INFO']}?version-id=#{rev.version}" } #{rev.meta['comment']}
          on #{rev.updated_at}
  - if @history.length > 1
    %input{ :type => "submit", :value => I18n.t("compare revisions") }

@@ wiki
%div#wiki_page
  = preserve @wiki.to_html( :blahtex_png_path => File.join(File.dirname(__FILE__),'public/math'), :blahtex_html_prefix => "/math/" )
- unless @wiki.categories.empty?
  %div#catlinks.catlinks
    %div#mw-normal-catlinks
      %a{ :href => "/special/Categories", :title => "Special:Categories" }= WikiCloth::Parser.localise_ns("Category") + ":"
      %ul
        - for cat in @wiki.categories
          %li
            %a{ :href => "/category/#{cat.strip.gsub(/\s+/,'_')}" }= cat

@@ category
%div#wiki_page
  = preserve @wiki.to_html( :blahtex_png_path => File.join(File.dirname(__FILE__),'public/math'), :blahtex_html_prefix => "/math/" )
%h2= I18n.t("pages in category", :category => @slot.name.gsub(/_/,' '))
- for cat in @cat_links
  %h3= cat.first
  %ul
    - for link in cat.last
      %li
        %a{ :href => "/wiki/#{link}" }= link.gsub(/_/,' ')
- unless @wiki.categories.empty?
  %div#catlinks.catlinks
    %div#mw-normal-catlinks
      %a{ :href => "/special/Categories", :title => "Special:Categories" }= WikiCloth::Parser.localise_ns("Category") + ":"
      %ul
        - for cat in @wiki.categories
          %li
            %a{ :href => "/category/#{cat.strip.gsub(/\s+/,'_')}" }= cat
