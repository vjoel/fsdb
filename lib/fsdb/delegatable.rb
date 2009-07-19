module Delegatable
  def delegate h
    h.each do |meth, reader|
      module_eval %{
        def #{meth}(*args, &block); #{reader}.#{meth}(*args, &block); end
      }
    end
  end
end
  
    def browse(&block);  @db.browse(path, &block);  end
    def edit(&block);    @db.edit(path, &block);    end
    def replace(&block); @db.replace(path, &block); end
    def insert(&block);  @db.insert(path, &block);  end
    def delete(&block);  @db.delete(path, &block);  end
    def fetch(&block);   @db.fetch(path, &block);   end

    extend Delegatable
    delegate :browse => "@db", :edit => "@db", :replace => "@db",
             :insert => "@db", :delegate => "@db", :fetch => "@db"
    
