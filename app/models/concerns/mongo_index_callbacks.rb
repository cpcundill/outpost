module MongoIndexCallbacks

    extend ActiveSupport::Concern

    attr_accessor :skip_mongo_callbacks

    included do
        after_save :update_index, unless: :skip_mongo_callbacks
    end

    def update_index
        client = Mongo::Client.new(ENV["MONGODB_URI"] || 'mongodb://127.0.0.1:27017/outpost_development')
        collection = client.database[:indexed_services]
        if self.approved?
            collection.find_one_and_update({id: self.id}, self.as_json, {upsert: true})
        elsif self.last_approved_snapshot
            collection.find_one_and_update({id: self.id}, self.last_approved_snapshot.object, {upsert: true})
        end
    end

end