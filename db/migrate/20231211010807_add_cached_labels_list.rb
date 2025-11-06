class AddCachedLabelsList < ActiveRecord::Migration[7.0]
  def change
    add_column :conversations, :cached_label_list, :string
    # Note: ActsAsTaggableOn::Taggable::Cache.included(Conversation) removed
    # as it's not safe to call during migrations and will be automatically
    # applied when the model is loaded in the application context
  end
end
