ActiveRecord::Migration.class_eval do
  unless ActiveRecord::Base.connection.table_exists? 'template_caches'
    create_table :template_caches do |t|
      t.string :page_name
      t.string :template_name
      t.string :md5
      t.text :content
    end
  end
  unless ActiveRecord::Base.connection.table_exists? 'page_links'
    create_table :page_links do |t|
      t.string :page_name
      t.string :page_link
      t.column :link_type
    end
  end
end

class TemplateCache < ActiveRecord::Base
end
class PageLink < ActiveRecord::Base
end
